provider "aws" {
  region = "us-east-1" # Change as needed
}

# VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true
  tags = { Name = "ecs-vpc" }
}

# Public Subnets
resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1a"
  tags = { Name = "public-subnet-1" }
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1b"
  tags = { Name = "public-subnet-2" }
}

# Private Subnets
resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1a"
  tags = { Name = "private-subnet-1" }
}

resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "us-east-1b"
  tags = { Name = "private-subnet-2" }
}

# Internet Gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags = { Name = "ecs-igw" }
}

# Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route { cidr_block = "0.0.0.0/0" gateway_id = aws_internet_gateway.gw.id }
}

# Associate Route Table with Public Subnets
resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

# Security Group for ECS Instances
resource "aws_security_group" "ecs_sg" {
  vpc_id = aws_vpc.main.id
  ingress { from_port = 80 to_port = 80 protocol = "tcp" cidr_blocks = ["0.0.0.0/0"] }
  egress { from_port = 0 to_port = 0 protocol = "-1" cidr_blocks = ["0.0.0.0/0"] }
}

# ECS Cluster
resource "aws_ecs_cluster" "ecs_cluster" {
  name = "ecs-cluster"
}

# Launch Template
resource "aws_launch_template" "ecs_lt" {
  name_prefix   = "ecs-lt"
  image_id      = "ami-0c7af5fe939f2677f" # Update with valid ECS optimized AMI
  instance_type = "t2.micro"
  user_data = base64encode(<<-EOF
              #!/bin/bash
              echo ECS_CLUSTER=${aws_ecs_cluster.ecs_cluster.name} >> /etc/ecs/ecs.config
              EOF
            )
  network_interfaces {
    security_groups = [aws_security_group.ecs_sg.id]
  }
  tag_specifications {
    resource_type = "instance"
    tags = { Name = "ecs-instance" }
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "ecs_asg" {
  vpc_zone_identifier = [aws_subnet.public_1.id, aws_subnet.public_2.id]
  desired_capacity    = 2
  max_size           = 3
  min_size           = 1
  launch_template {
    id      = aws_launch_template.ecs_lt.id
    version = "$Latest"
  }
}

# Load Balancer
resource "aws_lb" "ecs_lb" {
  name               = "ecs-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.ecs_sg.id]
  subnets           = [aws_subnet.public_1.id, aws_subnet.public_2.id]
}

# Target Group
resource "aws_lb_target_group" "ecs_tg" {
  name     = "ecs-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
}

# Listener
resource "aws_lb_listener" "ecs_listener" {
  load_balancer_arn = aws_lb.ecs_lb.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ecs_tg.arn
  }
}

# Task Definition
resource "aws_ecs_task_definition" "ecs_task" {
  family                   = "ecs-task"
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]
  container_definitions    = <<TASK_DEFINITION
  [
    {
      "name": "my-container",
      "image": "nginx",
      "memory": 512,
      "cpu": 256,
      "essential": true,
      "portMappings": [{"containerPort": 80, "hostPort": 80}]
    }
  ]
TASK_DEFINITION
}

# ECS Service
resource "aws_ecs_service" "ecs_service" {
  name            = "ecs-service"
  cluster         = aws_ecs_cluster.ecs_cluster.id
  task_definition = aws_ecs_task_definition.ecs_task.arn
  desired_count   = 2
  launch_type     = "EC2"
  load_balancer {
    target_group_arn = aws_lb_target_group.ecs_tg.arn
    container_name   = "my-container"
    container_port   = 80
  }
}
