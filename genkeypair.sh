#!/bin/bash

: ${ETHKEY:=ethkey}

function new_key_pair {
	while read -r line; do
		if [ ${line:0:6} = secret ]; then
			key=${line:9}
		elif [ ${line:0:7} = address ]; then
			addr=${line:9}
		fi
	done < <($ETHKEY generate random)
	echo [$addr]=$key
}

for i in `seq 1 $1`; do
	new_key_pair
done
