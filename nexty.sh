#!/bin/bash
#
# Usage

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
: ${PASSWORD:=}

: ${BINARY_POSTFIX:=}
# KEY_LOCATION=~/.ssh/id_rsa
: ${KEY_LOCATION:=}
if [ ! -z $KEY_LOCATION ]; then
	KEY_LOCATION=-i$KEY_LOCATION
fi
SSH="ssh -oStrictHostKeyChecking=no -oBatchMode=yes $KEY_LOCATION"
SCP="scp -oStrictHostKeyChecking=no -oBatchMode=yes $KEY_LOCATION"

: ${SSH_USER:=ubuntu}
: ${IP_LIST:=`cat endpoints | tr '\r\n' ' '`}
IPS=($IP_LIST)
IPS_IDX=(${!IPS[@]})
IPS_LEN=${#IPS[@]}

# COMMAND SHORTCUTS
: ${GETH_CMD_LOCATION:=../go?e*/build/bin}
: ${GETH_CMD:=geth}
GETH="./$GETH_CMD --syncmode full --cache 2048 --gcmode=archive --rpc --rpcapi db,eth,net,web3,personal --rpccorsdomain \"*\" --rpcaddr 0.0.0.0 --gasprice 0 --targetgaslimit 42000000 --txpool.nolocals --txpool.pricelimit 0"

# stop IP IP ..
function stop {
	test $# -ne 0 && IP_LIST="$@"

	for IP in $IP_LIST
	do
		$SSH $SSH_USER@$IP killall -q --signal SIGINT $GETH_CMD &
	done
	wait
}

# node IP IP ..
function node {
	test $# -ne 0 && IP_LIST="$@"

	for IP in $IP_LIST
	do (
		test -z $NETWORK_ID && BOOTNODE=`$SSH $SSH_USER@$IP "cat ./networkid.info"`
		test -z $BOOTNODE && BOOTNODE=`$SSH $SSH_USER@$IP "cat ./bootnode.info"`

		$SSH $SSH_USER@$IP "nohup $GETH --networkid $NETWORK_ID --bootnodes $BOOTNODE &>>./geth.log &"
	) &
	done
	wait
}

# seal IP IP ..
function seal {
	test $# -ne 0 && IP_LIST="$@"

	for IP in $IP_LIST
	do
		test -z $NETWORK_ID && NETWORK_ID=`$SSH $SSH_USER@$IP "cat ./networkid.info"`
		test -z $BOOTNODE && BOOTNODE=`$SSH $SSH_USER@$IP "cat ./bootnode.info"`
		test -z $ETHSTATS && ETHSTATS=`$SSH $SSH_USER@$IP "cat ./ethstats.info"`

		echo "About to run sealer in $IP with:"
		echo "	NetworkID:	"$NETWORK_ID
		echo "	Bootnode:	"$BOOTNODE
		echo "	Ethstat:	"$ETHSTATS
		read -s -p "	Keystore password: " PASS
		if [ ! -z $PASS ]; then
			PASSWORD=$PASS
		fi

		$SSH $SSH_USER@$IP "nohup $GETH --networkid $NETWORK_ID --bootnodes $BOOTNODE --mine --unlock 0 --password <(echo $PASSWORD) --ethstats $IP:$ETHSTATS &>>./geth.log &"
	done
	wait
}

# deploy IP IP ..
function deploy {
	test $# -ne 0 && IP_LIST="$@"

	for IP in $IP_LIST
	do
		$SCP $GETH_CMD_LOCATION/$GETH_CMD $SSH_USER@$IP:./ &
	done
	wait
}

# clear IP IP ..
function clear {
	test $# -ne 0 && IP_LIST="$@"

	echo "I don't want to live dangerously, please do it yourself by running the following command(s):"

	for IP in $IP_LIST
	do
		echo $SSH $SSH_USER@$IP "rm -rf ~/.ethereum"
	done
	wait
}

# create IP IP ..
function init {
	test $# -ne 0 && IP_LIST="$@"

	for IP in $IP_LIST
	do
		test -z $NETWORK_ID && NETWORK_ID=`$SSH $SSH_USER@$IP "cat ./networkid.info"`
		test -z $NETWORK_ID && echo "Please set the NETWORK_ID env (export NETWORK_ID=66666)" && continue
		test -z $BOOTNODE && BOOTNODE=`$SSH $SSH_USER@$IP "cat ./bootnode.info"`
		test -z $BOOTNODE && echo "Please set the BOOTNODE env (export BOOTNODE=enode://...)" && continue
		test -z $ETHSTATS && ETHSTATS=`$SSH $SSH_USER@$IP "cat ./ethstats.info"`
		test -z $ETHSTATS && echo "Please set the ETHSTATS env (export ETHSTATS=ip:port)" && continue

		ACC_LIST=`$SSH $SSH_USER@$IP "./$GETH_CMD account list" 2>/dev/null`
		if grep --quiet 'Account #' <<< $ACC_LIST; then
			ACC=`grep 'Account #0:' <<< $ACC_LIST`
			ACC=${ACC##*\{}
			ACC=${ACC%%\}*}

			echo "Node $IP is already initialized with:"
			echo "	NetworkID:	"$NETWORK_ID
			echo "	Bootnode:	"$BOOTNODE
			echo "	Ethstat:	"$ETHSTATS
			echo "	Account:	"$ACC

			continue
		fi
		echo "About to create a new account in $IP with:"
		echo "	NetworkID:	"$NETWORK_ID
		echo "	Bootnode:	"$BOOTNODE
		echo "	Ethstat:	"$ETHSTATS
		read -s -p "	Keystore password: " PASS
		if [ ! -z $PASS ]; then
			PASSWORD=$PASS
		fi

		ACC=`$SSH $SSH_USER@$IP "./$GETH_CMD account new --password <(echo $PASSWORD)"`
		ACC=${ACC##*\{}
		ACC=${ACC%%\}*}
		echo "	Account:	"$ACC

		$SSH $SSH_USER@$IP "printf \"$NETWORK_ID\" >| networkid.info; printf \"$BOOTNODE\" >| bootnode.info; printf \"$ETHSTATS\" > ethstats.info;"
	done
	wait
}

"$@"
