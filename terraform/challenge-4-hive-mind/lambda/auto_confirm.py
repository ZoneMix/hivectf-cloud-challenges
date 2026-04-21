def handler(event, context):
    event["response"]["autoConfirmUser"] = True
    # Only auto-verify email if one was provided during signup
    if event.get("request", {}).get("userAttributes", {}).get("email"):
        event["response"]["autoVerifyEmail"] = True
    return event
