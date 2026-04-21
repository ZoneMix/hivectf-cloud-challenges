#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# HiveCTF - Show All Terraform Outputs
#
# Displays all terraform outputs for deployed challenges in one place.
#
# Usage:
#   ./scripts/show-outputs.sh          # all challenges
#   ./scripts/show-outputs.sh 1        # challenge 1 only
#   ./scripts/show-outputs.sh 2 5      # challenges 2 and 5
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/../terraform"

# Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

tf_out() {
    local dir="$1"
    local key="$2"
    terraform -chdir="$dir" output -raw "$key" 2>/dev/null || echo "(not deployed)"
}

show_challenge_1() {
    local TF_DIR="${TERRAFORM_DIR}/challenge-1-bucket-list"
    echo -e "\n${CYAN}========================================${NC}"
    echo -e "${CYAN}  Challenge 1: Bucket List${NC}"
    echo -e "${CYAN}========================================${NC}"

    if ! terraform -chdir="$TF_DIR" output -json >/dev/null 2>&1; then
        echo -e "  ${RED}Not deployed${NC}"
        return
    fi

    echo -e "  ${BOLD}Website URL:${NC}        http://$(tf_out "$TF_DIR" website_url)"
    echo -e "  ${BOLD}Bucket Name:${NC}        $(tf_out "$TF_DIR" bucket_name)"
    echo -e "  ${BOLD}Access Key ID:${NC}      $(tf_out "$TF_DIR" reader_access_key_id)"
    echo -e "  ${BOLD}Secret Access Key:${NC}  $(tf_out "$TF_DIR" reader_secret_access_key)"
    echo -e "  ${BOLD}Secret ARN:${NC}         $(tf_out "$TF_DIR" secret_arn)"
}

show_challenge_2() {
    local TF_DIR="${TERRAFORM_DIR}/challenge-2-role-call"
    echo -e "\n${CYAN}========================================${NC}"
    echo -e "${CYAN}  Challenge 2: Role Call${NC}"
    echo -e "${CYAN}========================================${NC}"

    if ! terraform -chdir="$TF_DIR" output -json >/dev/null 2>&1; then
        echo -e "  ${RED}Not deployed${NC}"
        return
    fi

    echo -e "  ${BOLD}Intern Username:${NC}    $(tf_out "$TF_DIR" intern_username)"
    echo -e "  ${BOLD}Access Key ID:${NC}      $(tf_out "$TF_DIR" intern_access_key_id)"
    echo -e "  ${BOLD}Secret Access Key:${NC}  $(tf_out "$TF_DIR" intern_secret_access_key)"
    echo -e "  ${BOLD}Dev Role ARN:${NC}       $(tf_out "$TF_DIR" dev_role_arn)"
    echo -e "  ${BOLD}Processor Lambda:${NC}   $(tf_out "$TF_DIR" processor_function_name)"
    echo -e "  ${BOLD}Decoy Lambda:${NC}       $(tf_out "$TF_DIR" public_api_function_name)"
}

show_challenge_3() {
    local TF_DIR="${TERRAFORM_DIR}/challenge-3-bees-knees"
    echo -e "\n${CYAN}========================================${NC}"
    echo -e "${CYAN}  Challenge 3: Bee's Knees${NC}"
    echo -e "${CYAN}========================================${NC}"

    if ! terraform -chdir="$TF_DIR" output -json >/dev/null 2>&1; then
        echo -e "  ${RED}Not deployed${NC}"
        return
    fi

    echo -e "  ${BOLD}API Base URL:${NC}       $(tf_out "$TF_DIR" api_base_url)"
    echo -e "  ${BOLD}Bucket Name:${NC}        $(tf_out "$TF_DIR" bucket_name)"
    echo -e "  ${BOLD}Lambda Function:${NC}    $(tf_out "$TF_DIR" lambda_function_name)"
}

show_challenge_4() {
    local TF_DIR="${TERRAFORM_DIR}/challenge-4-hive-mind"
    echo -e "\n${CYAN}========================================${NC}"
    echo -e "${CYAN}  Challenge 4: Hive Mind${NC}"
    echo -e "${CYAN}========================================${NC}"

    if ! terraform -chdir="$TF_DIR" output -json >/dev/null 2>&1; then
        echo -e "  ${RED}Not deployed${NC}"
        return
    fi

    echo -e "  ${BOLD}Website URL:${NC}        $(tf_out "$TF_DIR" website_url)"
    echo -e "  ${BOLD}User Pool ID:${NC}       $(tf_out "$TF_DIR" cognito_user_pool_id)"
    echo -e "  ${BOLD}Client ID:${NC}          $(tf_out "$TF_DIR" cognito_client_id)"
    echo -e "  ${BOLD}Identity Pool ID:${NC}   $(tf_out "$TF_DIR" cognito_identity_pool_id)"
}

show_challenge_5() {
    local TF_DIR="${TERRAFORM_DIR}/challenge-5-queens-gambit"
    echo -e "\n${CYAN}========================================${NC}"
    echo -e "${CYAN}  Challenge 5: Queen's Gambit${NC}"
    echo -e "${CYAN}========================================${NC}"

    if ! terraform -chdir="$TF_DIR" output -json >/dev/null 2>&1; then
        echo -e "  ${RED}Not deployed${NC}"
        return
    fi

    echo -e "  ${BOLD}Scout Access Key:${NC}   $(tf_out "$TF_DIR" scout_access_key_id)"
    echo -e "  ${BOLD}Scout Secret Key:${NC}   $(tf_out "$TF_DIR" scout_secret_access_key)"
    echo -e "  ${BOLD}Bucket Name:${NC}        $(tf_out "$TF_DIR" bucket_name)"
    echo -e "  ${BOLD}Flag Secret ARN:${NC}    $(tf_out "$TF_DIR" flag_secret_arn)"
}

# ==============================================================================
# Main
# ==============================================================================
echo -e "${CYAN}"
echo "  +=============================================+"
echo "  |     HiveCTF - Terraform Outputs             |"
echo "  +=============================================+"
echo -e "${NC}"

CHALLENGES=()

if [ $# -eq 0 ]; then
    CHALLENGES=(1 2 3 4 5)
else
    CHALLENGES=("$@")
fi

for c in "${CHALLENGES[@]}"; do
    case "$c" in
        1) show_challenge_1 ;;
        2) show_challenge_2 ;;
        3) show_challenge_3 ;;
        4) show_challenge_4 ;;
        5) show_challenge_5 ;;
        *)
            echo -e "${RED}Unknown challenge: $c${NC}"
            echo "Valid options: 1, 2, 3, 4, 5"
            exit 1
            ;;
    esac
done

echo ""
