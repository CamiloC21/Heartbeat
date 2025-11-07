import json

def lambda_handler(event, context):
    print("Alerta: Servicio NO está sirviendo (heartbeat perdido por 30s)")
    return {"status": "Service down alert triggered"}
