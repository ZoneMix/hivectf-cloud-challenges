#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/../terraform"

if [ $# -lt 1 ]; then
    echo "Usage: $0 <challenge-number>"
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
echo "  Destroying: ${CHALLENGE}"
echo "========================================="
echo ""
echo "WARNING: This will destroy all infrastructure for ${CHALLENGE}."
read -p "Are you sure? (yes/no): " confirm
if [ "${confirm}" != "yes" ]; then
    echo "Aborted."
    exit 0
fi

cd "${CHALLENGE_DIR}"

echo "Running terraform destroy..."
terraform destroy -auto-approve -input=false

echo ""
echo "Challenge ${CHALLENGE_NUM} destroyed."
