terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.5.0"
}

provider "aws" {
  region = "us-east-1"
}

# --- SECURITY GROUP ---
resource "aws_security_group" "heartbeat_sg" {
  name        = "heartbeat-sg"
  description = "Allow SSH (only for testing)"
  ingress {
    from_port   = 22
    to_port     = 22
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

# --- EC2 INSTANCE ---
data "aws_ami" "amazon_linux_arm" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-arm64-gp2"]
  }
}

resource "aws_instance" "heartbeat_service" {
  ami                    = data.aws_ami.amazon_linux_arm.id
  instance_type          = "t4g.nano"
  iam_instance_profile   = "LabInstanceProfile" # ✅ usa el perfil de laboratorio existente
  user_data              = file("${path.module}/ec2/user_data.sh")
  vpc_security_group_ids = [aws_security_group.heartbeat_sg.id]
  tags = {
    Name = "Manejador de Pedidos - prueba (mini)"
    Role = "heartbeat-sender"
  }
}

# --- SNS Topic ---
resource "aws_sns_topic" "heartbeat_alerts" {
  name = "heartbeat-alerts"
}

# --- SNS Subscription (correo) ---
resource "aws_sns_topic_subscription" "email_sub" {
  topic_arn = aws_sns_topic.heartbeat_alerts.arn
  protocol  = "email"
  endpoint  = "camilo.castilla21@gmail.com"
}

# --- CloudWatch Alarm ---
resource "aws_cloudwatch_metric_alarm" "heartbeat_alarm" {
  alarm_name          = "ServiceHeartbeatMissing"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 3
  period              = 10
  threshold           = 0
  metric_name         = "ServiceAlive"
  namespace           = "HeartbeatService"
  statistic           = "SampleCount"
  treat_missing_data  = "breaching"
  alarm_description   = "Dispara si el heartbeat no se recibe por 30s"
  alarm_actions       = [aws_sns_topic.heartbeat_alerts.arn]
}

# --- Outputs ---
output "ec2_public_ip" {
  value = aws_instance.heartbeat_service.public_ip
}

output "sns_topic_arn" {
  value = aws_sns_topic.heartbeat_alerts.arn
}
