#!/bin/zsh
# usage: cover_gen.sh name aspect "prompt"
KEY=$(grep '^OPENROUTER_API_KEY=' ../../.env | cut -d= -f2- | tr -d '"')
jq -n --arg p "$3" --arg a "$2" '{model:"google/gemini-3-pro-image",messages:[{role:"user",content:$p}],modalities:["image","text"],image_config:{aspect_ratio:$a}}' \
 | curl -sS https://openrouter.ai/api/v1/chat/completions -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' -d @- -o raw/cover/$1.json
jq -r '.choices[0].message.images[0].image_url.url // empty' raw/cover/$1.json | sed 's/^data:image\/[a-z]*;base64,//' | base64 -d > raw/cover/$1.png 2>/dev/null
[ -s raw/cover/$1.png ] && echo "$1 ok $(jq '.usage.cost' raw/cover/$1.json)" || { echo "$1 FAIL"; jq -c '.error' raw/cover/$1.json | cut -c1-200; }
