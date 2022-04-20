#!/bin/bash

RESULT=$(sudo iw dev wlp5s0 scan | grep -A8 'freq:' | grep -E 'freq|SSID|signal|channel')

while IFS= read -r line; do
  name=${line%%:*}
  value=${line#*:}

  if [[ $name == "	freq" ]]; then
    echo "---"
  fi

  if [[ $name == "	DS Parameter set" ]]; then
    echo "	$(echo $value | xargs)"
  else
    echo "$line"
  fi
done < <(printf "%s\n" "$RESULT") 
