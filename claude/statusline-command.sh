#!/bin/sh
input=$(cat)
model=$(echo "$input" | jq -r '.model.display_name // "Unknown Model"')
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

if [ -n "$used" ]; then
  printf "\033[1;36m%s\033[0m  \033[0;33mContext:\033[0m %s%%" "$model" "$used"
else
  printf "\033[1;36m%s\033[0m" "$model"
fi
