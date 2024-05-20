#!/bin/bash

diff_content="Write a commit message in the style of conventional commits specification, using bullet points, for the following: \n $(git --no-pager diff --cached)"

echo $diff_content

payload=$(jq -nc --arg content "$diff_content" '{
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
