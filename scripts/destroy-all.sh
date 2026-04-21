#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/../terraform"

CHALLENGES=(
    "challenge-5-queens-gambit"
    "challenge-4-hive-mind"
    "challenge-3-bees-knees"
    "challenge-2-role-call"
    "challenge-1-bucket-list"
)

echo "========================================="
echo "  HiveCTF - Destroy All Challenges"
echo "========================================="
echo ""
echo "WARNING: This will destroy ALL challenge infrastructure."
read -p "Are you sure? (yes/no): " confirm
if [ "${confirm}" != "yes" ]; then
    echo "Aborted."
    exit 0
fi

echo ""

FAILED=()

for challenge in "${CHALLENGES[@]}"; do
    echo "--- Destroying ${challenge} ---"
    challenge_dir="${TERRAFORM_DIR}/${challenge}"

    if [ ! -d "${challenge_dir}" ]; then
        echo "  [SKIP] Directory not found: ${challenge_dir}"
        continue
    fi

    cd "${challenge_dir}"

    if [ ! -f "terraform.tfstate" ] && [ ! -d ".terraform" ]; then
        echo "  [SKIP] No state found for ${challenge}"
        continue
    fi

    if terraform destroy -auto-approve -input=false -no-color; then
        echo "  [OK] ${challenge} destroyed"
    else
        echo "  [FAIL] terraform destroy failed for ${challenge}"
        FAILED+=("${challenge}")
    fi

    echo ""
done

if [ ${#FAILED[@]} -gt 0 ]; then
    echo "Some challenges failed to destroy:"
    for f in "${FAILED[@]}"; do
        echo "  - ${f}"
    done
    exit 1
fi

echo "All challenges destroyed successfully!"
