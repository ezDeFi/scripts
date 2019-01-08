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
: ${CONTRACT_BIN_FILE:=nexty.bin}
: ${CONTRACT_BIN:=`cat $CONTRACT_BIN_FILE`}
#: ${SPAM_DATA_SIGNAL:=666666}

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

# spam FROM N
function spam {
	FROM=${1:-$PREFUND_ADDR}
	N=${2:-1}

	DATA=`random_hex`

	KEY=${KEYS[$FROM]}
	BALANCE=`$ETHEREAL eth balance --address=$FROM`
	BALANCE=${BALANCE% *}
	BALANCE=${BALANCE%.*}
	SPLIT=${BALANCE:0:-3}
	NONCE=`$ETHEREAL acc nonce --address=$FROM`
	j=1
	while [ $j -lt 256 ]; do
		PAIR=(`new_key_pair`)
		TO=${PAIR[0]}
		KEYS[$TO]=${PAIR[1]}
		(
			echo "	${FROM:0:6} -> ${TO:0:6}: ${SPLIT}"
			$ETHEREAL tx send --from=$FROM --to=$TO --privatekey=$KEY --amount=${SPLIT}ether --nonce=$((NONCE+j)) #--data=$DATA
		) &
		let j=j+1
	done

	wait
	echo ====================== ${#KEYS[@]} ===========================
	sleep 4s

	i=0
	for FROM in "${!KEYS[@]}"
	do
		KEY=${KEYS[$FROM]}
		(
			j=0
			while [ $j -lt 100 ]; do
				BALANCE=
				while [ -z "$BALANCE" ]; do
					BALANCE=`$ETHEREAL eth balance --address=$FROM`
					BALANCE=${BALANCE% *}
					if [ -z "$BALANCE" ]; then
						echo "Unable to get balance of account: ${FROM:0:6}" >&2
						exit
					elif [ "$BALANCE" = "0" ]; then
						BALANCE=
						sleep 1s
					fi
				done
				ROUND=${BALANCE%\.*}
				if [ "${#ROUND}" -eq 1 ] && [ "$ROUND" -eq 0 ]; then
					echo "Balance to small ($BALANCE), account: ${FROM:0:6}" >&2
					exit
				fi

				PAIR=(`new_key_pair`)
				TO=${PAIR[0]}
				echo "	${FROM:0:6} -> ${TO:0:6}: $BALANCE"
				$ETHEREAL tx send --from=$FROM --to=$TO --privatekey=$KEY --amount=${ROUND:0:-1}ether --quiet

				REPEAT=80
				if [ $j -eq 0 ]; then
					WIGGLE=`shuf -i 0-$REPEAT -n 1`
					((REPEAT=REPEAT+WIGGLE))
				fi
				SPLIT=0 #${ROUND:0:-3}ether
				CMD="$ETHEREAL --repeat=$REPEAT tx send --from=$FROM --to=$TO --privatekey=$KEY --amount=${SPLIT}"
				if [ "$i" -lt 10 ]; then
					CMD="$ETHEREAL --repeat=$REPEAT contract deploy --from=$FROM --privatekey=$KEY --data=$CONTRACT_BIN"
				elif  [ "$i" -lt 20 ]; then
					if [ ! -z "$SPAM_DATA_SIGNAL" ]; then
						CMD="$CMD --data=$SPAM_DATA_SIGNAL"
					fi
				else
					CMD="$CMD --data=${SPAM_DATA_SIGNAL}${DATA}"
				fi
				$CMD --quiet

				let j=j+1
				FROM=$TO
				KEY=${PAIR[1]}
			done
		) &
		let i=i+1
	done

	read  -n 1 -p "Press enter to stop."
	kill $(jobs -p)
	kill -9 $(jobs -p)
}

"$@"
