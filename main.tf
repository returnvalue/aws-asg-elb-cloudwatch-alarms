# AWS provider configuration for LocalStack
provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true

  endpoints {
    apigateway     = "http://localhost:4566"
    cloudformation = "http://localhost:4566"
    cloudwatch     = "http://localhost:4566"
    dynamodb       = "http://localhost:4566"
    ec2            = "http://localhost:4566"
    es             = "http://localhost:4566"
    firehose       = "http://localhost:4566"
    iam            = "http://localhost:4566"
    kinesis        = "http://localhost:4566"
    lambda         = "http://localhost:4566"
    route53        = "http://localhost:4566"
    redshift       = "http://localhost:4566"
    s3             = "http://s3.localhost.localstack.cloud:4566"
    secretsmanager = "http://localhost:4566"
    ses            = "http://localhost:4566"
    sns            = "http://localhost:4566"
    sqs            = "http://localhost:4566"
    ssm            = "http://localhost:4566"
    stepfunctions  = "http://localhost:4566"
    sts            = "http://localhost:4566"
    elb            = "http://localhost:4566"
    elbv2          = "http://localhost:4566"
    rds            = "http://localhost:4566"
    autoscaling    = "http://localhost:4566"
    events         = "http://localhost:4566"
  }
}

# VPC: The foundational network for our high-availability architecture
resource "aws_vpc" "asg_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "asg-lab-vpc"
  }
}

# Subnet 1: Availability Zone A
resource "aws_subnet" "subnet_a" {
  vpc_id                  = aws_vpc.asg_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "asg-subnet-a"
  }
}

# Subnet 2: Availability Zone B
resource "aws_subnet" "subnet_b" {
  vpc_id                  = aws_vpc.asg_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "asg-subnet-b"
  }
}

# Internet Gateway: Entrance and exit for internet traffic
resource "aws_internet_gateway" "asg_igw" {
  vpc_id = aws_vpc.asg_vpc.id

  tags = {
    Name = "asg-lab-igw"
  }
}

# Route Table: Directs subnet traffic toward the internet
resource "aws_route_table" "asg_rt" {
  vpc_id = aws_vpc.asg_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.asg_igw.id
  }

  tags = {
    Name = "asg-lab-route-table"
  }
}

# Subnet Associations: Link the subnets to our internet-facing route table
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.subnet_a.id
  route_table_id = aws_route_table.asg_rt.id
}

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.subnet_b.id
  route_table_id = aws_route_table.asg_rt.id
}

# Security Group: Firewall for our ASG instances and Load Balancer
resource "aws_security_group" "asg_sg" {
  name        = "asg-lab-sg"
  description = "Allow HTTP inbound traffic"
  vpc_id      = aws_vpc.asg_vpc.id

  # Inbound HTTP: Allow traffic on port 80
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound All: Allow instances to reach the internet
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "asg-lab-sg"
  }
}

# Launch Template: Defines the blueprint for our Auto Scaling instances
resource "aws_launch_template" "asg_launch_template" {
  name_prefix   = "asg-lab-template"
  image_id      = "ami-0c55b159cbfafe1f0" # Placeholder AMI for LocalStack
  instance_type = "t2.micro"

  vpc_security_group_ids = [aws_security_group.asg_sg.id]

  # User Data: Script to initialize a web server and show the instance ID
  user_data = base64encode(<<-EOF
              #!/bin/bash
              echo "Hello from $(hostname -f)" > index.html
              nohup python3 -m http.server 80 &
              EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "asg-lab-instance"
    }
  }
}

# Application Load Balancer: Distributes incoming web traffic
resource "aws_lb" "asg_alb" {
  name               = "asg-lab-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.asg_sg.id]
  subnets            = [aws_subnet.subnet_a.id, aws_subnet.subnet_b.id]

  tags = {
    Name = "asg-lab-alb"
  }
}

# Target Group: A collection of instances that the ALB can route to
resource "aws_lb_target_group" "asg_tg" {
  name     = "asg-lab-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.asg_vpc.id

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }

  tags = {
    Name = "asg-lab-tg"
  }
}

# ALB Listener: Listens for HTTP traffic and forwards it to the target group
resource "aws_lb_listener" "asg_listener" {
  load_balancer_arn = aws_lb.asg_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.asg_tg.arn
  }
}

# Auto Scaling Group: Manages the lifecycle and count of our instances
resource "aws_autoscaling_group" "asg_lab" {
  name                = "asg-lab-group"
  desired_capacity    = 2
  max_size            = 4
  min_size            = 1
  target_group_arns   = [aws_lb_target_group.asg_tg.arn]
  vpc_zone_identifier = [aws_subnet.subnet_a.id, aws_subnet.subnet_b.id]

  launch_template {
    id      = aws_launch_template.asg_launch_template.id
    version = "$Latest"
  }

  # Ensure the ASG waits for instances to be healthy before considering the update complete
  health_check_type         = "ELB"
  health_check_grace_period = 300

  tag {
    key                 = "Name"
    value               = "asg-lab-instance"
    propagate_at_launch = true
  }
}

# Scaling Policy: Add one instance (Scale Up)
resource "aws_autoscaling_policy" "scale_up" {
  name                   = "scale-up-policy"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.asg_lab.name
}

# CloudWatch Alarm: Trigger Scale Up when CPU > 70%
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "cpu-high-alarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = "70"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.asg_lab.name
  }

  alarm_description = "This metric monitors ec2 cpu utilization"
  alarm_actions     = [aws_autoscaling_policy.scale_up.arn]
}

# Scaling Policy: Remove one instance (Scale Down)
resource "aws_autoscaling_policy" "scale_down" {
  name                   = "scale-down-policy"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.asg_lab.name
}

# CloudWatch Alarm: Trigger Scale Down when CPU < 30%
resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name          = "cpu-low-alarm"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = "30"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.asg_lab.name
  }

  alarm_description = "This metric monitors ec2 cpu utilization"
  alarm_actions     = [aws_autoscaling_policy.scale_down.arn]
}

# Outputs: Key identifiers for testing the ASG and ELB architecture
output "alb_dns_name" {
  value = aws_lb.asg_alb.dns_name
}

output "asg_name" {
  value = aws_autoscaling_group.asg_lab.name
}

output "target_group_arn" {
  value = aws_lb_target_group.asg_tg.arn
}
