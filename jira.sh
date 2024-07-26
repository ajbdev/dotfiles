#!/bin/bash

set -e
set -o pipefail

if [ -z "$JIRA_BASE_URL" ] || [ -z "$JIRA_USERNAME" ] || [ -z "$JIRA_API_TOKEN" ]; then
    echo -e "The following ENV vars are required:\n"
    echo -e "JIRA_BASE_URL: Fully qualified domain of JIRA host (e.g., https://acme.atlassian.net)"
    echo -e "JIRA_USERNAME: JIRA username to act on behalf of"
    echo -e "JIRA_API_TOKEN: Generated JIRA API token\n"
    exit 1
fi

GIT_BRANCH_PREFIX="andy"
SCRIPT_DIR=$(dirname "$0")
ISSUE="$1"
AUTH=$(echo -n "$JIRA_USERNAME:$JIRA_API_TOKEN" | base64)

jiraRequest() {
    JIRA_RESPONSE=$(curl -s -H "Authorization: Basic $AUTH" -H "Content-Type: application/json" "$JIRA_BASE_URL/$1")
}

suggestBranchSlug() {
    jiraRequest issue/$ISSUE
    DETAILS="$(echo "$JIRA_RESPONSE" | jq --raw-output '.fields .summary') \n $(echo "$JIRA_RESPONSE" | jq --raw-output '.fields .description')"
    SUGGEST_BRANCH_SLUG="$($SCRIPT_DIR/chat_gpt.sh branch-name $DETAILS)"
}

git fetch
git checkout main
git pull

LOCAL_BRANCH=$(git branch --list "$GIT_BRANCH_PREFIX/$ISSUE/*" | head -n 1)
REMOTE_BRANCH=$(git branch -r --list "origin/$GIT_BRANCH_PREFIX/$ISSUE/*" | head -n 1)

if [ -n "$LOCAL_BRANCH" ]; then
    echo -e "Switching to local branch \`$LOCAL_BRANCH\`"
    git checkout $LOCAL_BRANCH
elif [ -n "$REMOTE_BRANCH" ]; then
    echo -e "Switching to remote branch \`$REMOTE_BRANCH\`"
    git checkout $REMOTE_BRANCH
else
    suggestBranchSlug
    NEW_BRANCH="$GIT_BRANCH_PREFIX/$ISSUE/$SUGGEST_BRANCH_SLUG"
    read -p "New branch [$NEW_BRANCH]: " INPUT_BRANCH

    if [[ -z $INPUT_BRANCH ]]; then
        INPUT_BRANCH="$NEW_BRANCH"
    fi

    git checkout -b $INPUT_BRANCH  
fi
