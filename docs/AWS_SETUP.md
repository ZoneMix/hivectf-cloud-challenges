# AWS Setup Guide for HiveCTF

This guide walks you through setting up AWS from scratch to run HiveCTF challenges. No prior AWS experience is assumed.

## Table of Contents

- [Overview](#overview)
- [Why Two AWS Accounts?](#why-two-aws-accounts)
- [Step 1: Create AWS Account 1](#step-1-create-aws-account-1)
- [Step 2: Create AWS Account 2](#step-2-create-aws-account-2)
- [Step 3: Create IAM Admin Users](#step-3-create-iam-admin-users)
- [Step 4: Install the AWS CLI](#step-4-install-the-aws-cli)
- [Step 5: Configure AWS CLI Profiles](#step-5-configure-aws-cli-profiles)
- [Step 6: Verify Your Setup](#step-6-verify-your-setup)
- [Cost Considerations](#cost-considerations)

---

## Overview

HiveCTF deploys cloud challenges into real AWS infrastructure using Terraform. You need:

- **1 AWS account** to run challenges 1-4
- **2 AWS accounts** to run challenge 5 (cross-account pivot)

If you only plan to run challenges 1-4, you can skip creating the second account.

## Why Two AWS Accounts?

Challenge 5 ("Queen's Gambit") teaches cross-account privilege escalation. The attack path starts in Account 1, pivots into Account 2 via IAM role assumption, and then returns to Account 1 to retrieve the flag. This requires two real, separate AWS accounts because cross-account IAM trust relationships cannot be simulated within a single account.

Challenges 1-3 deploy entirely to Account 1. Challenge 4 deploys to Account 2. Challenge 5 deploys resources to both accounts simultaneously.

## Step 1: Create AWS Account 1

1. Go to [https://aws.amazon.com/](https://aws.amazon.com/) and click **Create an AWS Account**.

2. Enter an email address. This becomes the **root user** email. Use a real email you control -- you will need to verify it. A good pattern is `yourname+aws1@gmail.com` (Gmail ignores everything after `+`).

3. Choose an **AWS account name**. Something like `HiveCTF Account 1` works fine. This is just a display name.

4. Follow the prompts to set a password, provide contact information, and enter a payment method. AWS requires a credit card on file even for free-tier usage.

5. Select the **Basic (Free)** support plan.

6. Once the account is created, sign in to the AWS Management Console at [https://console.aws.amazon.com/](https://console.aws.amazon.com/).

7. **Enable MFA on the root user** (strongly recommended):
   - Click your account name in the top-right corner, then **Security credentials**.
   - Under **Multi-factor authentication (MFA)**, click **Assign MFA device**.
   - Choose **Authenticator app** and follow the prompts with an app like Google Authenticator, Authy, or 1Password.

8. **Note your Account ID**: Click your account name in the top-right corner of the console. The 12-digit number shown is your Account ID. Save it -- you will need it for Terraform variables.

## Step 2: Create AWS Account 2

Repeat the exact same process from Step 1, but use a different email address (e.g., `yourname+aws2@gmail.com`). Give it a name like `HiveCTF Account 2`.

Again, note the 12-digit Account ID for this second account.

**Reminder**: You only need this second account if you plan to run Challenge 5.

## Step 3: Create IAM Admin Users

AWS best practice is to never use the root account for day-to-day work. Instead, create an IAM admin user in each account that Terraform will use to deploy resources.

### In Account 1

1. Sign in to Account 1's console as the root user.

2. Navigate to **IAM** (search for "IAM" in the top search bar).

3. In the left sidebar, click **Users**, then **Create user**.

4. **User name**: `hivectf-admin`

5. Do **not** check "Provide user access to the AWS Management Console" (this user only needs programmatic access).

6. Click **Next**. On the permissions page, select **Attach policies directly**.

7. Search for and check the box next to `AdministratorAccess`.

8. Click **Next**, then **Create user**.

9. Click on the newly created user name to open the user details.

10. Go to the **Security credentials** tab.

11. Under **Access keys**, click **Create access key**.

12. Select **Command Line Interface (CLI)** as the use case. Check the confirmation checkbox at the bottom, then click **Next**.

13. Click **Create access key**.

14. **Save both values now** -- the Secret Access Key is only shown once:
    - Access Key ID (looks like `AKIAIOSFODNN7EXAMPLE`)
    - Secret Access Key (looks like `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY`)

### In Account 2

Sign out of Account 1, sign in to Account 2 as root, and repeat the exact same process above. Create a user named `hivectf-admin` with `AdministratorAccess` and generate access keys.

You should now have two sets of access keys -- one for each account.

## Step 4: Install the AWS CLI

The AWS CLI v2 is required. Install it for your operating system:

### macOS

```bash
curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
sudo installer -pkg AWSCLIV2.pkg -target /
rm AWSCLIV2.pkg
```

### Linux (x86_64)

```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
rm -rf aws awscliv2.zip
```

### Windows

Download and run the installer from:
[https://awscli.amazonaws.com/AWSCLIV2.msi](https://awscli.amazonaws.com/AWSCLIV2.msi)

### Verify Installation

```bash
aws --version
```

You should see output like `aws-cli/2.x.x Python/3.x.x ...`. Any 2.x version works.

## Step 5: Configure AWS CLI Profiles

HiveCTF uses **named profiles** so Terraform can target the correct account. The profile names must match what the Terraform configurations expect.

### Configure Account 1 Profile

```bash
aws configure --profile hivectf-account-1-admin
```

When prompted, enter:

```
AWS Access Key ID [None]: <paste Account 1 Access Key ID>
AWS Secret Access Key [None]: <paste Account 1 Secret Access Key>
Default region name [None]: us-east-1
Default output format [None]: json
```

### Configure Account 2 Profile

```bash
aws configure --profile hivectf-account-2-admin
```

When prompted, enter:

```
AWS Access Key ID [None]: <paste Account 2 Access Key ID>
AWS Secret Access Key [None]: <paste Account 2 Secret Access Key>
Default region name [None]: us-east-1
Default output format [None]: json
```

These credentials are stored in `~/.aws/credentials` and `~/.aws/config` on your machine.

## Step 6: Verify Your Setup

Run the following commands to confirm each profile is correctly configured:

```bash
aws sts get-caller-identity --profile hivectf-account-1-admin
```

Expected output (your Account ID will differ):

```json
{
    "UserId": "AIDAEXAMPLEID",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/hivectf-admin"
}
```

```bash
aws sts get-caller-identity --profile hivectf-account-2-admin
```

Verify this returns a **different** Account number than the first command.

If either command returns an error, double-check:
- The access key and secret key were pasted correctly (no trailing spaces).
- The profile name matches exactly (`hivectf-account-1-admin`, `hivectf-account-2-admin`).
- The IAM user has the `AdministratorAccess` policy attached.

## Cost Considerations

### What Is in the AWS Free Tier

Many of the services used by HiveCTF fall within the AWS Free Tier (available for 12 months after account creation):

| Service | Free Tier Allowance | Used By |
|---------|-------------------|---------|
| S3 | 5 GB storage, 20,000 GET requests | Challenges 1, 3, 4, 5 |
| Lambda | 1M requests/month, 400,000 GB-seconds | Challenges 2, 3, 4, 5 |
| DynamoDB | 25 GB storage, 25 read/write capacity units | Challenge 4 |
| API Gateway | 1M API calls/month (first 12 months) | Challenge 3 |
| Secrets Manager | 30-day free trial for new secrets | Challenges 1, 5 |
| IAM | Always free | All challenges |
| STS | Always free | Challenges 2, 5 |
| Cognito | 50,000 MAUs free | Challenge 4 |
| SSM Parameter Store | Standard parameters free | Challenge 5 |

### Estimated Costs

If your accounts are within the free tier period, running all 5 challenges costs approximately **$0.50-2.00 per day**, primarily from:

- **Secrets Manager**: $0.40/secret/month (2 secrets across challenges = ~$0.03/day)
- **KMS**: $1.00/key/month for the customer-managed key in Challenge 3 (~$0.03/day)
- **API Gateway**: Negligible for CTF traffic levels

If your accounts are **outside** the free tier period, expect **$1-5 per day** depending on how much traffic your participants generate.

### Keeping Costs Low

1. **Deploy only when needed.** Run `./scripts/deploy-all.sh` the morning of the event.

2. **Destroy immediately after.** Run `./scripts/destroy-all.sh` when the CTF ends. Every hour the infrastructure is running costs money.

3. **Use `terraform destroy`** if the scripts fail for any reason:
   ```bash
   cd terraform/challenge-1-bucket-list
   terraform destroy -auto-approve
   ```

4. **Set up billing alerts.** In the AWS Console, go to **Billing and Cost Management** > **Budgets** > **Create a budget**. Set a $10 monthly budget with an email alert at 80% threshold.

5. **Check for leftover resources.** After destroying, verify in the AWS Console that no S3 buckets, Lambda functions, or DynamoDB tables remain. Terraform handles cleanup, but it is good practice to confirm.
