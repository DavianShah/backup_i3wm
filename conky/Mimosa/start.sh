#!/bin/bash

# Close all active Conky instances
killall conky 2>/dev/null
sleep 2s

# Launch specific Conky config
# Add more lines below if combining with other themes
conky -c "$HOME/.config/conky/Mimosa/Mimosa.conf" &> /dev/null &

exit 0
