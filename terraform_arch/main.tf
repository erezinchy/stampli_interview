# 1. PROVIDER & VPC CONFIGURATION
provider "aws" {
  region = "us-east-1"
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_subnet" "pub_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "pub_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true
}

resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.pub_a.id
  route_table_id = aws_route_table.rt.id
}

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.pub_b.id
  route_table_id = aws_route_table.rt.id
}

# 2. SECURITY GROUPS
resource "aws_security_group" "alb_sg" {
  name   = "alb-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ecs_sg" {
  name   = "ecs-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 3. ECR & ECS INFRASTRUCTURE
resource "aws_ecr_repository" "app" {
  name         = "tiny-web-app"
  force_delete = true
}

resource "aws_ecs_cluster" "main" {
  name = "app-cluster" # GitHub Action must use: ECS_CLUSTER: app-cluster
}

# CloudWatch Log Group (Fixed: Created manually for ECS)
resource "aws_cloudwatch_log_group" "ecs_logs" {
  name              = "/ecs/tiny-web-app"
  retention_in_days = 7
}

# IAM Role for ECS Task Execution
resource "aws_iam_role" "ecs_exec_role" {
  name = "ecs_exec_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ecs-tasks.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_exec_attach" {
  role       = aws_iam_role.ecs_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_ecs_task_definition" "app" {
  family                   = "app-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_exec_role.arn

  container_definitions = jsonencode([{
    name  = "web-app"
    image = "${aws_ecr_repository.app.repository_url}:latest"
    portMappings = [{ containerPort = 3000, hostPort = 3000 }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "/ecs/tiny-web-app"
        "awslogs-region"        = "us-east-1"
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

resource "aws_ecs_service" "app" {
  name            = "app-service" # GitHub Action must use: ECS_SERVICE: app-service
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  launch_type     = "FARGATE"
  desired_count   = 2

  network_configuration {
    subnets          = [aws_subnet.pub_a.id, aws_subnet.pub_b.id]
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = true 
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.tg.arn
    container_name   = "web-app"
    container_port   = 3000
  }
}

# 4. LOAD BALANCER
resource "aws_lb" "alb" {
  name               = "app-alb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.pub_a.id, aws_subnet.pub_b.id]
}

resource "aws_lb_target_group" "tg" {
  name        = "app-tg"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
  health_check { path = "/" }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

# 5. CLOUDFRONT DISTRIBUTION (Updated with Managed Policies)
resource "aws_cloudfront_distribution" "cf" {
  origin {
    domain_name = aws_lb.alb.dns_name
    origin_id   = "ALBOrigin"
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  enabled         = true
  is_ipv6_enabled = true

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "ALBOrigin"

    # Forwarding X-Forwarded-For via Managed Origin Request Policy
    origin_request_policy_id = "b689b0a8-53d0-40a8-b0e6-2457ca350846" # AllViewerExceptHostHeader
    cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # CachingDisabled (for real-time IP tests)

    viewer_protocol_policy = "redirect-to-https"
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# OUTPUTS
output "cloudfront_url" {
  value = aws_cloudfront_distribution.cf.domain_name
}

output "ecs_execution_role_arn" {
  value = aws_iam_role.ecs_exec_role.arn
}