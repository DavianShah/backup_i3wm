#!/bin/bash

# v1.2
# Closebox73

# Read raw CPU temperature in millidegree Celsius
temp_raw=$(</sys/class/thermal/thermal_zone0/temp)

# Convert to Celsius
temp_c=$(echo "$temp_raw / 1000" | bc -l)

# Convert to Fahrenheit and round to nearest integer
temp_f=$(printf "%.0f" "$(echo "$temp_c * 9 / 5 + 32" | bc -l)")

# Output
echo "$temp_f"

exit 0
