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

"$@"
