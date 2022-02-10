#!/usr/bin/env bash

set -euo pipefail

# Complete script for API-driven runs.
# Documentation can be found at:
# https://www.terraform.io/docs/cloud/run/api.html


function processCmdLine() {
  local -n args="${1}"
  shift

  while getopts "a:c:" arg; do
    case $arg in
    a) args[account]=${OPTARG}     ;;
    c) args[content]=${OPTARG}     ;;
    *) exit 1                      ;;
    esac
  done
}

function checkArgs() {
  # shellcheck disable=SC2178
  local -nr args="${1}"

  if [[ ! -v args[@] ]]; then
    echo "args unset"
    usage
    exit 1
  elif [[ ! -v args[account] || ${#args[account]} -eq 0 ]]; then
    echo "Problem with -a ACCOUNT argument - represents TFC org/workspace"
    usage
    exit 1
  elif [[ ! -v args[content] ||  ${#args[content]} -eq 0 ]]; then
    echo "Problem with -c CONTENT argument - represents HCL dir"
    usage
    exit 1
  elif [[ ! -v TOKEN || ${#TOKEN} -eq 0 ]]; then
    echo "Problem with TOKEN environment variable - obtain from TFC/E"
    usage
    exit 1
  fi

  # shellcheck disable=SC2129
  echo "Final values are"
  echo "ACCOUNT = ${args[account]}"
  echo "CONTENT = ${args[content]}"
}

function usage() {
  # shellcheck disable=SC2129
  echo "required arguments are"
  echo "  -a <account>     : TFC org/workspace"
  echo "  -c <content>     : HCL content directory"
  echo "export TOKEN=<token from TFE/C>"
}

function run() {
  # shellcheck disable=SC2178
  local -n args="${1}"

  ORG_NAME="$(cut -d'/' -f1 <<<"${args[account]}")"
  WORKSPACE_NAME="$(cut -d'/' -f2 <<<"${args[account]}")"

  echo "ORG_NAME       == ${ORG_NAME}"
  echo "WORKSPACE_NAME == ${WORKSPACE_NAME}"

  # 2. Create the File for Upload

  UPLOAD_FILE_NAME="./content-$(date +%s).tar.gz"
  tar -zcvf "$UPLOAD_FILE_NAME" -C "${args[content]}" . > /dev/null 2>&1

  # 3. Look Up the Workspace ID

  WORKSPACE_ID=($(curl \
    --silent \
    --header "Authorization: Bearer $TOKEN" \
    --header "Content-Type: application/vnd.api+json" \
    https://app.terraform.io/api/v2/organizations/$ORG_NAME/workspaces/$WORKSPACE_NAME \
    | jq -r '.data.id'))

  # 4. Create a New Configuration Version

  echo '{"data":{"type":"configuration-versions"}}' > ./create_config_version.json

  UPLOAD_URL=($(curl \
    --silent \
    --header "Authorization: Bearer $TOKEN" \
    --header "Content-Type: application/vnd.api+json" \
    --request POST \
    --data @create_config_version.json \
    https://app.terraform.io/api/v2/workspaces/$WORKSPACE_ID/configuration-versions \
    | jq -r '.data.attributes."upload-url"' ))

  # 5. Upload the Configuration Content File

  curl \
    --silent \
    --header "Content-Type: application/octet-stream" \
    --request PUT \
    --data-binary @"$UPLOAD_FILE_NAME" \
    $UPLOAD_URL > /dev/null 2>&1

  rc=$?

  # 6. Delete Temporary Files

  rm "$UPLOAD_FILE_NAME"
  rm ./create_config_version.json

  return ${rc}
}

# shellcheck disable=SC2034
declare -A arguments

processCmdLine arguments "$@"

echo "check argument validity"
checkArgs arguments

echo "upload HCL to TFC/E"
run arguments

exit $?
