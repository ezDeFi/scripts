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
: ${GAS_PRICE:=9000000000}
: ${IPS:=(18.191.160.71 18.224.39.130 52.43.241.206 52.53.177.205 54.183.206.45 54.201.181.84 54.215.213.102)}
: ${THREAD_PER_IP:=2}

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
ETHKEY_CMD=`which ethkey`
ETHKEY="$ETHKEY_CMD"
ETHEREAL_CMD=`which ethereal`
ETHEREAL="$ETHEREAL_CMD"
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

function spam2 {
	declare -A LISTS
	LISTS=()

	IP_IDXS=(${!IPS[@]})
	IP_N=${#IPS[@]}

	i=0
	for FROM in "${!KEYS[@]}"; do
		let j=i%IP_N
		IP=${IPS[${IP_IDXS[j]}]}
		LISTS[$IP]="${LISTS[$IP]} $FROM"
		let i=i+1
	done

	DATA=`random_hex`

	for IP in "${!LISTS[@]}"; do
		LIST=${LISTS[$IP]}

		SUBLISTS=()
		i=0
		for ADDR in $LIST; do
			let j=i%THREAD_PER_IP
			SUBLISTS[$j]="${SUBLISTS[$j]} $ADDR"
			let i=i+1
		done 

		ENDPOINT=http://$IP:8545
		echo "	${ENDPOINT:7:-5}: $LIST"

		for SUBLIST in ${SUBLISTS[@]}; do
			echo "$SUBLIST" @ $IP
			(
				while true; do
					i=0
					for FROM in $SUBLIST; do
						KEY=${KEYS[$FROM]}
						TO=$FROM
						REPEAT=100
						SPLIT=1
						CMD="$ETHEREAL --repeat=$REPEAT tx send --from=$FROM --to=$TO --privatekey=$KEY --amount=${SPLIT} --connection=$ENDPOINT --gasprice=$GAS_PRICE"
						if [ "$i" -lt 2 ]; then
							CMD="$ETHEREAL --repeat=$REPEAT contract deploy --from=$FROM --privatekey=$KEY --data=$CONTRACT_BIN --connection=$ENDPOINT"
						elif  [ "$i" -lt 4 ]; then
							if [ ! -z "$SPAM_DATA_SIGNAL" ]; then
								CMD="$CMD --data=$SPAM_DATA_SIGNAL"
							fi
						else
							CMD="$CMD --data=${SPAM_DATA_SIGNAL}${DATA}"
						fi
						$CMD --quiet && echo "		${FROM:0:6}"
						let i=i+1
					done
				done
			) &
		done
	done

	read  -n 1 -p "Press enter to stop..."
	kill $(jobs -p)
	kill -9 $(jobs -p)
}

# spam FROM N
function spam {
	DATA=`random_hex`
	ENDPOINT=`random_endpoint`

	# j=1
	# while [ $j -lt 300 ]; do
	# 	PAIR=(`new_key_pair`)
	# 	TO=${PAIR[0]}
	# 	KEYS[$TO]=${PAIR[1]}
	# 	let j=j+1
	# done

	FROM=${1:-$PREFUND_ADDR}
	KEY=${KEYS[$FROM]}
	BALANCE=`$ETHEREAL eth balance --wei --address=$FROM --connection=$ENDPOINT`
	SPLIT=${BALANCE:0:-3}
	NONCE=`$ETHEREAL acc nonce --address=$FROM --connection=$ENDPOINT`
	# for TO in "${!KEYS[@]}"; do
	# 	$ETHEREAL tx send --from=$FROM --to=$TO --privatekey=$KEY --amount=$SPLIT --nonce=$NONCE  --connection=$ENDPOINT
	# 	echo "	${FROM:0:6} -> ${TO:0:6}: ${SPLIT}"
	# 	let NONCE=NONCE+1
	# done

	echo ====================== ${#KEYS[@]} ===========================

	(
	j=0
	while true; do
		i=0
		for FROM in "${!KEYS[@]}"; do
			ENDPOINT=`random_endpoint`

			# BALANCE=`$ETHEREAL eth balance --wei --address=$FROM --connection=$ENDPOINT`
			# if [ -z "$BALANCE" ]; then
			# 	echo "Unable to get balance of account: ${FROM:0:6}" >&2
			# 	continue
			# elif [ "$BALANCE" = "0" ]; then
			# 	echo "Zero balance account: ${FROM:0:6}" >&2
			# 	continue
			# fi

			# ROUND=$BALANCE
			# if [ "${#ROUND}" -eq 1 ] && [ "$ROUND" -eq 0 ]; then
			# 	echo "Balance to small ($BALANCE), account: ${FROM:0:6}" >&2
			# 	exit
			# fi
			echo "	${FROM:0:6} <-> ${BALANCE} @ ${ENDPOINT:7:-5}"

			KEY=${KEYS[$FROM]}
			TO=$FROM
			REPEAT=100
			# if [ $j -eq 0 ]; then
			# 	WIGGLE=`shuf -i 0-$REPEAT -n 1`
			# 	((REPEAT=REPEAT+WIGGLE+1000))
			# fi
			SPLIT=0 #${ROUND:0:-2}ether
			CMD="$ETHEREAL --repeat=$REPEAT tx send --from=$FROM --to=$TO --privatekey=$KEY --amount=${SPLIT} --connection=$ENDPOINT --gasprice=9000000000"
			if [ "$i" -lt 10 ]; then
				CMD="$ETHEREAL --repeat=$REPEAT contract deploy --from=$FROM --privatekey=$KEY --data=$CONTRACT_BIN --connection=$ENDPOINT"
			elif  [ "$i" -lt 50 ]; then
				if [ ! -z "$SPAM_DATA_SIGNAL" ]; then
					CMD="$CMD --data=$SPAM_DATA_SIGNAL"
				fi
			else
				CMD="$CMD --data=${SPAM_DATA_SIGNAL}${DATA}"
			fi
			nohup $CMD &>/dev/null &disown
			#--quiet

			let i=i+1
		done
		let j=j+1
	done ) &

	read  -n 1 -p "Press enter to stop..."
	kill $(jobs -p)
	kill -9 $(jobs -p)
}

spam2 "$@"
