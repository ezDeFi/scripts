#!/bin/bash
#
# Usage
#
# Set the environment variables:
# export KEY_LOCATION=~/.ssh/devop
#
# Deploy or upgrade geth binary to new servers
# 	geth.sh deploy IP IP ...
#
# Init the new sealer nodes.
# 	geth.sh init IP IP ...
#
# Create new account for new nodes, account password will be promted.
# 	geth.sh create IP IP ...
#
# Clear the node accounts.
# 	geth.sh clear IP IP ...
#
# Import private key to nodes. Account password and private key will be prompted.
# 	geth.sh import IP IP ...
#
# Stop the node.
# 	geth.sh stop IP IP ...
#
# Start the node (no sealing nor ethstat).
# 	geth.sh node IP IP ...
#
# Start the sealer (and report to ethstat). Account password will be prompted.
# 	geth.sh seal IP IP ...
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
: ${PASSWORD:=}
: ${IP_LIST:=}
: ${NET_IF:=}

: ${BINARY_POSTFIX:=}
# KEY_LOCATION=~/.ssh/id_rsa
: ${KEY_LOCATION:=}
if [ ! -z $KEY_LOCATION ]; then
	KEY_LOCATION=-i$KEY_LOCATION
fi
SSH="ssh -oStrictHostKeyChecking=no -oBatchMode=yes $KEY_LOCATION"
SCP="scp -oStrictHostKeyChecking=no -oBatchMode=yes $KEY_LOCATION"

: ${SSH_USER:=ubuntu}

# COMMAND SHORTCUTS
: ${GETH_CMD_LOCATION:=../go?e*/build/bin}
: ${GETH_CMD:=geth}
GETH="./$GETH_CMD --syncmode=full --cache=2048 --gcmode=archive --rpc --rpcapi=db,eth,net,web3,personal --rpccorsdomain=\"*\" --rpcaddr=0.0.0.0 --gasprice=0 --targetgaslimit=42000000 --txpool.nolocals --txpool.pricelimit=0 --verbosity=5 --maxpeers=4"

function stop {
	if [ -z "$IP_LIST" ]; then
		echo "Please set IP_LIST env"
		return
	fi

	for IP in $IP_LIST
	do (
		$SSH $SSH_USER@$IP killall -q --signal SIGINT $GETH_CMD &
	) &
	done
	wait
}

function node {
	if [ -z "$IP_LIST" ]; then
		echo "Please set IP_LIST env"
		return
	fi

	for IP in $IP_LIST
	do (
		test -z $NETWORK_ID && NETWORK_ID=`$SSH $SSH_USER@$IP "cat ./networkid.info"`
		test -z $BOOTNODE && BOOTNODE=`$SSH $SSH_USER@$IP "cat ./bootnode.info"`

		$SSH $SSH_USER@$IP "nohup $GETH --networkid $NETWORK_ID --bootnodes $BOOTNODE &>>./geth.log &"
	) &
	done
	wait
}

function seal {
	if [ -z "$IP_LIST" ]; then
		echo "Please set IP_LIST env"
		return
	fi

	for IP in $IP_LIST
	do
		ACC=`get_acc $IP`
		if [ -z "$ACC" ]; then
			echo "Node $IP doesn't have an account to seal"
			return
		fi
		test -z $NETWORK_ID && NETWORK_ID=`$SSH $SSH_USER@$IP "cat ./networkid.info"`
		test -z $BOOTNODE && BOOTNODE=`$SSH $SSH_USER@$IP "cat ./bootnode.info"`
		test -z $ETHSTATS && ETHSTATS=`$SSH $SSH_USER@$IP "cat ./ethstats.info"`
	done

	test -z $NETWORK_ID && echo "Please set the NETWORK_ID env (export NETWORK_ID=66666)" && return
	test -z $BOOTNODE && echo "Please set the BOOTNODE env (export BOOTNODE=enode://...)" && return
	test -z $ETHSTATS && echo "Please set the ETHSTATS env (export ETHSTATS=ip:port)" && return

	for IP in $IP_LIST
	do
		echo "About to run sealer in $IP with:"
		echo "	NetworkID:	$NETWORK_ID"
		echo "	Bootnode:	...${BOOTNODE: -40}"
		echo "	Ethstat:	$ETHSTATS"
		if [ -z $PASSWORD ]; then
			read -s -p "	Keystore password: " PASS
			if [ ! -z $PASS ]; then
				PASSWORD=$PASS
			fi
		fi

		$SSH $SSH_USER@$IP "nohup $GETH --networkid $NETWORK_ID --bootnodes $BOOTNODE --mine --unlock 0 --password <(echo $PASSWORD) --ethstats $IP:$ETHSTATS &>>./geth.log &"
	done
	wait
}

function deploy {
	if [ -z "$IP_LIST" ]; then
		echo "Please set IP_LIST env"
		return
	fi

	for IP in $IP_LIST
	do
		$SCP $GETH_CMD_LOCATION/$GETH_CMD $SSH_USER@$IP:./ &
	done
	wait
}

function clear {
	if [ -z "$IP_LIST" ]; then
		echo "Please set IP_LIST env"
		return
	fi

	echo "I don't want to live dangerously, please do it yourself by running the following command(s):"

	for IP in $IP_LIST
	do
		echo $SSH $SSH_USER@$IP "rm -rf ./.ethereum"
	done
	wait
}

# get_acc IP
function get_acc {
	IP=$1
	ACC=`$SSH $SSH_USER@$IP "./$GETH_CMD account list" 2>/dev/null | grep 'Account #0:'`
	if [ -z "$ACC" ]; then
		return
	fi
	ACC=${ACC##*\{}
	ACC=${ACC%%\}*}
	echo $ACC
}

# create
function create {
	if [ -z "$IP_LIST" ]; then
		echo "Please set IP_LIST env"
		return
	fi

	for IP in $IP_LIST
	do
		ACC=`get_acc $IP`
		if [ ! -z "$ACC" ]; then
			echo "Node $IP already has an account:"
			echo "	Account:	"$ACC
			continue
		fi
		echo "About to create a new account in $IP with:"
		if [ -z $PASSWORD ]; then
			read -s -p "	Keystore password: " PASS
			if [ ! -z $PASS ]; then
				PASSWORD=$PASS
			fi
		fi

		ACC=`$SSH $SSH_USER@$IP "./$GETH_CMD account new --password <(echo $PASSWORD)"`
		ACC=${ACC##*\{}
		ACC=${ACC%%\}*}
		echo "	Account:	"$ACC
	done
	wait
}

# import
function import {
	if [ -z "$IP_LIST" ]; then
		echo "Please set IP_LIST env"
		return
	fi

	for IP in $IP_LIST
	do
		ACC=`get_acc $IP`
		if [ ! -z "$ACC" ]; then
			echo "Node $IP already has an account:"
			echo "	Account:	"$ACC
			continue
		fi
		echo "About to import a new private key into $IP with:"
		if [ -z $PASSWORD ]; then
			read -s -p "	Keystore password: " PASS
			if [ ! -z $PASS ]; then
				PASSWORD=$PASS
			fi
			echo
		fi

		read -s -p "	New Private Key: " SKEY
		if [ ! -z $SKEY ]; then
			PRVKEY=$SKEY
		fi

		ACC=`$SSH $SSH_USER@$IP "./$GETH_CMD account import --password <(echo $PASSWORD) <(echo $PRVKEY)"`
		ACC=${ACC##*\{}
		ACC=${ACC%%\}*}
		echo "	Account:	"$ACC
	done
	wait
}

# export
function export {
	if [ -z "$IP_LIST" ]; then
		echo "Please set IP_LIST env"
		return
	fi

	ETHEREAL=`command -v ethereal`
	if [ -z $ETHEREAL ]; then
		echo "etheral not installed"
		return
	fi

	for IP in $IP_LIST
	do
		ACC=`get_acc $IP`
		if [ -z "$ACC" ]; then
			echo "Node $IP doesn't have an account to export"
			return
		fi

		if ! $SSH $SSH_USER@$IP stat ethereal \> /dev/null 2\>\&1; then
			$SCP "$ETHEREAL" $SSH_USER@$IP:./
		fi

		echo "About to export a keys from $IP:"
		if [ -z $PASSWORD ]; then
			read -s -p "	Keystore password: " PASS
			if [ ! -z $PASS ]; then
				PASSWORD=$PASS
			fi
			echo
		fi

		$SSH $SSH_USER@$IP "./ethereal account keys --passphrase=$PASSWORD --address=$ACC"
	done
	wait
}

# init
function init {
	if [ -z "$IP_LIST" ]; then
		echo "Please set IP_LIST env"
		return
	fi

	for IP in $IP_LIST
	do
		test -z $NETWORK_ID && NETWORK_ID=`$SSH $SSH_USER@$IP "cat ./networkid.info"`
		test -z $NETWORK_ID && echo "Please set the NETWORK_ID env (export NETWORK_ID=66666)" && continue
		test -z $BOOTNODE && BOOTNODE=`$SSH $SSH_USER@$IP "cat ./bootnode.info"`
		test -z $BOOTNODE && echo "Please set the BOOTNODE env (export BOOTNODE=enode://...)" && continue
		test -z $ETHSTATS && ETHSTATS=`$SSH $SSH_USER@$IP "cat ./ethstats.info"`
		test -z $ETHSTATS && echo "Please set the ETHSTATS env (export ETHSTATS=ip:port)" && continue

		ACC=`get_acc $IP`
		if [ -z "$ACC" ]; then
			echo "About to create a new account in $IP with:"
			echo "	NetworkID:	$NETWORK_ID"
			echo "	Bootnode:	...${BOOTNODE: -40}"
			echo "	Ethstat:	$ETHSTATS"
			if [ -z $PASSWORD ]; then
				read -s -p "	Keystore password: " PASS
				if [ ! -z $PASS ]; then
					PASSWORD=$PASS
				fi
			fi

			ACC=`$SSH $SSH_USER@$IP "./$GETH_CMD account new --password <(echo $PASSWORD)"`
			ACC=${ACC##*\{}
			ACC=${ACC%%\}*}
			echo "	Account:	"$ACC
		else
			echo "About to init node $IP with:"
			echo "	NetworkID:	$NETWORK_ID"
			echo "	Bootnode:	...${BOOTNODE: -40}"
			echo "	Ethstat:	$ETHSTATS"
			echo "	Account:	$ACC"
		fi

		$SSH $SSH_USER@$IP "./$GETH_CMD init *.json"

		$SSH $SSH_USER@$IP "printf \"$NETWORK_ID\" >| networkid.info; printf \"$BOOTNODE\" >| bootnode.info; printf \"$ETHSTATS\" > ethstats.info;"
	done
	wait
}

# default_interface IP
function default_interface {
	IP=$1
	$SSH $SSH_USER@$IP "route | grep ^default | awk '{print \$NF}'"
}

# network delay LATENCY
# network loss LOSS
# network clear
# network random LATENCY_CAP(ms) LOSS_CAP(%%)
function network {
	if [ -z "$IP_LIST" ]; then
		echo "Please set IP_LIST env"
		return
	fi

	for IP in $IP_LIST
	do (
		if [ -z $NET_IF ]; then
			NET_IF=`default_interface $IP`
		fi

		if [ "$1" = clear ]; then
			echo "$IP	$NET_IF"
			$SSH $SSH_USER@$IP "sudo tc qdisc del dev $NET_IF root netem"
		elif [ "$1" = random ]; then
			LATENCY_CAP=${2:-500}
			LOSS_CAP=${3:-20}
			LATENCY=$((RANDOM%LATENCY_CAP+1))ms
			LOSS=`printf "%02d" $((RANDOM%LOSS_CAP+1)) | sed 's/.$/.&/'`
			echo "$IP	$NET_IF	$LATENCY	$LOSS%"
			$SSH $SSH_USER@$IP "sudo tc qdisc \`grep -q netem <(tc qdisc) && echo change || echo add\` dev $NET_IF root netem delay $LATENCY loss $LOSS"
		else
			echo "$IP	$NET_IF"
			$SSH $SSH_USER@$IP "sudo tc qdisc \`grep -q netem <(tc qdisc) && echo change || echo add\` dev $NET_IF root netem $*"
		fi
	) &
	done
	wait
}

function re_seal {
	if [ -z "$IP_LIST" ]; then
		echo "Please set IP_LIST env"
		return
	fi

	stop
	sleep 3s
	seal
}

function re_deploy {
	if [ -z "$IP_LIST" ]; then
		echo "Please set IP_LIST env"
		return
	fi

	stop
	sleep 3s
	deploy
	seal
}

"$@"
