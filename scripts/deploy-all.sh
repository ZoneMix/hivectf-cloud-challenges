#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/../terraform"

CHALLENGES=(
    "challenge-1-bucket-list"
    "challenge-2-role-call"
    "challenge-3-bees-knees"
    "challenge-4-hive-mind"
    "challenge-5-queens-gambit"
)

echo "========================================="
echo "  HiveCTF - Deploy All Challenges"
echo "========================================="
echo ""

FAILED=()
SUCCEEDED=()

for challenge in "${CHALLENGES[@]}"; do
    echo "--- Deploying ${challenge} ---"
    challenge_dir="${TERRAFORM_DIR}/${challenge}"

    if [ ! -d "${challenge_dir}" ]; then
        echo "  [SKIP] Directory not found: ${challenge_dir}"
        continue
    fi

    cd "${challenge_dir}"

    if ! terraform init -input=false -no-color > /dev/null 2>&1; then
        echo "  [FAIL] terraform init failed for ${challenge}"
        FAILED+=("${challenge}")
        continue
    fi

    if terraform apply -auto-approve -input=false -no-color; then
        echo "  [OK] ${challenge} deployed successfully"
        echo ""
        echo "  Outputs:"
        terraform output -no-color 2>/dev/null | sed 's/^/    /'
        SUCCEEDED+=("${challenge}")
    else
        echo "  [FAIL] terraform apply failed for ${challenge}"
        FAILED+=("${challenge}")
    fi

    echo ""
done

echo "========================================="
echo "  Deployment Summary"
echo "========================================="
echo "  Succeeded: ${#SUCCEEDED[@]}"
for s in "${SUCCEEDED[@]}"; do
    echo "    - ${s}"
done

if [ ${#FAILED[@]} -gt 0 ]; then
    echo "  Failed: ${#FAILED[@]}"
    for f in "${FAILED[@]}"; do
        echo "    - ${f}"
    done
    exit 1
fi

echo ""
echo "All challenges deployed successfully!"
