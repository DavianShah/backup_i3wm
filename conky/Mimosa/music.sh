#!/bin/sh
# emit: status|artist|title|duration  (pipes are field separators)
out=$(playerctl metadata --format '{{status}}|{{artist}}|{{title}}|{{duration(mpris:length)}}' 2>/dev/null)
if [ -n "$out" ]; then
  printf '%s\n' "$out"
else
  printf 'OFF||||\n'
fi
