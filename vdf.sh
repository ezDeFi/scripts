#!/bin/bash

: ${BITSIZE:=2047}

time vdf-cli -l$BITSIZE "$@"

notify-send -t 10000 VDF "

		Done!		Done!		Done!

"
