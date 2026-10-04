#!/bin/sh
# launch/restart Mimosa conky widget (called by i3 exec_always)
pkill -x conky 2>/dev/null
sleep 0.3
export LD_LIBRARY_PATH="$HOME/.local/conky/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
"$HOME/.local/conky/usr/bin/conky" -c "$HOME/.config/conky/Mimosa/conky.conf" &
CONKY_PID=$!

# sink widget to bottom of X stack: covered by app windows,
# visible only when no window covers it (empty workspace)
wid=
i=0
while [ $i -lt 10 ]; do
  wid=$(/usr/bin/xdotool search --class conky 2>/dev/null | head -n1)
  [ -n "$wid" ] && break
  i=$((i + 1))
  sleep 0.5
done
[ -n "$wid" ] && python3 "$HOME/.config/conky/Mimosa/lower.py" "$wid"

wait "$CONKY_PID"
