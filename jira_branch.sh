#!/bin/bash

# Script to fetch JIRA ticket title and generate a branch name
# Usage: ./jira_branch.sh TICKET_NUMBER

if [ $# -eq 0 ]; then
    echo "Usage: $0 <JIRA_TICKET_NUMBER>"
    echo "Example: $0 HUM-1234"
    exit 1
fi

TICKET_NUMBER="$1"
AUTH=$(echo -n "$JIRA_USERNAME:$JIRA_API_TOKEN" | base64)

# Check required environment variables
if [ -z "$JIRA_API_TOKEN" ] || [ -z "$JIRA_BASE_URL" ] || [ -z "$JIRA_USERNAME" ] || [ -z "$GIT_BRANCH_PREFIX" ]; then
    echo "Error: Required environment variables not set:"
    echo "  JIRA_API_TOKEN, JIRA_BASE_URL, JIRA_USERNAME, GIT_BRANCH_PREFIX"
    exit 1
fi

# Fetch ticket data from JIRA API
JIRA_RESPONSE=$(curl -s -L -H "Authorization: Basic $AUTH"  \
    -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    "$JIRA_BASE_URL/rest/api/2/issue/$TICKET_NUMBER")

# Check if curl command was successful
if [ $? -ne 0 ]; then
    echo "Error: Failed to connect to JIRA API"
    exit 1
fi

# Extract the ticket title from the JSON response
TICKET_TITLE=$(echo "$JIRA_RESPONSE" | jq -r '.fields.summary')

# Check if ticket exists or if there was an error
if [ "$TICKET_TITLE" = "null" ] || [ -z "$TICKET_TITLE" ]; then
    echo "Error: Could not retrieve ticket $TICKET_NUMBER or ticket does not exist"
    echo "Response: $JIRA_RESPONSE"
    exit 1
fi

# Create a prompt for Claude Code to generate a slugified branch name
CLAUDE_PROMPT="Convert the following JIRA ticket title to a slugified branch name suitable for git. 
The title is: '$TICKET_TITLE'
Please return only the slugified name (lowercase, hyphens instead of spaces, no special characters except hyphens, max 50 chars)."

# Use Claude Code to generate the slugified branch name
SLUGIFIED_NAME=$(echo "$CLAUDE_PROMPT" | claude-code --no-interactive 2>/dev/null | tail -n 1 | tr -d '\n')

# Fallback slugification if Claude Code fails
if [ -z "$SLUGIFIED_NAME" ] || [ ${#SLUGIFIED_NAME} -gt 50 ]; then
    # Manual slugification as fallback
    SLUGIFIED_NAME=$(echo "$TICKET_TITLE" | \
        tr '[:upper:]' '[:lower:]' | \
        sed 's/[^a-z0-9]/-/g' | \
        sed 's/--*/-/g' | \
        sed 's/^-\|-$//g' | \
        cut -c1-50 | \
        sed 's/-$//')
fi

# Generate the final branch name
BRANCH_NAME="$GIT_BRANCH_PREFIX/$TICKET_NUMBER/$SLUGIFIED_NAME"

echo "$BRANCH_NAME"