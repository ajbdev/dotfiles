#!/bin/bash

# Script to fetch JIRA ticket details and launch Claude with prepopulated prompt
# Usage: ./jira_claude.sh TICKET_NUMBER

if [ $# -eq 0 ]; then
    echo "Usage: $0 <JIRA_TICKET_NUMBER>"
    echo "Example: $0 HUM-1234"
    exit 1
fi

TICKET_NUMBER="$1"
AUTH=$(echo -n "$JIRA_USERNAME:$JIRA_API_TOKEN" | base64)

# Check required environment variables
if [ -z "$JIRA_API_TOKEN" ] || [ -z "$JIRA_BASE_URL" ] || [ -z "$JIRA_USERNAME" ]; then
    echo "Error: Required environment variables not set:"
    echo "  JIRA_API_TOKEN, JIRA_BASE_URL, JIRA_USERNAME"
    exit 1
fi

# Fetch ticket data from JIRA API
JIRA_RESPONSE=$(curl -s -L -H "Authorization: Basic $AUTH"  \
    -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    "$JIRA_BASE_URL/issue/$TICKET_NUMBER")

# Check if curl command was successful
if [ $? -ne 0 ]; then
    echo "Error: Failed to connect to JIRA API"
    exit 1
fi

# Extract ticket details from the JSON response
TICKET_TITLE=$(echo "$JIRA_RESPONSE" | jq -r '.fields.summary')
TICKET_DESCRIPTION=$(echo "$JIRA_RESPONSE" | jq -r '.fields.description // "No description provided"')
TICKET_STATUS=$(echo "$JIRA_RESPONSE" | jq -r '.fields.status.name')
TICKET_PRIORITY=$(echo "$JIRA_RESPONSE" | jq -r '.fields.priority.name // "Not set"')
TICKET_TYPE=$(echo "$JIRA_RESPONSE" | jq -r '.fields.issuetype.name')
ASSIGNEE=$(echo "$JIRA_RESPONSE" | jq -r '.fields.assignee.displayName // "Unassigned"')

# Extract attachment information
ATTACHMENTS=$(echo "$JIRA_RESPONSE" | jq -r '.fields.attachment // []')

# Check if ticket exists or if there was an error
if [ "$TICKET_TITLE" = "null" ] || [ -z "$TICKET_TITLE" ]; then
    echo "Error: Could not retrieve ticket $TICKET_NUMBER or ticket does not exist"
    echo "Response: $JIRA_RESPONSE"
    exit 1
fi

# Create temporary directory for attachments
ATTACHMENT_DIR=$(mktemp -d)
ATTACHMENT_FILES=()

# Download attachments if they exist
ATTACHMENT_COUNT=$(echo "$ATTACHMENTS" | jq -r 'length')
if [ "$ATTACHMENT_COUNT" -gt 0 ]; then
    echo "Downloading $ATTACHMENT_COUNT attachment(s)..."
    
    for i in $(seq 0 $((ATTACHMENT_COUNT - 1))); do
        ATTACHMENT_URL=$(echo "$ATTACHMENTS" | jq -r ".[$i].content")
        ATTACHMENT_NAME=$(echo "$ATTACHMENTS" | jq -r ".[$i].filename")
        ATTACHMENT_SIZE=$(echo "$ATTACHMENTS" | jq -r ".[$i].size")
        
        if [ "$ATTACHMENT_URL" != "null" ] && [ "$ATTACHMENT_NAME" != "null" ]; then
            echo "  Downloading: $ATTACHMENT_NAME ($ATTACHMENT_SIZE bytes)"
            ATTACHMENT_PATH="$ATTACHMENT_DIR/$ATTACHMENT_NAME"
            
            # Download the attachment
            curl -s -L -H "Authorization: Basic $AUTH" \
                "$ATTACHMENT_URL" -o "$ATTACHMENT_PATH"
            
            if [ $? -eq 0 ] && [ -f "$ATTACHMENT_PATH" ]; then
                ATTACHMENT_FILES+=("$ATTACHMENT_PATH")
            else
                echo "    Warning: Failed to download $ATTACHMENT_NAME"
            fi
        fi
    done
fi

# Create a comprehensive prompt for Claude
CLAUDE_PROMPT="I'm working on JIRA ticket $TICKET_NUMBER. Here are the details:

**Ticket:** $TICKET_NUMBER
**Title:** $TICKET_TITLE
**Type:** $TICKET_TYPE
**Status:** $TICKET_STATUS
**Priority:** $TICKET_PRIORITY
**Assignee:** $ASSIGNEE

**Description:**
$TICKET_DESCRIPTION"

# Add attachment information to the prompt if attachments exist
if [ ${#ATTACHMENT_FILES[@]} -gt 0 ]; then
    CLAUDE_PROMPT="$CLAUDE_PROMPT

**Attachments:** (${#ATTACHMENT_FILES[@]} file(s) downloaded and attached)"
    for attachment_file in "${ATTACHMENT_FILES[@]}"; do
        attachment_name=$(basename "$attachment_file")
        CLAUDE_PROMPT="$CLAUDE_PROMPT
- $attachment_name"
    done
fi

CLAUDE_PROMPT="$CLAUDE_PROMPT

Please help me understand this ticket and provide guidance on how to approach implementing a solution. Consider:

1. What are the key requirements based on the description?
2. What potential technical approaches could be used?
3. Are there any edge cases or considerations I should be aware of?
4. What would be a good development plan for this ticket?

If you need more context about the codebase or specific technical details, please let me know what additional information would be helpful."

# Create a temporary file with the prompt
TEMP_FILE=$(mktemp)
echo "$CLAUDE_PROMPT" > "$TEMP_FILE"

echo $CLAUDE_PROMPT

# Launch Claude Code with the prompt and attachments
echo "Launching Claude Code with JIRA ticket details..."
if [ ${#ATTACHMENT_FILES[@]} -gt 0 ]; then
    # Launch Claude with prompt and attachment files
    claude < "$TEMP_FILE" "${ATTACHMENT_FILES[@]}"
else
    # Launch Claude with just the prompt
    claude < "$TEMP_FILE"
fi

# Clean up temporary files and attachment directory
rm "$TEMP_FILE"
if [ -d "$ATTACHMENT_DIR" ]; then
    rm -rf "$ATTACHMENT_DIR"
fi
