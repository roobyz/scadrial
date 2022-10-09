#!/bin/bash

IFACE=$(iw dev | awk '$1=="Interface"{print $2}' | tail -n 1)
CHNLS=$(sudo iw dev ${IFACE} scan | grep -A10 'freq:' | grep -E 'freq|SSID|signal|channel')

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
done < <(printf "%s\n" "$CHNLS") 
