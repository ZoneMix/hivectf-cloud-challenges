"""Public API handler - HiveCTF Challenge 2 (decoy)."""

import os


def handler(event, context):
    """Handle public API requests.

    This is the public-facing API endpoint for HiveCorp services.
    """
    stage = os.environ.get("STAGE", "unknown")
    return {
        "statusCode": 200,
        "body": f"HiveCorp Public API - Stage: {stage}",
    }
