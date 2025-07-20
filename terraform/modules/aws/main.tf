# AWS Managed Services Module for Video Streaming Service
# Using ECS Fargate, RDS, ElastiCache, S3, CloudFront, and other managed services

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
      configuration_aliases = [aws.us_east_1]
    }
  }
}

# Variables
variable "domain_name" {
  description = "Domain name for the application"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "server_count" {
  description = "Number of ECS tasks to run"
  type        = number
  default     = 2
}

variable "instance_type" {
  description = "ECS task size (small, medium, large)"
  type        = string
  default     = "medium"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "ssh_public_key" {
  description = "SSH public key (not used in managed services)"
  type        = string
  default     = ""
}

variable "enable_load_balancer" {
  description = "Enable load balancer (always true for managed services)"
  type        = bool
  default     = true
}

variable "enable_monitoring" {
  description = "Enable enhanced monitoring"
  type        = bool
  default     = true
}

variable "common_tags" {
  description = "Common tags to apply to resources"
  type        = map(string)
  default     = {}
}

# Local values
locals {
  # ECS task sizes
  task_sizes = {
    small = {
      cpu    = 512
      memory = 1024
    }
    medium = {
      cpu    = 1024
      memory = 2048
    }
    large = {
      cpu    = 2048
      memory = 4096
    }
  }
  
  task_cpu    = local.task_sizes[var.instance_type].cpu
  task_memory = local.task_sizes[var.instance_type].memory
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

# VPC and Networking
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.common_tags, {
    Name = "${var.environment}-video-streaming-vpc"
  })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.common_tags, {
    Name = "${var.environment}-video-streaming-igw"
  })
}

# Public subnets for ALB
resource "aws_subnet" "public" {
  count = 2

  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.${count.index + 1}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.common_tags, {
    Name = "${var.environment}-video-streaming-public-${count.index + 1}"
    Type = "Public"
  })
}

# Private subnets for ECS and RDS
resource "aws_subnet" "private" {
  count = 2

  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index + 10}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = merge(var.common_tags, {
    Name = "${var.environment}-video-streaming-private-${count.index + 1}"
    Type = "Private"
  })
}

# NAT Gateway for private subnets
resource "aws_eip" "nat" {
  count = 2

  domain = "vpc"
  tags = merge(var.common_tags, {
    Name = "${var.environment}-video-streaming-nat-eip-${count.index + 1}"
  })
}

resource "aws_nat_gateway" "main" {
  count = 2

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(var.common_tags, {
    Name = "${var.environment}-video-streaming-nat-${count.index + 1}"
  })

  depends_on = [aws_internet_gateway.main]
}

# Route tables
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(var.common_tags, {
    Name = "${var.environment}-video-streaming-public-rt"
  })
}

resource "aws_route_table" "private" {
  count = 2

  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = merge(var.common_tags, {
    Name = "${var.environment}-video-streaming-private-rt-${count.index + 1}"
  })
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# Security Groups
resource "aws_security_group" "alb" {
  name_prefix = "${var.environment}-video-streaming-alb-"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.environment}-video-streaming-alb-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "ecs" {
  name_prefix = "${var.environment}-video-streaming-ecs-"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 5050
    to_port         = 5050
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    from_port       = 3000
    to_port         = 3000
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
    Name = "${var.environment}-video-streaming-ecs-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "rds" {
  name_prefix = "${var.environment}-video-streaming-rds-"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.environment}-video-streaming-rds-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "elasticache" {
  name_prefix = "${var.environment}-video-streaming-redis-"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }

  tags = merge(var.common_tags, {
    Name = "${var.environment}-video-streaming-redis-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# RDS PostgreSQL Database
resource "aws_db_subnet_group" "main" {
  name       = "${var.environment}-video-streaming-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = merge(var.common_tags, {
    Name = "${var.environment}-video-streaming-db-subnet-group"
  })
}

resource "random_password" "db_password" {
  length  = 16
  special = true
}

resource "aws_db_instance" "main" {
  identifier = "${var.environment}-video-streaming-db"

  engine         = "postgres"
  engine_version = "15.8"
  instance_class = "db.t3.micro"

  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = "video_streaming_db"
  username = "postgres"
  password = random_password.db_password.result

  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = aws_db_subnet_group.main.name

  backup_retention_period = 7
  backup_window          = "03:00-04:00"
  maintenance_window     = "sun:04:00-sun:05:00"

  skip_final_snapshot = true
  deletion_protection = false

  performance_insights_enabled = var.enable_monitoring

  tags = merge(var.common_tags, {
    Name = "${var.environment}-video-streaming-db"
  })
}

# ElastiCache Redis
resource "aws_elasticache_subnet_group" "main" {
  name       = "${var.environment}-video-streaming-redis-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = var.common_tags
}

resource "aws_elasticache_replication_group" "main" {
  replication_group_id       = "${var.environment}-video-streaming-redis"
  description                = "Redis cluster for video streaming service"

  node_type            = "cache.t3.micro"
  port                 = 6379
  parameter_group_name = "default.redis7"

  num_cache_clusters = 2

  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [aws_security_group.elasticache.id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true

  automatic_failover_enabled = true
  multi_az_enabled          = true

  tags = merge(var.common_tags, {
    Name = "${var.environment}-video-streaming-redis"
  })
}

# S3 Buckets
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# S3 bucket for video storage
resource "aws_s3_bucket" "videos" {
  bucket = "${var.environment}-video-streaming-videos-${random_id.bucket_suffix.hex}"

  tags = merge(var.common_tags, {
    Name = "${var.environment}-video-streaming-videos"
  })
}

resource "aws_s3_bucket_versioning" "videos" {
  bucket = aws_s3_bucket.videos.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "videos" {
  bucket = aws_s3_bucket.videos.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_cors_configuration" "videos" {
  bucket = aws_s3_bucket.videos.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST", "DELETE", "HEAD"]
    allowed_origins = ["https://${var.domain_name}"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

# S3 bucket for static assets
resource "aws_s3_bucket" "static" {
  bucket = "${var.environment}-video-streaming-static-${random_id.bucket_suffix.hex}"

  tags = merge(var.common_tags, {
    Name = "${var.environment}-video-streaming-static"
  })
}

# Keep S3 bucket private - CloudFront will access via OAI
resource "aws_s3_bucket_public_access_block" "static" {
  bucket = aws_s3_bucket.static.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# No public bucket policy needed - CloudFront OAI handles access

# CloudFront Distribution
resource "aws_cloudfront_distribution" "main" {
  origin {
    domain_name = aws_s3_bucket.static.bucket_regional_domain_name
    origin_id   = "S3-${aws_s3_bucket.static.bucket}"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.main.cloudfront_access_identity_path
    }
  }

  origin {
    domain_name = aws_lb.main.dns_name
    origin_id   = "ALB-${var.environment}-video-streaming"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  aliases = [var.domain_name]

  default_cache_behavior {
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "ALB-${var.environment}-video-streaming"
    compress               = true
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = true
      headers      = ["Host", "Authorization"]

      cookies {
        forward = "all"
      }
    }

    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
  }

  # WebSocket paths should bypass CloudFront and go directly to ALB
  ordered_cache_behavior {
    path_pattern     = "/api/ws/*"
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "ALB-${var.environment}-video-streaming"

    forwarded_values {
      query_string = true
      headers      = ["*"]  # Forward all headers for WebSocket upgrade
      cookies {
        forward = "all"
      }
    }

    min_ttl                = 0
    default_ttl            = 0    # No caching for WebSocket connections
    max_ttl                = 0
    compress               = false # Don't compress WebSocket traffic
    viewer_protocol_policy = "redirect-to-https"
  }

  ordered_cache_behavior {
    path_pattern     = "/static/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.static.bucket}"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  price_class = "PriceClass_100"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate.main.arn
    ssl_support_method  = "sni-only"
  }

  tags = merge(var.common_tags, {
    Name = "${var.environment}-video-streaming-cloudfront"
  })
}

resource "aws_cloudfront_origin_access_identity" "main" {
  comment = "OAI for ${var.environment} video streaming static assets"
}

# ACM Certificate for CloudFront (must be in us-east-1)
resource "aws_acm_certificate" "main" {
  provider = aws.us_east_1
  
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.common_tags, {
    Name = "${var.environment}-video-streaming-cert"
  })
}

# ACM Certificate for ALB (in the main region)
resource "aws_acm_certificate" "alb" {
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.common_tags, {
    Name = "${var.environment}-video-streaming-alb-cert"
  })
}

# Application Load Balancer
resource "aws_lb" "main" {
  name               = "${var.environment}-video-streaming-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  enable_deletion_protection = false

  tags = merge(var.common_tags, {
    Name = "${var.environment}-video-streaming-alb"
  })
}

resource "aws_lb_target_group" "backend" {
  name        = "${var.environment}-video-streaming-backend-tg"
  port        = 5050
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/api/status"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = var.common_tags
}

resource "aws_lb_target_group" "websocket" {
  name        = "${var.environment}-video-streaming-ws-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  # Enable WebSocket support
  protocol_version = "HTTP1"
  
  # Configure stickiness for WebSocket connections
  stickiness {
    enabled = true
    type    = "lb_cookie"
    cookie_duration = 86400  # 24 hours
  }

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200,400,426"  # 426 is WebSocket upgrade required
    path                = "/api/ws/comments/1"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 10
    unhealthy_threshold = 3
  }

  tags = var.common_tags
}

resource "aws_lb_target_group" "frontend" {
  name        = "${var.environment}-video-streaming-frontend-tg"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = var.common_tags
}

resource "aws_lb_listener" "main" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = aws_acm_certificate.alb.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
}

resource "aws_lb_listener_rule" "api" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }

  condition {
    path_pattern {
      values = ["/api/*"]
    }
  }
}

# WebSocket-specific listener rule (higher priority to catch WebSocket upgrades)
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

# Additional WebSocket listener rule for HTTP upgrade requests
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

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "${var.environment}-video-streaming"

  configuration {
    execute_command_configuration {
      logging = "OVERRIDE"

      log_configuration {
        cloud_watch_encryption_enabled = true
        cloud_watch_log_group_name     = aws_cloudwatch_log_group.ecs.name
      }
    }
  }

  tags = merge(var.common_tags, {
    Name = "${var.environment}-video-streaming-ecs"
  })
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.environment}-video-streaming"
  retention_in_days = 14

  tags = var.common_tags
}

# IAM Roles for ECS
resource "aws_iam_role" "ecs_task_execution" {
  name = "${var.environment}-video-streaming-ecs-task-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = var.common_tags
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task" {
  name = "${var.environment}-video-streaming-ecs-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = var.common_tags
}

resource "aws_iam_role_policy" "ecs_task" {
  name = "${var.environment}-video-streaming-ecs-task-policy"
  role = aws_iam_role.ecs_task.id

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
          "${aws_s3_bucket.videos.arn}/*",
          aws_s3_bucket.static.arn,
          "${aws_s3_bucket.static.arn}/*"
        ]
      }
    ]
  })
}

# Database Migration Task Definition
resource "aws_ecs_task_definition" "db_migration" {
  family                   = "${var.environment}-video-streaming-db-migration"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn           = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name  = "db-migration"
      image = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.environment}-video-streaming-backend:latest"
      
      command = [
        "sh", "-c", 
        "apt-get update && apt-get install -y postgresql-client && psql \"$DATABASE_URL\" -f /app/init-db.sql"
      ]

      environment = [
        {
          name  = "DATABASE_URL"
          value = "postgres://postgres:${random_password.db_password.result}@${aws_db_instance.main.endpoint}/video_streaming_db?sslmode=require"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "db-migration"
        }
      }

      essential = true
    }
  ])

  tags = var.common_tags
}

# Run database migration as a one-time task
resource "null_resource" "db_migration" {
  depends_on = [
    aws_db_instance.main,
    aws_ecs_cluster.main,
    aws_ecs_task_definition.db_migration
  ]

  provisioner "local-exec" {
    command = <<-EOT
      aws ecs run-task \
        --cluster ${aws_ecs_cluster.main.name} \
        --task-definition ${aws_ecs_task_definition.db_migration.arn} \
        --launch-type FARGATE \
        --network-configuration "awsvpcConfiguration={subnets=[${join(",", aws_subnet.private[*].id)}],securityGroups=[${aws_security_group.ecs.id}],assignPublicIp=DISABLED}" \
        --region ${var.region}
    EOT
  }

  triggers = {
    db_endpoint = aws_db_instance.main.endpoint
    task_def    = aws_ecs_task_definition.db_migration.revision
  }
}

# ECS Task Definition
resource "aws_ecs_task_definition" "app" {
  family                   = "${var.environment}-video-streaming"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = local.task_cpu
  memory                   = local.task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn           = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
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
          value = "redis://${aws_elasticache_replication_group.main.primary_endpoint_address}:6379"
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
          name  = "CORS_ALLOWED_ORIGINS"
          value = "https://${var.domain_name},http://${var.domain_name}"
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

      essential = true
    },
    {
      name  = "frontend"
      image = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.environment}-video-streaming-frontend:latest"
      
      portMappings = [
        {
          containerPort = 3000
          protocol      = "tcp"
        }
      ]

      environment = [
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

      essential = true
    }
  ])

  tags = var.common_tags
}

# ECS Service
resource "aws_ecs_service" "main" {
  name            = "${var.environment}-video-streaming"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.server_count
  launch_type     = "FARGATE"

  network_configuration {
    security_groups  = [aws_security_group.ecs.id]
    subnets          = aws_subnet.private[*].id
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.backend.arn
    container_name   = "backend"
    container_port   = 5050
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.websocket.arn
    container_name   = "backend"
    container_port   = 8080
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.frontend.arn
    container_name   = "frontend"
    container_port   = 3000
  }

  depends_on = [
    aws_lb_listener.https,
    aws_iam_role_policy_attachment.ecs_task_execution
  ]

  tags = var.common_tags
}

# ECR Repositories
resource "aws_ecr_repository" "backend" {
  name                 = "${var.environment}-video-streaming-backend"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = var.common_tags
}

resource "aws_ecr_repository" "frontend" {
  name                 = "${var.environment}-video-streaming-frontend"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = var.common_tags
}

resource "aws_ecr_repository" "scraper" {
  name                 = "${var.environment}-video-streaming-scraper"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = var.common_tags
}

# On-Demand YouTube Scraper Task Definition
resource "aws_ecs_task_definition" "scraper" {
  family                   = "${var.environment}-video-streaming-scraper"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 1024  # 1 vCPU
  memory                   = 2048  # 2GB RAM (needed for video processing)
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn           = aws_iam_role.scraper_task.arn

  container_definitions = jsonencode([
    {
      name  = "scraper"
      image = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.environment}-video-streaming-scraper:latest"
      
      # Run in CLI mode for one-time execution
      command = ["youtube_scraper", "--url", "PLACEHOLDER_URL", "--user-id", "1"]

      environment = [
        {
          name  = "DATABASE_URL"
          value = "postgres://postgres:${random_password.db_password.result}@${aws_db_instance.main.endpoint}/video_streaming_db"
        },
        {
          name  = "AWS_REGION"
          value = var.region
        },
        {
          name  = "MINIO_BUCKET"
          value = aws_s3_bucket.videos.bucket
        },
        {
          name  = "RUST_LOG"
          value = "info"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.scraper.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "scraper"
        }
      }

      essential = true
    }
  ])

  tags = var.common_tags
}

# CloudWatch Log Group for Scraper
resource "aws_cloudwatch_log_group" "scraper" {
  name              = "/ecs/${var.environment}-video-streaming-scraper"
  retention_in_days = 7  # Keep logs for 7 days only to save costs

  tags = var.common_tags
}

# IAM Role for Scraper Task (with S3 permissions)
resource "aws_iam_role" "scraper_task" {
  name = "${var.environment}-video-streaming-scraper-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = var.common_tags
}

resource "aws_iam_role_policy" "scraper_task" {
  name = "${var.environment}-video-streaming-scraper-task-policy"
  role = aws_iam_role.scraper_task.id

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

# Lambda function to trigger scraper tasks on-demand
resource "aws_lambda_function" "scraper_trigger" {
  filename         = "scraper_trigger.zip"
  function_name    = "${var.environment}-video-streaming-scraper-trigger"
  role            = aws_iam_role.lambda_scraper_trigger.arn
  handler         = "index.handler"
  runtime         = "python3.9"
  timeout         = 60

  environment {
    variables = {
      ECS_CLUSTER_NAME = aws_ecs_cluster.main.name
      TASK_DEFINITION  = aws_ecs_task_definition.scraper.arn
      SUBNET_IDS       = join(",", aws_subnet.private[*].id)
      SECURITY_GROUP   = aws_security_group.ecs.id
    }
  }

  depends_on = [data.archive_file.scraper_trigger_zip]

  tags = var.common_tags
}

# Create the Lambda deployment package
data "archive_file" "scraper_trigger_zip" {
  type        = "zip"
  output_path = "scraper_trigger.zip"
  
  source {
    content = <<EOF
import json
import boto3
import os
import uuid

ecs = boto3.client('ecs')

def handler(event, context):
    try:
        # Parse the request body
        if 'body' in event:
            body = json.loads(event['body'])
        else:
            body = event
        
        youtube_url = body.get('youtube_url')
        user_id = body.get('user_id', 1)
        
        if not youtube_url:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'youtube_url is required'})
            }
        
        # Generate a unique task name
        task_name = f"scraper-{str(uuid.uuid4())[:8]}"
        
        # Override the container command with the actual URL
        task_definition = os.environ['TASK_DEFINITION']
        
        # Run the ECS task
        response = ecs.run_task(
            cluster=os.environ['ECS_CLUSTER_NAME'],
            taskDefinition=task_definition,
            launchType='FARGATE',
            networkConfiguration={
                'awsvpcConfiguration': {
                    'subnets': os.environ['SUBNET_IDS'].split(','),
                    'securityGroups': [os.environ['SECURITY_GROUP']],
                    'assignPublicIp': 'DISABLED'
                }
            },
            overrides={
                'containerOverrides': [
                    {
                        'name': 'scraper',
                        'command': ['youtube_scraper', '--url', youtube_url, '--user-id', str(user_id)]
                    }
                ]
            },
            tags=[
                {
                    'key': 'Name',
                    'value': task_name
                },
                {
                    'key': 'Type',
                    'value': 'OnDemandScraper'
                }
            ]
        )
        
        task_arn = response['tasks'][0]['taskArn']
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'message': 'Scraper task started successfully',
                'task_arn': task_arn,
                'task_name': task_name,
                'youtube_url': youtube_url
            })
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': str(e)})
        }
EOF
    filename = "index.py"
  }
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_scraper_trigger" {
  name = "${var.environment}-video-streaming-lambda-scraper-trigger"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = var.common_tags
}

resource "aws_iam_role_policy" "lambda_scraper_trigger" {
  name = "${var.environment}-video-streaming-lambda-scraper-trigger-policy"
  role = aws_iam_role.lambda_scraper_trigger.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecs:RunTask",
          "ecs:DescribeTasks",
          "ecs:TagResource"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = [
          aws_iam_role.ecs_task_execution.arn,
          aws_iam_role.scraper_task.arn
        ]
      }
    ]
  })
}

# API Gateway for triggering scraper
resource "aws_api_gateway_rest_api" "scraper_api" {
  name        = "${var.environment}-video-streaming-scraper-api"
  description = "API for triggering on-demand video scraping"

  tags = var.common_tags
}

resource "aws_api_gateway_resource" "scraper_resource" {
  rest_api_id = aws_api_gateway_rest_api.scraper_api.id
  parent_id   = aws_api_gateway_rest_api.scraper_api.root_resource_id
  path_part   = "scrape"
}

resource "aws_api_gateway_method" "scraper_method" {
  rest_api_id   = aws_api_gateway_rest_api.scraper_api.id
  resource_id   = aws_api_gateway_resource.scraper_resource.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "scraper_options" {
  rest_api_id   = aws_api_gateway_rest_api.scraper_api.id
  resource_id   = aws_api_gateway_resource.scraper_resource.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "scraper_integration" {
  rest_api_id = aws_api_gateway_rest_api.scraper_api.id
  resource_id = aws_api_gateway_resource.scraper_resource.id
  http_method = aws_api_gateway_method.scraper_method.http_method

  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.scraper_trigger.invoke_arn
}

resource "aws_api_gateway_integration" "scraper_options_integration" {
  rest_api_id = aws_api_gateway_rest_api.scraper_api.id
  resource_id = aws_api_gateway_resource.scraper_resource.id
  http_method = aws_api_gateway_method.scraper_options.http_method

  type = "MOCK"
  
  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "scraper_options_response" {
  rest_api_id = aws_api_gateway_rest_api.scraper_api.id
  resource_id = aws_api_gateway_resource.scraper_resource.id
  http_method = aws_api_gateway_method.scraper_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "scraper_options_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.scraper_api.id
  resource_id = aws_api_gateway_resource.scraper_resource.id
  http_method = aws_api_gateway_method.scraper_options.http_method
  status_code = aws_api_gateway_method_response.scraper_options_response.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

resource "aws_api_gateway_deployment" "scraper_deployment" {
  depends_on = [
    aws_api_gateway_integration.scraper_integration,
    aws_api_gateway_integration.scraper_options_integration
  ]

  rest_api_id = aws_api_gateway_rest_api.scraper_api.id
  stage_name  = "prod"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lambda_permission" "api_gateway_lambda" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.scraper_trigger.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_api_gateway_rest_api.scraper_api.execution_arn}/*/*"
}

# Outputs
output "server_ips" {
  description = "ECS service endpoint"
  value       = [aws_lb.main.dns_name]
}

output "server_private_ips" {
  description = "Private subnets"
  value       = aws_subnet.private[*].cidr_block
}

output "load_balancer_dns" {
  description = "Load balancer DNS name"
  value       = aws_lb.main.dns_name
}

output "load_balancer_ip" {
  description = "Load balancer DNS (for compatibility)"
  value       = aws_lb.main.dns_name
}

output "ssh_connection_commands" {
  description = "ECS Exec commands"
  value = [
    "aws ecs execute-command --cluster ${aws_ecs_cluster.main.name} --task <task-id> --container backend --interactive --command '/bin/bash'"
  ]
}

output "server_info" {
  description = "Service information"
  value = {
    ecs_cluster    = aws_ecs_cluster.main.name
    ecs_service    = aws_ecs_service.main.name
    database       = aws_db_instance.main.endpoint
    redis          = aws_elasticache_replication_group.main.primary_endpoint_address
    s3_videos      = aws_s3_bucket.videos.bucket
    s3_static      = aws_s3_bucket.static.bucket
    cloudfront     = aws_cloudfront_distribution.main.domain_name
    ecr_backend    = aws_ecr_repository.backend.repository_url
    ecr_frontend   = aws_ecr_repository.frontend.repository_url
  }
}

output "database_endpoint" {
  description = "RDS database endpoint"
  value       = aws_db_instance.main.endpoint
}

output "database_password" {
  description = "RDS database password"
  value       = random_password.db_password.result
  sensitive   = true
}

output "redis_endpoint" {
  description = "ElastiCache Redis endpoint"
  value       = aws_elasticache_replication_group.main.primary_endpoint_address
}

output "s3_buckets" {
  description = "S3 bucket names"
  value = {
    videos = aws_s3_bucket.videos.bucket
    static = aws_s3_bucket.static.bucket
  }
}

output "ecr_repositories" {
  description = "ECR repository URLs"
  value = {
    backend  = aws_ecr_repository.backend.repository_url
    frontend = aws_ecr_repository.frontend.repository_url
    scraper  = aws_ecr_repository.scraper.repository_url
  }
}

output "scraper_api_endpoint" {
  description = "API Gateway endpoint for triggering scraper"
  value       = "${aws_api_gateway_rest_api.scraper_api.execution_arn}/prod/scrape"
}

output "scraper_api_url" {
  description = "Full URL for scraper API"
  value       = "https://${aws_api_gateway_rest_api.scraper_api.id}.execute-api.${var.region}.amazonaws.com/prod/scrape"
}

output "cloudfront_domain" {
  description = "CloudFront distribution domain"
  value       = aws_cloudfront_distribution.main.domain_name
}
