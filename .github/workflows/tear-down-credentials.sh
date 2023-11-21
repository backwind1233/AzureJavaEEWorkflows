#!/usr/bin/env bash
################################################
# This script is invoked by a human who:
# - has invoked the setup-cluster-credentials.sh script
#
# This script removes the secrets and deletes the azure resources created in
# setup-cluster-credentials.sh.
#
# Script design taken from https://github.com/microsoft/NubesGen.
#
################################################


set -Eeuo pipefail
trap cleanup SIGINT SIGTERM ERR EXIT

cleanup() {
  trap - SIGINT SIGTERM ERR EXIT
  # script cleanup here
}

setup_colors() {
  if [[ -t 2 ]] && [[ -z "${NO_COLOR-}" ]] && [[ "${TERM-}" != "dumb" ]]; then
    NOFORMAT='\033[0m' RED='\033[0;31m' GREEN='\033[0;32m' ORANGE='\033[0;33m' BLUE='\033[0;34m' PURPLE='\033[0;35m' CYAN='\033[0;36m' YELLOW='\033[1;33m'
  else
    NOFORMAT='' RED='' GREEN='' ORANGE='' BLUE='' PURPLE='' CYAN='' YELLOW=''
  fi
}

msg() {
  echo >&2 -e "${1-}"
}

setup_colors

DISAMBIG_PREFIX=$(gh variable list | grep DISAMBIG_PREFIX | awk '{print $2}')

GH_FLAGS=""

echo DISAMBIG_PREFIX=$DISAMBIG_PREFIX
SERVICE_PRINCIPAL_NAME=${DISAMBIG_PREFIX}sp

# Execute commands
msg "${GREEN}(1/3) Delete service principal ${SERVICE_PRINCIPAL_NAME}"
SUBSCRIPTION_ID=$(az account show --query id --output tsv --only-show-errors)
SP_OBJECT_ID_ARRAY=$(az ad sp list --display-name ${SERVICE_PRINCIPAL_NAME} --query "[].id") || true
# remove whitespace
SP_OBJECT_ID_ARRAY=$(echo ${SP_OBJECT_ID_ARRAY} | xargs) || true
SP_OBJECT_ID_ARRAY=${SP_OBJECT_ID_ARRAY//[/}
SP_OBJECT_ID=${SP_OBJECT_ID_ARRAY//]/}
az ad sp delete --id ${SP_OBJECT_ID} || true

# Check GitHub CLI status
msg "${GREEN}(2/3) Checking GitHub CLI status...${NOFORMAT}"
USE_GITHUB_CLI=false
{
  gh auth status && USE_GITHUB_CLI=true && msg "${YELLOW}GitHub CLI is installed and configured!"
} || {
  msg "${YELLOW}Cannot use the GitHub CLI. ${GREEN}No worries! ${YELLOW}We'll set up the GitHub secrets manually."
  USE_GITHUB_CLI=false
}

msg "${GREEN}(3/3) Removing secrets/variables...${NOFORMAT}"
if $USE_GITHUB_CLI; then
  {
    msg "${GREEN}Using the GitHub CLI to remove secrets.${NOFORMAT}"
    gh ${GH_FLAGS} secret remove AZURE_CREDENTIALS
    gh ${GH_FLAGS} secret remove SERVICE_PRINCIPAL
    gh ${GH_FLAGS} secret remove ORACLE_USER_EMAIL
    gh ${GH_FLAGS} secret remove ORACLE_USER_PASSWORD

    msg "${GREEN}Using the GitHub CLI to remove variables.${NOFORMAT}"
    gh ${GH_FLAGS} variable remove DISAMBIG_PREFIX
    gh ${GH_FLAGS} variable remove AZURE_ACCOUNT_USER
  } || {
    USE_GITHUB_CLI=false
  }
fi
if [ $USE_GITHUB_CLI == false ]; then
  msg "${NOFORMAT}======================MANUAL REMOVAL======================================"
  msg "${GREEN}Using your Web browser to remove secrets..."
  msg "${NOFORMAT}Go to the GitHub repository you want to configure."
  msg "${NOFORMAT}In the \"settings\", go to the \"secrets\" tab and remove the following secrets:"
  msg "(in ${YELLOW}yellow the secret name)"
  msg "${YELLOW}\"AZURE_CREDENTIALS\""
  msg "${YELLOW}\"SERVICE_PRINCIPAL\""
  msg "${YELLOW}\"ORACLE_USER_EMAIL\""
  msg "${YELLOW}\"ORACLE_USER_PASSWORD\""
  msg "${NOFORMAT}========================================================================"
fi
msg "${GREEN}Secrets removed"
