"""Internal data processor - HiveCTF Challenge 2."""

import os


def handler(event, context):
    """Process internal data requests.

    This function is for internal use only.
    The FLAG environment variable contains sensitive data.
    """
    return {
        "statusCode": 403,
        "body": "Internal use only. This endpoint is not publicly accessible.",
    }
