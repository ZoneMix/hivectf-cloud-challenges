import json
import os
import boto3


SENSOR_DATA = {
    "HV-001": {
        "location": "Hive Alpha",
        "temperature": 35.2,
        "humidity": 62,
        "bee_count": 48200,
        "status": "active",
        "last_check": "2026-04-04T08:30:00Z",
    },
    "HV-002": {
        "location": "Hive Beta",
        "temperature": 34.8,
        "humidity": 58,
        "bee_count": 51400,
        "status": "active",
        "last_check": "2026-04-04T08:31:00Z",
    },
    "HV-003": {
        "location": "Hive Gamma",
        "temperature": 31.1,
        "humidity": 71,
        "bee_count": 12300,
        "status": "maintenance",
        "last_check": "2026-04-03T22:15:00Z",
    },
}


def handler(event, context):
    """HiveWatch Sensor API - Retrieve sensor data by ID."""
    try:
        params = event.get("queryStringParameters") or {}
        sensor_id = params.get("id", "")

        if not sensor_id:
            return {
                "statusCode": 400,
                "headers": {"Content-Type": "application/json"},
                "body": json.dumps({
                    "error": "Missing required parameter: id",
                    "usage": "GET /sensor?id=HV-001",
                }),
            }

        # NOTE: This is an INTENTIONAL vulnerability for a CTF challenge.
        # In production code, NEVER use eval() on user input.
        # This simulates a real-world code smell where dynamic evaluation
        # is used instead of a simple dictionary lookup.
        result = eval(f"SENSOR_DATA.get('{sensor_id}', None)")  # noqa: S307

        if result is None:
            return {
                "statusCode": 404,
                "headers": {"Content-Type": "application/json"},
                "body": json.dumps({
                    "error": f"Sensor '{sensor_id}' not found",
                    "available": list(SENSOR_DATA.keys()),
                }),
            }

        return {
            "statusCode": 200,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({
                "sensor_id": sensor_id,
                "data": result,
                "api_version": "1.4.2",
            }),
        }

    except Exception as e:
        import traceback
        return {
            "statusCode": 500,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({
                "error": f"{type(e).__name__}: {e}",
                "detail": traceback.format_exc().splitlines()[-3:],
            }),
        }
