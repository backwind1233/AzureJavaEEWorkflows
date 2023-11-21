#!/usr/bin/env bash
################################################
# This script is invoked by a human who:
# - has done az login.
# - can create repository secrets in the github repo from which this file was cloned.
# - has the gh client >= 2.0.0 installed.
#
# This script initializes the repo from which this file is was cloned
# with the necessary secrets to run the workflows.
#
# Script design taken from https://github.com/microsoft/NubesGen.
#
################################################

################################################
# Set environment variables - the main variables you might want to configure.
#
# Three letters to disambiguate names.
DISAMBIG_PREFIX=workflow-$(date +%s)
# The location of the resource group. For example `eastus`. Leave blank to use your default location.
LOCATION=

GH_FLAGS=""

SLEEP_VALUE=30s

# User Email of Oracle acount
ORACLE_USER_EMAIL=
# User Password of Oracle acount
ORACLE_USER_PASSWORD=

# End set environment variables
################################################


set -Eeuo pipefail
trap cleanup SIGINT SIGTERM ERR EXIT

isOsMac="false"
if [[ $OSTYPE == 'darwin'* ]]; then
    isOsMac="true"
fi

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

# get ORACLE_USER_EMAIL if not set at the beginning of this file
if [ "$ORACLE_USER_EMAIL" == '' ] ; then
    read -r -p "Enter user email of Oracle account: " ORACLE_USER_EMAIL
fi

# get ORACLE_USER_PASSWORD if not set at the beginning of this file
if [ "$ORACLE_USER_PASSWORD" == '' ] ; then
    read -s -r -p "Enter user password of Oracle account: " ORACLE_USER_PASSWORD
fi


# Comment out adding date suffix to make it works with tear down script
# DISAMBIG_PREFIX=${DISAMBIG_PREFIX}`date +%m%d`
SERVICE_PRINCIPAL_NAME=${DISAMBIG_PREFIX}sp

# get default location if not set at the beginning of this file
if [ "$LOCATION" == '' ] ; then
    {
      az config get defaults.location --only-show-errors > /dev/null 2>&1
      LOCATION_DEFAULTS_SETUP=$?
    } || {
      LOCATION_DEFAULTS_SETUP=0
    }
    # if no default location is set, fallback to "eastus"
    if [ "$LOCATION_DEFAULTS_SETUP" -eq 1 ]; then
      LOCATION=eastus
    else
      LOCATION=$(az config get defaults.location --only-show-errors | jq -r .value)
    fi
fi

# Check AZ CLI status
msg "${GREEN}(1/4) Checking Azure CLI status...${NOFORMAT}"
{
  az > /dev/null
} || {
  msg "${RED}Azure CLI is not installed."
  msg "${GREEN}Go to https://aka.ms/nubesgen-install-az-cli to install Azure CLI."
  exit 1;
}
{
  az account show > /dev/null
} || {
  msg "${RED}You are not authenticated with Azure CLI."
  msg "${GREEN}Run \"az login\" to authenticate."
  exit 1;
}

msg "${YELLOW}Azure CLI is installed and configured!"

# Check GitHub CLI status
msg "${GREEN}(2/4) Checking GitHub CLI status...${NOFORMAT}"
USE_GITHUB_CLI=false
{
  gh auth status && USE_GITHUB_CLI=true && msg "${YELLOW}GitHub CLI is installed and configured!"
} || {
  msg "${YELLOW}Cannot use the GitHub CLI. ${GREEN}No worries! ${YELLOW}We'll set up the GitHub secrets manually."
  USE_GITHUB_CLI=false
}

# Execute commands
msg "${GREEN}(3/4) Create service principal and Azure credentials ${SERVICE_PRINCIPAL_NAME}"
SUBSCRIPTION_ID=$(az account show --query id --output tsv --only-show-errors)

### AZ ACTION CREATE

if [[ "${isOsMac}" == "true" ]]; then
    SERVICE_PRINCIPAL=$(az ad sp create-for-rbac --name ${SERVICE_PRINCIPAL_NAME} --role="Contributor" --scopes="/subscriptions/${SUBSCRIPTION_ID}" --sdk-auth --only-show-errors | base64)
else
    SERVICE_PRINCIPAL=$(az ad sp create-for-rbac --name ${SERVICE_PRINCIPAL_NAME} --role="Contributor" --scopes="/subscriptions/${SUBSCRIPTION_ID}" --sdk-auth --only-show-errors | base64 -w0)
fi

SP_ID=$( az ad sp list --display-name $SERVICE_PRINCIPAL_NAME --query '[0]'.id -o tsv)
az role assignment create --assignee ${SP_ID} --role "User Access Administrator" --subscription "${SUBSCRIPTION_ID}" --scope "/subscriptions/${SUBSCRIPTION_ID}"
AZURE_CREDENTIALS=$(echo $SERVICE_PRINCIPAL | base64 -d)

# Get Azure Account Uesrname
AZURE_ACCOUNT_USER=$(az account show --query user.name -o tsv)

msg "${GREEN}(4/4) Create secrets/variables in GitHub"
if $USE_GITHUB_CLI; then
  {
    msg "${GREEN}Using the GitHub CLI to set secrets.${NOFORMAT}"
    gh ${GH_FLAGS} secret set AZURE_CREDENTIALS -b"${AZURE_CREDENTIALS}"
    msg "${YELLOW}\"AZURE_CREDENTIALS\""
    msg "${GREEN}${AZURE_CREDENTIALS}"
    gh ${GH_FLAGS} secret set SERVICE_PRINCIPAL -b"${SERVICE_PRINCIPAL}"
    msg "${YELLOW}\"SERVICE_PRINCIPAL\""
    msg "${GREEN}${SERVICE_PRINCIPAL}"
    gh ${GH_FLAGS} secret set ORACLE_USER_EMAIL -b"${ORACLE_USER_EMAIL}"
    msg "${YELLOW}\"ORACLE_USER_EMAIL\""
    msg "${GREEN}${ORACLE_USER_EMAIL}"
    gh ${GH_FLAGS} secret set ORACLE_USER_PASSWORD -b"${ORACLE_USER_PASSWORD}"
    msg "${YELLOW}\"ORACLE_USER_PASSWORD\""
    msg "${GREEN}${ORACLE_USER_PASSWORD}"

    msg "${GREEN}Using the GitHub CLI to set variables.${NOFORMAT}"
    gh ${GH_FLAGS} variable set DISAMBIG_PREFIX -b"${DISAMBIG_PREFIX}"
    msg "${YELLOW}\"DISAMBIG_PREFIX\""
    msg "${GREEN}${DISAMBIG_PREFIX}"
    gh ${GH_FLAGS} variable set AZURE_ACCOUNT_USER -b"${AZURE_ACCOUNT_USER}"
    msg "${YELLOW}\"AZURE_ACCOUNT_USER\""
    msg "${GREEN}${AZURE_ACCOUNT_USER}"


  } || {
    USE_GITHUB_CLI=false
  }
fi
if [ $USE_GITHUB_CLI == false ]; then
  msg "${NOFORMAT}======================MANUAL SETUP======================================"
  msg "${GREEN}Using your Web browser to set up secrets..."
  msg "${NOFORMAT}Go to the GitHub repository you want to configure."
  msg "${NOFORMAT}In the \"settings\", go to the \"secrets\" tab and the following secrets:"
  msg "(in ${YELLOW}yellow the secret name and${NOFORMAT} in ${GREEN}green the secret value)"
  msg "${YELLOW}\"AZURE_CREDENTIALS\""
  msg "${GREEN}${AZURE_CREDENTIALS}"
  msg "${YELLOW}\"SERVICE_PRINCIPAL\""
  msg "${GREEN}${SERVICE_PRINCIPAL}"
  msg "${YELLOW}\"DISAMBIG_PREFIX\""
  msg "${GREEN}${DISAMBIG_PREFIX}"
  msg "${YELLOW}\"ORACLE_USER_EMAIL\""
  msg "${GREEN}${ORACLE_USER_EMAIL}"
  msg "${YELLOW}\"ORACLE_USER_PASSWORD\""
  msg "${GREEN}${ORACLE_USER_PASSWORD}"
  msg "${NOFORMAT}========================================================================"
fi
msg "${GREEN}Secrets configured"
