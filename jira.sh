#!/bin/bash

set -e
set -o pipefail

if [ -z "$JIRA_BASE_URL" ] || [ -z "$JIRA_USERNAME" ] || [ -z "$JIRA_API_TOKEN" ] || [ -z "$GIT_BRANCH_PREFIX"  ]; then
    echo -e "The following ENV vars are required:\n"
    echo -e "JIRA_BASE_URL: Fully qualified domain of JIRA host (e.g., https://acme.atlassian.net)"
    echo -e "JIRA_USERNAME: JIRA username to act on behalf of"
    echo -e "JIRA_API_TOKEN: Generated JIRA API token"
    echo -e "GIT_BRANCH_PREFIX: First folder name of git branch\n"
    exit 1
fi

SCRIPT_DIR=$(dirname "$0")
ISSUE="$1"
AUTH=$(echo -n "$JIRA_USERNAME:$JIRA_API_TOKEN" | base64)


jiraRequest() {
    JIRA_RESPONSE=$(curl -s -H "Authorization: Basic $AUTH" -H "Content-Type: application/json" "$JIRA_BASE_URL/$1")
}

suggestBranchSlug() {
    SUGGEST_BRANCH_SLUG=$($SCRIPT_DIR/chat_gpt.sh branch-name "$DETAILS")
}

promptBranchName() {
    suggestBranchSlug
    NEW_BRANCH="$GIT_BRANCH_PREFIX/$ISSUE/$SUGGEST_BRANCH_SLUG"
    read -p "New branch [$NEW_BRANCH] (! to resuggest): " INPUT_BRANCH

    if [[ -z $INPUT_BRANCH ]]; then
        INPUT_BRANCH="$NEW_BRANCH"
    elif [[ "$INPUT_BRANCH" == "!" ]]; then
        promptBranchName
    fi
}

if [[ $1 == "finish" ]]; then
    COMMIT_MSG=$($SCRIPT_DIR/chat_gpt.sh git-diff)
    echo "$COMMIT_MSG" | git commit -e -F - 
    exit
fi

git fetch
git checkout main
git pull

jiraRequest issue/$ISSUE
DETAILS="$(echo "$JIRA_RESPONSE" | jq --raw-output '.fields .summary') \n\n $(echo "$JIRA_RESPONSE" | jq --raw-output '.fields .description')\n"
echo -e "Issue $ISSUE"
echo -e $DETAILS

LOCAL_BRANCH=$(git branch --list "$GIT_BRANCH_PREFIX/$ISSUE/*" | head -n 1)
REMOTE_BRANCH=$(git branch -r --list "origin/$GIT_BRANCH_PREFIX/$ISSUE/*" | head -n 1)

if [ -n "$LOCAL_BRANCH" ]; then
    echo -e "Switching to local branch \`$LOCAL_BRANCH\`"
    git checkout $LOCAL_BRANCH
elif [ -n "$REMOTE_BRANCH" ]; then
    echo -e "Switching to remote branch \`$REMOTE_BRANCH\`"
    git checkout $REMOTE_BRANCH
else
    promptBranchName

    git checkout -b $INPUT_BRANCH  
fi
