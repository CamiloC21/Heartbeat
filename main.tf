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

# --- IAM Role para EC2 ---
resource "aws_iam_role" "ec2_role" {
  name = "ec2-heartbeat-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_cloudwatch_access" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchFullAccess"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2-heartbeat-profile"
  role = aws_iam_role.ec2_role.name
}

# --- EC2 INSTANCE (tiny) ---
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
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name
  user_data              = file("${path.module}/ec2/user_data.sh")
  vpc_security_group_ids = [aws_security_group.heartbeat_sg.id]
  tags = {
    Name = "Manejador de Pedidos - prueba (mini)"
    Role = "heartbeat-sender"
  }
}

# --- IAM Role para Lambda ---
resource "aws_iam_role" "lambda_exec_role" {
  name = "heartbeat-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# --- Lambda Function ---
resource "aws_lambda_function" "heartbeat_alarm_handler" {
  filename         = "${path.module}/lambda/handler.zip"
  function_name    = "heartbeat-alarm-handler"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.11"
  source_code_hash = filebase64sha256("${path.module}/lambda/handler.zip")
}

# --- SNS Topic ---
resource "aws_sns_topic" "heartbeat_alerts" {
  name = "heartbeat-alerts"
}

# --- SNS Subscriptions ---
resource "aws_sns_topic_subscription" "email_sub" {
  topic_arn = aws_sns_topic.heartbeat_alerts.arn
  protocol  = "email"
  endpoint  = "camilo.castilla21@gmail.com"
}

resource "aws_lambda_permission" "allow_sns_invoke" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.heartbeat_alarm_handler.arn
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.heartbeat_alerts.arn
}

resource "aws_sns_topic_subscription" "lambda_sub" {
  topic_arn = aws_sns_topic.heartbeat_alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.heartbeat_alarm_handler.arn
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
