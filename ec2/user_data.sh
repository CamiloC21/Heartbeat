#!/bin/bash
# Instalar dependencias
yum update -y
yum install -y python3 pip awscli

# Script de heartbeat
cat << 'EOF' > /home/ec2-user/heartbeat.py
import boto3, time
cloudwatch = boto3.client('cloudwatch', region_name='us-east-1')
while True:
    cloudwatch.put_metric_data(
        Namespace='HeartbeatService',
        MetricData=[{
            'MetricName': 'ServiceAlive',
            'Value': 1,
            'Unit': 'Count'
        }]
    )
    print("✅ Heartbeat enviado")
    time.sleep(10)
EOF

# Ejecutar el script en segundo plano al iniciar
nohup python3 /home/ec2-user/heartbeat.py > /home/ec2-user/heartbeat.log 2>&1 &