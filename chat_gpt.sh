SUGGEST_TYPE="$1"

case "$SUGGEST_TYPE" in
    git-diff)
        DIFF=$(git --no-pager diff --cached)
        if [[ -z $DIFF ]]; then
            echo -e "No diff found; \`git add\` your changes first."
            exit 1
        fi
        CONTENT="Write a concise, human readable commit message, using bullet points if needed, for the following: \n $DIFF \n\nDo not add any punctuation except dashes the output."
        ;;
    branch-name)
        if [[ -z $2 ]]; then
            echo -e "Enter a description to create a branch name from."
            exit 1
        fi
        CONTENT="Create a descriptive git branch name, without a forward slash, as a slug, from the following issue: \n $2"
        ;;
    *)
        CONTENT="$1"
        ;;
esac

payload=$(jq -nc --arg content "$CONTENT" '{
    "model": "gpt-4",
    "messages": [
        {"role": "system", "content": "You are ChatGPT, a large language model trained by OpenAI. Carefully heed the users instructions."},
        {
            "role": "user",
            "content": $content
        }
    ],
   "temperature": 1
}')

# Pass the payload to the OpenAI API chat completions endpoint
response=$(curl -s -X POST https://api.openai.com/v1/chat/completions \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    --data "$payload")

echo $response | jq -r '.choices[0].message.content'
