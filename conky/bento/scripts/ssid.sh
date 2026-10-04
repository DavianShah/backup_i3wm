#!/bin/bash
# Current Wi-Fi SSID (fetched rarely by ${execi 600}).
s=$(/sbin/iwgetid -r 2>/dev/null)
printf '%s\n' "${s:-Not connected}"
