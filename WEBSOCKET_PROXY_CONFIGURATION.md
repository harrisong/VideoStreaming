# WebSocket Proxy Configuration

This document outlines the configuration changes made to proxy WebSocket traffic through nginx on port 80 and ALB on port 443 for both live comments and watch party features.

## Changes Made

### 1. Nginx Configuration (`frontend/nginx.conf`)

Added WebSocket proxy configuration to handle `/api/ws/` paths:

```nginx
# WebSocket proxy for live comments and watch party
location /api/ws/ {
    proxy_pass http://localhost:8080;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_cache_bypass $http_upgrade;
    proxy_read_timeout 86400;
    proxy_send_timeout 86400;
}
```

**Key Features:**
- Proxies WebSocket traffic from port 80 to backend port 8080
- Sets proper WebSocket upgrade headers
- Configures long timeouts (24 hours) for persistent connections
- Bypasses cache for WebSocket connections

### 2. Frontend Configuration (`frontend/src/config.ts`)

Updated WebSocket URL configuration comment to reflect the new proxy setup:

```typescript
const getApiBaseUrl = (): string => {
  // In production, use the current domain without port (load balancer handles routing)
  // In development, use localhost with port 80 (nginx proxies to backend port 5050)
  if (process.env.NODE_ENV === 'production') {
    return window.location.origin;
  }
  return 'http://localhost';
};

const getWebSocketUrl = (): string => {
  // In production, use the current domain with ws/wss protocol through port 80/443 (nginx proxies to backend)
  // In development, use localhost with port 80 (nginx proxies to backend port 8080)
  if (process.env.NODE_ENV === 'production') {
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    return `${protocol}//${window.location.host}`;
  }
  return 'ws://localhost';
};
```

**Key Features:**
- Both production and development now use standard HTTP/HTTPS ports (80/443)
- Nginx handles the proxying to backend services in both environments
- API endpoints use port 80 → nginx → backend port 5050
- WebSocket endpoints use port 80 → nginx → backend port 8080

### 3. ALB Configuration (`terraform/modules/aws/main.tf`)

#### CloudFront Origin Configuration
Changed CloudFront to use HTTPS-only communication with ALB:

```hcl
custom_origin_config {
  http_port              = 80
  https_port             = 443
  origin_protocol_policy = "https-only"
  origin_ssl_protocols   = ["TLSv1.2"]
}
```

#### Enhanced WebSocket Listener Rules
Added two listener rules for better WebSocket handling:

1. **Primary WebSocket Rule (Priority 50):**
```hcl
resource "aws_lb_listener_rule" "websocket" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 50

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.websocket.arn
  }

  condition {
    path_pattern {
      values = ["/api/ws/*"]
    }
  }
}
```

2. **WebSocket Upgrade Rule (Priority 40):**
```hcl
resource "aws_lb_listener_rule" "websocket_upgrade" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 40

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.websocket.arn
  }

  condition {
    path_pattern {
      values = ["/api/ws/*"]
    }
  }

  condition {
    http_header {
      http_header_name = "Upgrade"
      values          = ["websocket"]
    }
  }
}
```

## Traffic Flow

### Production Environment

1. **Client → CloudFront (HTTPS/WSS)**
   - Client connects to `wss://yourdomain.com/api/ws/...`
   - CloudFront forwards to ALB via HTTPS

2. **CloudFront → ALB (HTTPS)**
   - ALB receives HTTPS request on port 443
   - WebSocket listener rules route `/api/ws/*` to WebSocket target group

3. **ALB → ECS Tasks (HTTP)**
   - ALB forwards to backend containers on port 8080
   - WebSocket upgrade handled by ALB

4. **ECS Frontend → ECS Backend (HTTP)**
   - Nginx in frontend container proxies WebSocket traffic
   - Backend WebSocket server handles connections on port 8080

### Development Environment

1. **Client → Nginx (HTTP/WS)**
   - Client connects to `http://localhost/api/...` for API calls
   - Client connects to `ws://localhost/api/ws/...` for WebSocket connections
   - Nginx running in Docker container on port 80

2. **Nginx → Services (HTTP)**
   - Frontend requests: Nginx → React dev server (port 3000)
   - API requests: Nginx → Backend (port 5050)
   - WebSocket requests: Nginx → Backend WebSocket server (port 8080)

## Docker Compose Configuration

The development environment now includes an nginx service that acts as a reverse proxy:

```yaml
services:
  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
    volumes:
      - ./frontend/nginx.dev.conf:/etc/nginx/conf.d/default.conf
    depends_on:
      - frontend
      - backend
    networks:
      - app-network

  frontend:
    # ... existing config
    expose:
      - "3000"  # Changed from ports to expose
```

The nginx.dev.conf configuration handles:
- Serving the React frontend through proxy to port 3000
- Proxying API calls to backend port 5050
- Proxying WebSocket connections to backend port 8080

## WebSocket Endpoints

Both live comments and watch party use the same proxy configuration:

- **Live Comments:** `/api/ws/comments/{video_id}`
- **Watch Party:** `/api/ws/watchparty/{video_id}`

## Benefits

1. **Simplified Port Management:** All traffic goes through standard HTTP/HTTPS ports
2. **Better Security:** HTTPS/WSS encryption end-to-end in production
3. **Load Balancer Integration:** ALB handles WebSocket connections with health checks
4. **Scalability:** Multiple backend instances can handle WebSocket connections
5. **Monitoring:** ALB provides metrics and logging for WebSocket connections

## Health Checks

The WebSocket target group includes health checks that accept multiple status codes:
- `200`: Normal HTTP response
- `400`: Bad request (expected for non-WebSocket requests)
- `426`: Upgrade required (WebSocket upgrade response)

This ensures the health check doesn't fail when testing WebSocket endpoints with regular HTTP requests.
