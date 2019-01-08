#!/bin/bash
#
# Usage
#
# Config
#

# A POSIX variable
OPTIND=1         # Reset in case getopts has been used previously in the shell.

# Initialize our own variables:

while getopts "h?" opt; do
    case "$opt" in
    h|\?)
        echo "$(basename ""$0"") [-h|-?] command"
        exit 0
        ;;
    esac
done

shift $((OPTIND-1))

[ "${1:-}" = "--" ] && shift

# CONFIG
: ${NETWORK_NAME:=simnet}
: ${NETWORK_ID:=50613}
: ${BINARY_POSTFIX:=}
: ${PREFUND_ADDR:=000007e01c1507147a0e338db1d029559db6cb19}
: ${DATA_DIR:=~/.ethereum}
: ${CONTRACT_BIN_FILE:=contract.bin}
#: ${CONTRACT_BIN:=}

OUTPUT_TYPE=table

# Global Variables
BOOTNODE_STRING=
declare -A KEYS
KEYS=(
	[$PREFUND_ADDR]=cd4bdb10b75e803d621f64cc22bffdfc5c4b9f8e63e67820cc27811664d43794
)

# COMMAND SHORTCUTS
: ${GETH_CMD:=./build/bin/geth$BINARY_POSTFIX}
: ${PUPPETH_CMD:=./build/bin/puppeth$BINARY_POSTFIX}
: ${BOOTNODE_CMD:=./build/bin/bootnode$BINARY_POSTFIX}
ETHKEY_CMD=`which ethkey`
ETHKEY="$ETHKEY_CMD"
ETHEREAL_CMD=`which ethereal`
ETHEREAL="$ETHEREAL_CMD --connection=http://localhost:8545/"

GETH_CMD=`which geth`
PUPPETH_CMD=`which puppeth`
BOOTNODE_CMD=`which bootnode`
GETH_CMD="$GETH_CMD --datadir=$DATA_DIR"
GETH="$GETH_CMD --syncmode=full --cache 2048 --gcmode=archive --networkid $NETWORK_ID --rpc --rpcapi db,eth,net,web3,personal --rpccorsdomain \"*\" --rpcaddr 0.0.0.0 --gasprice 0 --targetgaslimit 42000000 --txpool.nolocals --txpool.pricelimit 0"

function trim {
	awk '{$1=$1};1'
}

function random_hex {
	LEN=${1:-32000}
	cat /dev/urandom | tr -dc 'a-fA-F0-9' | fold -w $LEN | head -n 1
}

function new_key_pair {
	while read -r line; do
		if [ ${line:0:6} = secret ]; then
			key=${line:9}
		elif [ ${line:0:7} = address ]; then
			addr=${line:9}
		fi
	done < <($ETHKEY generate random)
	echo $addr $key
	#KEYS[$addr]=$key
}

function new_address {
	while read -r line; do
		if [ ${line:0:7} = address ]; then
			echo ${line:9}
			return
		fi
	done < <($ETHKEY generate random)
}

function send_tx {
	FROM=$1
	TO=$2
	AMOUNT=$3
	ETHEREAL tx send --from=$FROM --to=$TO --privatekey=KEYS[$addr] --amount=$SPLIT
}

# spam FROM N
function spam {
	FROM=${1:-$PREFUND_ADDR}
	N=${2:-1}

	DATA=`random_hex`

	KEY=${KEYS[$FROM]}
	BALANCE=`$ETHEREAL eth balance --address=$FROM`
	BALANCE=${BALANCE%.*}
	SPLIT=${BALANCE:0:-2}
	NONCE=`$ETHEREAL acc nonce --address=$FROM`
	j=0
	while [ $j -lt 99 ]; do
		PAIR=(`new_key_pair`)
		TO=${PAIR[0]}
		KEYS[$TO]=${PAIR[1]}
		(
			echo "	${FROM:0:6} -> ${TO:0:6}"
			$ETHEREAL tx send --from=$FROM --to=$TO --privatekey=$KEY --amount=$SPLIT --nonce=$((NONCE+j)) #--data=$DATA
		) &
		let j=j+1
	done

	wait
	echo ====================== ${#KEYS[@]} ===========================
	sleep 4s

	for FROM in "${!KEYS[@]}"
	do
		KEY=${KEYS[$FROM]}
		(
			BALANCE=`$ETHEREAL eth balance --address=$FROM`
			BALANCE=${BALANCE%.*}
			SPLIT=${BALANCE:0:-3}
			TO=`new_address`
			echo "	${FROM:0:6} -> ${TO:0:6}"
			#$ETHEREAL --repeat=1000 contract deploy --from=$FROM --privatekey=$KEY --data=$CONTRACT_BIN_FILE #--quiet
			CMD="$ETHEREAL --repeat=1000 tx send --from=$FROM --to=$TO --privatekey=$KEY --amount=$SPLIT"
			if [ "$FROM" != "$PREFUND_ADDR" ]; then
				CMD="$CMD --data=$DATA"
			fi
			$CMD #--quiet
		) &
	done

	read  -n 1 -p "Press enter to stop."
	kill $(jobs -p)
	kill -9 $(jobs -p)
}

"$@"
