# HiveCTF

An AWS cloud security Capture the Flag (CTF) platform with 5 challenges. All infrastructure is defined as Terraform and deploys to real AWS accounts.

Created by Dakota State University students for the HiveCTF 2026 competition.

## Challenge Overview

| # | Name | Category | Difficulty | AWS Services |
|---|------|----------|------------|-------------|
| 1 | Bucket List | Cloud | Easy | S3, Secrets Manager |
| 2 | Role Call | Cloud | Easy-Medium | IAM, STS, Lambda |
| 3 | Bee's Knees | Cloud | Medium | Lambda, API Gateway, S3, KMS |
| 4 | Hive Mind | Cloud | Medium-Hard | Cognito, DynamoDB, S3 |
| 5 | Queen's Gambit | Cloud | Hard | IAM, STS, Lambda, SSM, Secrets Manager (cross-account) |

**Flag format**: `HiveCTF{...}`

## Prerequisites

- [Terraform](https://www.terraform.io/downloads) >= 1.5
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) v2
- 2 AWS accounts with admin IAM users (see [docs/AWS_SETUP.md](docs/AWS_SETUP.md))
  - Challenges 1-4 can run with 1 account; only Challenge 5 requires 2
- AWS CLI profiles configured as:
  - `hivectf-account-1-admin` (Account 1)
  - `hivectf-account-2-admin` (Account 2)

## Quick Start

First, complete the AWS setup: **[docs/AWS_SETUP.md](docs/AWS_SETUP.md)**

Then update each challenge's Terraform variables with your AWS account IDs. See [Configuration](#configuration) below.

```bash
# Initialize and deploy all cloud challenges
./scripts/deploy-all.sh

# View outputs (credentials, URLs) for a specific challenge
cd terraform/challenge-1-bucket-list && terraform output

# When finished, destroy everything
./scripts/destroy-all.sh
```

## Per-Challenge Deployment

Deploy individual challenges when you do not want to bring up all infrastructure at once.

```bash
# Deploy a single challenge by number (1-5)
./scripts/deploy-challenge.sh 1

# Destroy a single challenge
./scripts/destroy-challenge.sh 3

# Reset a broken challenge (destroy + redeploy)
./scripts/reset-challenge.sh 4
```

Or use Terraform directly:

```bash
cd terraform/challenge-2-role-call
terraform init
terraform apply
```

After deployment, run `terraform output` in the challenge directory to get the values needed for the CTF scoreboard (credentials, URLs, bucket names).

## Configuration

### AWS Account IDs

Several challenges reference AWS account IDs in their variables. Update these to match your accounts:

**Challenge 4** (`terraform/challenge-4-hive-mind/variables.tf`):
- `aws_account_id` -- set to your Account 2 ID

**Challenge 5** (`terraform/challenge-5-queens-gambit/variables.tf`):
- `account1_id` -- set to your Account 1 ID
- `account2_id` -- set to your Account 2 ID

You can set these via `terraform.tfvars` files or command-line variables:

```bash
cd terraform/challenge-5-queens-gambit
terraform apply \
  -var 'account1_id=111111111111' \
  -var 'account2_id=222222222222'
```

### Custom Flags

Each challenge has a default flag. To customize:

```bash
# Via command-line variable
terraform apply -var 'flag=HiveCTF{your_custom_flag}'

# Or create terraform/challenge-N-name/terraform.tfvars:
# flag = "HiveCTF{your_custom_flag}"
```

See [docs/CHALLENGE_GUIDE.md](docs/CHALLENGE_GUIDE.md) for the variable name used by each challenge.

### AWS Profiles

The default profile names are `hivectf-account-1-admin` and `hivectf-account-2-admin`. To use different profile names, override the `aws_profile` variable (or `account1_profile`/`account2_profile` for Challenge 5).

## Directory Structure

```
hivectf/
├── terraform/                              # Cloud challenge infrastructure
│   ├── challenge-1-bucket-list/
│   │   ├── main.tf                         # S3 website, Secrets Manager, IAM
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── assets/                         # HTML, CSS, config template
│   ├── challenge-2-role-call/
│   │   ├── main.tf                         # IAM user/role, Lambda functions
│   │   └── lambda/                         # Python Lambda source
│   ├── challenge-3-bees-knees/
│   │   ├── main.tf                         # API Gateway, Lambda, S3, KMS
│   │   └── lambda/                         # Vulnerable sensor API handler
│   ├── challenge-4-hive-mind/
│   │   ├── main.tf                         # Cognito, DynamoDB, S3 portal
│   │   ├── lambda/                         # Auto-confirm trigger
│   │   └── assets/                         # Portal HTML template
│   └── challenge-5-queens-gambit/
│       ├── main.tf                         # Cross-account: S3, IAM, Lambda, SSM
│       ├── lambda/                         # Decoder function
│       └── assets/                         # Mission briefing text
├── challenges/                             # Player-facing materials
│   ├── 1-bucket-list/
│   │   ├── description.md                  # Challenge description for scoreboard
│   │   └── walkthrough.md                  # Full solution guide (do not distribute)
│   ├── 2-role-call/
│   ├── 3-bees-knees/
│   ├── 4-hive-mind/
│   └── 5-queens-gambit/
├── scripts/                                # Deployment management
│   ├── deploy-all.sh                       # Deploy all 5 cloud challenges
│   ├── destroy-all.sh                      # Tear down all cloud challenges
│   ├── deploy-challenge.sh <N>             # Deploy single challenge
│   ├── destroy-challenge.sh <N>            # Destroy single challenge
│   └── reset-challenge.sh <N>              # Destroy + redeploy
├── docs/
│   ├── AWS_SETUP.md                        # AWS account setup guide (start here)
│   └── CHALLENGE_GUIDE.md                  # Detailed guide for instructors
├── LICENSE
└── README.md
```

## Security Model

Each challenge creates isolated IAM users and roles with minimal permissions:

- **Permission boundaries** prevent privilege escalation beyond intended attack paths.
- **Resource-level restrictions** limit access to challenge-specific resources only.
- **No IAM write permissions** for any challenge identity.
- **No console access** for challenge users.
- Admin profiles (`hivectf-account-*-admin`) are never exposed to participants.

## Destroying and Resetting Challenges

### Destroy everything

```bash
./scripts/destroy-all.sh
```

### Reset a single challenge

If a participant breaks something (deletes an S3 object, fills a DynamoDB table, etc.):

```bash
./scripts/reset-challenge.sh <number>
```

This destroys and redeploys the challenge. If the challenge provides AWS credentials to participants, the credentials will change and need to be updated on the scoreboard.

### Manual cleanup

If the scripts fail, run Terraform directly:

```bash
cd terraform/challenge-3-bees-knees
terraform destroy -auto-approve
```

## Cost Disclaimer

HiveCTF deploys real AWS resources that incur charges. Estimated cost is $0.50-5.00 per day depending on free-tier eligibility and traffic volume. **Always run `./scripts/destroy-all.sh` when you are finished.** See [docs/AWS_SETUP.md](docs/AWS_SETUP.md) for detailed cost breakdowns and tips on minimizing spend.

The authors are not responsible for any AWS charges incurred. Set up billing alerts before deploying.

## Contributing

Contributions are welcome. To add a new cloud challenge:

1. Create `terraform/challenge-N-name/` with `main.tf`, `variables.tf`, and `outputs.tf`.
2. Create `challenges/N-name/description.md` (player-facing) and `walkthrough.md` (solution).
3. Use permission boundaries on all challenge IAM identities.
4. Add the challenge to the array in `scripts/deploy-all.sh`.
5. Test deployment and destruction in a clean AWS account.

## License

MIT -- see [LICENSE](LICENSE).
