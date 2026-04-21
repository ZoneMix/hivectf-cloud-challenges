# Challenge Guide

This guide is for instructors and CTF organizers. It explains what each challenge teaches, the intended attack path (without revealing flags), and how to set up and customize each challenge.

## Table of Contents

- [Cloud Challenges](#cloud-challenges)
  - [Challenge 1: Bucket List](#challenge-1-bucket-list)
  - [Challenge 2: Role Call](#challenge-2-role-call)
  - [Challenge 3: Bee's Knees](#challenge-3-bees-knees)
  - [Challenge 4: Hive Mind](#challenge-4-hive-mind)
  - [Challenge 5: Queen's Gambit](#challenge-5-queens-gambit)
- [Suggested Progression Order](#suggested-progression-order)
- [Customizing Flags](#customizing-flags)

---

## Cloud Challenges

All cloud challenges deploy via Terraform and require the AWS profiles described in [AWS_SETUP.md](AWS_SETUP.md).

### Challenge 1: Bucket List

| Field | Value |
|-------|-------|
| Difficulty | Easy |
| Points | 100 |
| AWS Services | S3, Secrets Manager, IAM |
| Account | 1 |

**What it teaches**: S3 bucket enumeration, understanding public bucket policies, recognizing sensitive data left in publicly accessible storage.

**Scenario**: Players are given a URL to a static website hosted on S3. The site is a marketing page for a fictional company.

**Intended attack path**:

1. Players visit the S3-hosted website and inspect the page source.
2. They discover the bucket allows public listing (via the `s3:ListBucket` permission).
3. Browsing the bucket contents reveals a backup configuration file in a `/backups/` prefix.
4. The backup file contains AWS access keys for a restricted IAM user.
5. Players configure those credentials in the AWS CLI and discover the user can read from Secrets Manager.
6. Retrieving the secret yields the flag.

**AWS resources created**: S3 bucket with static website hosting, IAM user with read-only Secrets Manager access, Secrets Manager secret, permission boundary preventing escalation.

---

### Challenge 2: Role Call

| Field | Value |
|-------|-------|
| Difficulty | Easy-Medium |
| Points | 200 |
| AWS Services | IAM, STS, Lambda |
| Account | 1 |

**What it teaches**: IAM enumeration, role chaining via `sts:AssumeRole`, inspecting Lambda function configurations for exposed secrets.

**Scenario**: Players receive AWS credentials for an "intern" user with minimal permissions.

**Intended attack path**:

1. Players start by identifying themselves with `sts:GetCallerIdentity`.
2. They enumerate their own permissions and discover they can list IAM roles.
3. Among the roles, they find a "dev-role" that the intern can assume.
4. After assuming the dev role, they gain Lambda read access.
5. Listing Lambda functions reveals an "internal-processor" function.
6. Inspecting the function's configuration exposes the flag stored in an environment variable.

**AWS resources created**: IAM user (intern) with enumeration permissions, IAM role (dev-role) with Lambda read access, two Lambda functions (one containing the flag in env vars, one decoy), permission boundaries.

---

### Challenge 3: Bee's Knees

| Field | Value |
|-------|-------|
| Difficulty | Medium |
| Points | 300 |
| AWS Services | Lambda, API Gateway, S3, KMS |
| Account | 1 |

**What it teaches**: API endpoint discovery, server-side template injection (SSTI) in a Lambda-backed API, leaking Lambda execution credentials, using stolen AWS credentials to access other services.

**Scenario**: Players are given the base URL of an API for an IoT sensor monitoring platform. The API is backed by a Lambda function with an SSTI vulnerability.

**Intended attack path**:

1. Players fuzz the API to discover endpoints (`/sensor`, `/health`, `/status`, `/info`).
2. The `/sensor` endpoint accepts an `id` query parameter that is vulnerable to injection.
3. Through SSTI exploitation, players extract the Lambda function's runtime AWS credentials from environment variables.
4. Using those temporary credentials, they discover the Lambda has S3 read access.
5. Listing and reading S3 objects reveals a `classified/flag.txt` file containing the flag.

**AWS resources created**: API Gateway (REST) with multiple endpoints (including decoys), Lambda function with S3 read permissions, S3 bucket with sensor data and the flag, KMS key for Lambda environment encryption, CloudWatch log group.

---

### Challenge 4: Hive Mind

| Field | Value |
|-------|-------|
| Difficulty | Medium-Hard |
| Points | 400 |
| AWS Services | Cognito, DynamoDB, S3, IAM |
| Account | 2 |

**What it teaches**: Cognito authentication flows, credential vending via Cognito Identity Pools, DynamoDB enumeration and querying, following breadcrumbs across multiple data sources.

**Scenario**: Players are given a URL to a research portal. The web interface exposes Cognito configuration in its client-side code.

**Intended attack path**:

1. Players inspect the portal's HTML source and extract Cognito User Pool ID, Client ID, and Identity Pool ID.
2. They register a new user via the Cognito User Pool (auto-confirmed by a Lambda trigger).
3. After authenticating, they exchange the Cognito token for temporary AWS credentials via the Identity Pool.
4. With those credentials, they list DynamoDB tables and find: `users`, `research-logs`, `admin-notes`, and `vault`.
5. Scanning the research logs reveals references to "Project Honeycomb" and a classified vault.
6. Scanning the admin notes reveals a classified entry containing a vault key.
7. Using that key to query the vault table (via `GetItem`) returns the flag.

**AWS resources created**: Cognito User Pool with auto-confirm Lambda trigger, Cognito Identity Pool, authenticated IAM role with DynamoDB read access, four DynamoDB tables with seeded data, S3 bucket for static website hosting, permission boundaries preventing writes.

---

### Challenge 5: Queen's Gambit

| Field | Value |
|-------|-------|
| Difficulty | Hard |
| Points | 500 |
| AWS Services | IAM, STS, S3, Lambda, SSM Parameter Store, Secrets Manager |
| Accounts | 1 + 2 (cross-account) |

**What it teaches**: Cross-account role assumption, multi-step privilege escalation across AWS account boundaries, decoding obfuscated hints, Lambda invocation, SSM Parameter Store retrieval, role chaining.

**Scenario**: Players receive credentials for a "scout" user in Account 1 and must navigate a chain of identities spanning two AWS accounts to reach the flag.

**Intended attack path**:

1. Players identify themselves and discover S3 access to a mission briefing bucket.
2. The briefing file provides narrative context. An intel file contains a base64-encoded IAM role ARN pointing to Account 2.
3. Players assume the "liaison" role in Account 2 (cross-account).
4. As the liaison, they discover and invoke a Lambda decoder function that returns SSM parameter paths.
5. The liaison can also assume an "intel-reader" role (role chaining within Account 2).
6. As the intel-reader, they retrieve SSM parameters containing access keys for a "queen" user back in Account 1.
7. Configuring the queen's credentials, they retrieve the flag from Secrets Manager in Account 1.

**AWS resources created**: In Account 1: S3 bucket with briefing files, scout IAM user, queen IAM user, Secrets Manager secret. In Account 2: Liaison IAM role (cross-account trust), intel-reader IAM role, Lambda decoder function, SSM parameters storing the queen's credentials.

---

## Suggested Progression Order

For a multi-hour CTF event, the recommended unlock/progression order is:

| Order | Challenge | Rationale |
|-------|-----------|-----------|
| 1 | Bucket List | Warm-up: basic web source inspection and S3 enumeration |
| 2 | Role Call | Introduces IAM enumeration and role assumption |
| 3 | Bee's Knees | Builds on web + cloud; SSTI adds complexity |
| 4 | Hive Mind | Multi-step cloud; requires Cognito understanding |
| 5 | Queen's Gambit | Capstone: cross-account, multi-identity, hardest challenge |

Alternatively, unlock all challenges at once and let teams self-select. The point values (100-500) already guide difficulty expectations.

## Customizing Flags

Each cloud challenge defines its flag as a Terraform variable with a default value. To set custom flags, create a `terraform.tfvars` file in each challenge directory or pass the variable on the command line.

### Using terraform.tfvars

Create a file at `terraform/challenge-1-bucket-list/terraform.tfvars`:

```hcl
challenge_flag = "HiveCTF{your_custom_flag_here}"
```

The variable names differ by challenge:

| Challenge | Variable Name |
|-----------|--------------|
| 1 - Bucket List | `challenge_flag` |
| 2 - Role Call | `challenge_flag` |
| 3 - Bee's Knees | `flag` |
| 4 - Hive Mind | `flag` |
| 5 - Queen's Gambit | `flag` |

### Using command-line variables

```bash
cd terraform/challenge-1-bucket-list
terraform apply -var 'challenge_flag=HiveCTF{my_custom_flag}'
```

