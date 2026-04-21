import json

PASSPHRASE = "pollenpath"


def handler(event, context):
    body = event
    if isinstance(event.get("body"), str):
        body = json.loads(event["body"])

    passphrase = body.get("passphrase", "")

    if passphrase != PASSPHRASE:
        return {
            "statusCode": 403,
            "body": json.dumps({
                "error": "ACCESS DENIED",
                "message": "Invalid passphrase. The queen does not recognize you."
            })
        }

    return {
        "statusCode": 200,
        "body": json.dumps({
            "message": "The queen acknowledges your presence.",
            "parameters": [
                "/hivectf/queen/key-id",
                "/hivectf/queen/secret-key"
            ],
            "hint": "These parameters hold the keys to the kingdom. But you may need different clearance to read them. Try enumerating what roles exist in this account."
        })
    }
