#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/../terraform"

if [ $# -lt 1 ]; then
    echo "Usage: $0 <challenge-number>"
    echo ""
    echo "This will destroy and redeploy a challenge, resetting it to a clean state."
    echo "Use this if a student accidentally broke something."
    echo ""
    echo "Available challenges:"
    echo "  1  - Bucket List (Easy)"
    echo "  2  - Role Call (Easy-Medium)"
    echo "  3  - Bee's Knees (Medium)"
    echo "  4  - Hive Mind (Medium-Hard)"
    echo "  5  - Queen's Gambit (Hard)"
    exit 1
fi

CHALLENGE_NUM="$1"

case "${CHALLENGE_NUM}" in
    1) CHALLENGE="challenge-1-bucket-list" ;;
    2) CHALLENGE="challenge-2-role-call" ;;
    3) CHALLENGE="challenge-3-bees-knees" ;;
    4) CHALLENGE="challenge-4-hive-mind" ;;
    5) CHALLENGE="challenge-5-queens-gambit" ;;
    *)
        echo "Error: Invalid challenge number '${CHALLENGE_NUM}'"
        echo "Valid options: 1, 2, 3, 4, 5"
        exit 1
        ;;
esac
CHALLENGE_DIR="${TERRAFORM_DIR}/${CHALLENGE}"

echo "========================================="
echo "  Resetting: ${CHALLENGE}"
echo "========================================="
echo ""
echo "This will destroy and redeploy the challenge."
echo "WARNING: Any student-created resources (Cognito users, etc.) will be wiped."
echo ""
read -p "Continue? (yes/no): " confirm
if [ "${confirm}" != "yes" ]; then
    echo "Aborted."
    exit 0
fi

cd "${CHALLENGE_DIR}"

echo ""
echo "Step 1/3: Destroying existing infrastructure..."
if [ -f "terraform.tfstate" ] || [ -d ".terraform" ]; then
    terraform destroy -auto-approve -input=false 2>/dev/null || true
fi

echo ""
echo "Step 2/3: Re-initializing..."
terraform init -input=false

echo ""
echo "Step 3/3: Redeploying..."
terraform apply -auto-approve -input=false

echo ""
echo "========================================="
echo "  Challenge ${CHALLENGE_NUM} Reset Complete"
echo "========================================="
echo ""
echo "New outputs:"
terraform output

echo ""
echo "NOTE: If this challenge provides credentials to students,"
echo "the credentials have changed. Update the challenge description"
echo "on MetaCTF with the new values above."
