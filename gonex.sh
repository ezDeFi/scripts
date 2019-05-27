#!/bin/bash
#
# Usage
#
# Set the environment variables:
# export KEY_LOCATION=~/.ssh/devop
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
: ${NETWORK_ID:=}
: ${BOOTNODE:=}
: ${ETHSTATS:=}
: ${PASSWORD:=password}
: ${IPS:=3.104.110.113 18.130.42.24 3.14.70.219}
: ${NAMES:=abc def xyz}
: ${NET_IF:=ens5}

: ${BINARY_POSTFIX:=}
# KEY_LOCATION=~/.ssh/devop
: ${KEY_LOCATION:=~/.ssh/devop}
if [ ! -z $KEY_LOCATION ]; then
	KEY_LOCATION=-i$KEY_LOCATION
fi
SSH="ssh -oStrictHostKeyChecking=no -oBatchMode=yes $KEY_LOCATION"
SCP="scp -oStrictHostKeyChecking=no -oBatchMode=yes $KEY_LOCATION -C"

: ${SSH_USER:=ubuntu}

# COMMAND SHORTCUTS
: ${GETH_CMD_LOCATION:=../gonex/build/bin}
: ${GETH_CMD:=gonex}
: ${GETH_CMD_BIN:=$GETH_CMD}
GETH="./$GETH_CMD --syncmode=fast --rpc --rpcapi=db,eth,net,web3,personal --rpccorsdomain=\"*\" --rpcaddr=0.0.0.0 --gasprice=0 --targetgaslimit=42000000 --txpool.nolocals --txpool.pricelimit=0 --verbosity=5"

# CONFIGS
declare -A IPs
declare -A NAMEs

function save {
	(
		echo "IPs=("
		for ID in "${!IPs[@]}"; do
			echo "	[$ID]=${IPs[$ID]}"
		done
		echo ")"

		echo "NAMEs=("
		for ID in "${!NAMEs[@]}"; do
			echo "	[$ID]=${NAMEs[$ID]}"
		done
		echo ")"
	) >| ./gonex.config
}

function load {
	source ./gonex.config
}

function sample {
	# TEST SAMPLES
	IPs=(
		[0]=1.22.31.41
		[1]=5.4.6.7
		[2]=12.54.98.4
	)
	NAMEs=(
		[0]=a
		[1]=b
		[2]=c
	)
}

function list {
	echo "ID	NAME	IP"
	for ID in ${!IPs[@]}; do
		IP=${IPs[$ID]}
		NAME=${NAMEs[$ID]}
		echo "$ID	$NAME	$IP"
	done
}

function add {
	NAMEs[$1]+="$2"
	IPs[$1]+="$3"
}

function rem {
	unset NAMEs[$1]
	unset IPs[$1]
}

function clear {
	IPs=()
	NAMEs=()
}

load
"$@"
save
