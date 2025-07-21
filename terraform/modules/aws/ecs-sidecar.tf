# ECS Task Definition with nginx sidecar pattern (DISABLED - Using EKS instead)
/*
resource "aws_ecs_task_definition" "app_sidecar" {
  family                   = "${var.environment}-video-streaming-sidecar"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = local.task_cpu
  memory                   = local.task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn           = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name  = "nginx-proxy"
      image = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.environment}-video-streaming-nginx-sidecar:latest"
      
      portMappings = [
        {
          containerPort = 80
          protocol      = "tcp"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "nginx-proxy"
        }
      }

      healthCheck = {
        command = [
          "CMD-SHELL",
          "curl -f http://localhost:80/nginx-health || exit 1"
        ]
        interval    = 30
        timeout     = 10
        retries     = 3
        startPeriod = 60
      }

      essential = true
    },
    {
      name  = "frontend"
      image = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.environment}-video-streaming-frontend-sidecar:latest"
      
      portMappings = [
        {
          containerPort = 3000
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "NODE_ENV"
          value = "production"
        },
        {
          name  = "REACT_APP_API_URL"
          value = "https://${var.domain_name}/api"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "frontend"
        }
      }

      healthCheck = {
        command = [
          "CMD-SHELL",
          "curl -f http://localhost:3000 || exit 1"
        ]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 30
      }

      essential = true
    },
    {
      name  = "backend"
      image = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.environment}-video-streaming-backend:latest"
      
      portMappings = [
        {
          containerPort = 5050
          protocol      = "tcp"
        },
        {
          containerPort = 8080
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "DATABASE_URL"
          value = "postgres://postgres:${random_password.db_password.result}@${aws_db_instance.main.endpoint}/video_streaming_db"
        },
        {
          name  = "REDIS_URL"
          value = "rediss://${aws_elasticache_replication_group.main.primary_endpoint_address}:6379"
        },
        {
          name  = "S3_BUCKET"
          value = aws_s3_bucket.videos.bucket
        },
        {
          name  = "AWS_REGION"
          value = var.region
        },
        {
          name  = "AWS_DEFAULT_REGION"
          value = var.region
        },
        {
          name  = "CORS_ALLOWED_ORIGINS"
          value = "https://${var.domain_name},http://localhost:3000"
        },
        {
          name  = "JWT_SECRET"
          value = random_password.jwt_secret.result
        },
        {
          name  = "RUST_LOG"
          value = "info"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "backend"
        }
      }

      healthCheck = {
        command = [
          "CMD-SHELL",
          "curl -f http://localhost:5050/api/status || exit 1"
        ]
        interval    = 60
        timeout     = 30
        retries     = 3
        startPeriod = 300
      }

      essential = true
    }
  ])

  tags = var.common_tags
}

# Generate JWT secret
resource "random_password" "jwt_secret" {
  length  = 32
  special = true
}

# IAM user for S3 access (for MinIO compatibility)
resource "aws_iam_user" "s3_user" {
  name = "${var.environment}-video-streaming-s3-user"
  tags = var.common_tags
}

resource "aws_iam_access_key" "s3_user" {
  user = aws_iam_user.s3_user.name
}

resource "aws_iam_user_policy" "s3_user" {
  name = "${var.environment}-video-streaming-s3-user-policy"
  user = aws_iam_user.s3_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.videos.arn,
          "${aws_s3_bucket.videos.arn}/*"
        ]
      }
    ]
  })
}

# Update ALB target group for nginx proxy
resource "aws_lb_target_group" "nginx_proxy" {
  name        = "${var.environment}-video-streaming-nginx-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/nginx-health"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 10
    unhealthy_threshold = 3
  }

  tags = var.common_tags
}


# Update security group for nginx proxy
resource "aws_security_group" "nginx_proxy" {
  name_prefix = "${var.environment}-video-streaming-nginx-"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.environment}-video-streaming-nginx-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Allow nginx proxy to communicate with containers (internal communication within the same task)
resource "aws_security_group_rule" "ecs_internal_frontend" {
  type              = "ingress"
  from_port         = 3000
  to_port           = 3000
  protocol          = "tcp"
  cidr_blocks       = ["10.0.0.0/16"]  # Allow from VPC CIDR
  security_group_id = aws_security_group.ecs.id
}

resource "aws_security_group_rule" "ecs_internal_backend_api" {
  type              = "ingress"
  from_port         = 5050
  to_port           = 5050
  protocol          = "tcp"
  cidr_blocks       = ["10.0.0.0/16"]  # Allow from VPC CIDR
  security_group_id = aws_security_group.ecs.id
}

resource "aws_security_group_rule" "ecs_internal_backend_ws" {
  type              = "ingress"
  from_port         = 8080
  to_port           = 8080
  protocol          = "tcp"
  cidr_blocks       = ["10.0.0.0/16"]  # Allow from VPC CIDR
  security_group_id = aws_security_group.ecs.id
}

# ECS Service with sidecar pattern
resource "aws_ecs_service" "main_sidecar" {
  name            = "${var.environment}-video-streaming-sidecar"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app_sidecar.arn
  desired_count   = var.server_count
  launch_type     = "FARGATE"

  network_configuration {
    security_groups  = [aws_security_group.ecs.id]
    subnets          = aws_subnet.private[*].id
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.nginx_proxy.arn
    container_name   = "nginx-proxy"
    container_port   = 80
  }

  depends_on = [
    aws_lb_listener.https,
    aws_iam_role_policy_attachment.ecs_task_execution
  ]

  tags = var.common_tags
}

# ECR Repository for nginx sidecar
resource "aws_ecr_repository" "nginx_sidecar" {
  name                 = "${var.environment}-video-streaming-nginx-sidecar"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = var.common_tags
}

# ECR Repository for frontend sidecar
resource "aws_ecr_repository" "frontend_sidecar" {
  name                 = "${var.environment}-video-streaming-frontend-sidecar"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = var.common_tags
}
*/

# ECS Sidecar configuration is disabled for EKS deployment
# To use ECS instead of EKS, uncomment the above resources and 
# uncomment the ECS resources in main.tf
