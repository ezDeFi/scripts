#!/bin/bash
#
# Usage
#
# Config
#

# A POSIX variable
OPTIND=1         # Reset in case getopts has been used previously in the shell.

# Initialize our own variables:
OPT_PREFUND=

while getopts "h?p" opt; do
    case "$opt" in
    h|\?)
        echo "$(basename ""$0"") [-h|-?] command"
        exit 0
        ;;
	p)
		OPT_PREFUND=1
		;;
    esac
done

shift $((OPTIND-1))

[ "${1:-}" = "--" ] && shift

# CONFIG
: ${BINARY_POSTFIX:=}
: ${PREFUND_ADDR:=000007e01c1507147a0e338db1d029559db6cb19}
: ${PREFUND_KEY:=cd4bdb10b75e803d621f64cc22bffdfc5c4b9f8e63e67820cc27811664d43794}
: ${DATA_DIR:=~/.ethereum}
: ${CONTRACT_BIN_FILE:=nexty.bin}
: ${CONTRACT_BIN:=`cat $CONTRACT_BIN_FILE`}
#: ${SPAM_DATA_SIGNAL:=666666}
: ${GAS_PRICE:=0}
: ${THREAD_PER_IP:=10}
: ${IP_LIST:=`cat endpoints | tr '\r\n' ' '`}
IPS=($IP_LIST)
IPS_IDX=(${!IPS[@]})
IPS_LEN=${#IPS[@]}

OUTPUT_TYPE=table

# Global Variables
BOOTNODE_STRING=
declare -A KEYS
eval "KEYS=(`cat keypairs`)"
echo "${#KEYS[@]} keys loaded."

# COMMAND SHORTCUTS
: ${GETH_CMD:=./build/bin/geth$BINARY_POSTFIX}
: ${PUPPETH_CMD:=./build/bin/puppeth$BINARY_POSTFIX}
: ${BOOTNODE_CMD:=./build/bin/bootnode$BINARY_POSTFIX}
ETHKEY_CMD=ethkey
ETHKEY="$ETHKEY_CMD"
ETHEREAL_CMD=ethereal
ETHEREAL="$ETHEREAL_CMD --log=/dev/null"
#ETHEREAL="$ETHEREAL_CMD --connection=http://localhost:8545/"

function trim {
	awk '{$1=$1};1'
}

function random_ip {
	echo ${IPS[$RANDOM % ${#IPS[@]}]}
}

function random_endpoint {
	echo http://`random_ip`:8545
}

function random_hex {
	LEN=${1:-32000}
	cat /dev/urandom | tr -dc 'a-fA-F0-9' | fold -w $LEN | head -n 1
}

function random_address {
	random_hex 40
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

function prefund {
	IP=${IPS[${IPS_IDX[0]}]}
	ENDPOINT=http://$IP:8545
	FROM=$PREFUND_ADDR
	KEY=$PREFUND_KEY
	BALANCE=`$ETHEREAL eth balance --wei --address=$FROM --connection=$ENDPOINT`
	SPLIT=${BALANCE:0:-3}
	NONCE=`$ETHEREAL acc nonce --address=$FROM --connection=$ENDPOINT`
	i=0
	for TO in "${!KEYS[@]}"; do
		CMD="$ETHEREAL tx send --from=$FROM --to=$TO --privatekey=$KEY --amount=$SPLIT --nonce=$((NONCE+i)) --connection=$ENDPOINT"
		( $CMD >/dev/null || echo "	Failed command ($?): ${CMD:0:100}" ) &
		let i=i+1
		if [ $((i%100)) -eq 0 ]; then
			echo "Funding 100 addresses.."
			wait
		fi
	done
	wait
	echo "Done funding ${#KEYS[@]} addresses."
}

function spam {
	DATA=`random_hex`
	declare -A LISTS

	if [ ! -z "$OPT_PREFUND" ]; then
		prefund
	fi

	# Split the KEYS to each LISTS item for each IP
	i=0
	for FROM in "${!KEYS[@]}"; do
		let j=i%IPS_LEN
		IP=${IPS[${IPS_IDX[j]}]}
		LISTS[$IP]="${LISTS[$IP]} $FROM"
		let i=i+1
	done

	for IP in "${!LISTS[@]}"; do
		LIST=${LISTS[$IP]}

		# Split the addresses to each sublist for each thread
		SUBLISTS=()
		i=0
		for ADDR in $LIST; do
			let j=i%THREAD_PER_IP
			SUBLISTS[$j]="${SUBLISTS[$j]} $ADDR"
			let i=i+1
		done

		ENDPOINT=http://$IP:8545
		REPEAT=100
		SPLIT=1

		for SUBLIST in "${SUBLISTS[@]}"; do
			echo "	$IP @ $SUBLIST"
			(
				while true; do
					for FROM in $SUBLIST; do
						KEY=${KEYS[$FROM]}
						TO=`random_address`
						CMD="$ETHEREAL --repeat=$REPEAT tx send --from=$FROM --to=$TO --privatekey=$KEY --amount=${SPLIT} --connection=$ENDPOINT --gasprice=$GAS_PRICE"
						if [ $((RANDOM%10)) -lt 4 ]; then
							CMD="$ETHEREAL --repeat=$REPEAT contract deploy --from=$FROM --privatekey=$KEY --data=$CONTRACT_BIN --connection=$ENDPOINT"
						elif  [ $((RANDOM%10)) -lt 6 ]; then
							if [ ! -z "$SPAM_DATA_SIGNAL" ]; then
								CMD="$CMD --data=$SPAM_DATA_SIGNAL"
							fi
						else
							CMD="$CMD --data=${SPAM_DATA_SIGNAL}${DATA}"
						fi
						$CMD >/dev/null || echo "	Failed command ($?): ${CMD:0:100}"
					done
				done
			) &
		done
	done

	# trap ctrl-c and call ctrl_c()
	trap clean_up SIGTERM SIGINT SIGKILL
	# wait for any key
	read  -n 1 -p "Press enter to stop..."
	kill $(jobs -p)
	kill -9 $(jobs -p)
	#clean_up
}

function clean_up() {
	echo "** Cleaning up **"
	killall "$(basename ""$0"")" ethereal
}

spam "$@"
