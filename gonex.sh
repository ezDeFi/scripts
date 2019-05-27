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

# CONSTANTS
ENODEs="enode://53af4fd44f7c9f8e7bbff4e4b8fc82c45d153e2762d5a3780bb6dd51ab476841d28262de498c747e717f53192166bc8276e3ad8fcf728104ccd4b81edd159740@13.228.68.50:30303
enode://eb74bcb909db025d60dd06151e608867bc5ffda454a4e13568867d2635ac481a49aea7f1b1a0845b71b2363d385394291e983489e6c52fcba5ee603cb0178555@35.197.153.143:30303
enode://5eec3d1256b3989e3bba0bb35690148fc1378d3d3fe27838ca6de04d9a880304af312c612bd25c89dd0cc8cfcdf5f8186c0f5a69f5cfe3a068330166661b431a@35.186.147.119:30303
enode://374fd3c0eec3e279122ad87bbc4bb729c055a42e7ce7b3988b55101a9b419aef5ba55d0727ec336fac3e64cd3ae5cb49d44404c463981db6b5bde6de12265aad@35.198.202.233:30303
enode://399a27c102949a776e0e0ec12f559fca18e2b4044af3f8180a0f1fb5bcaa293b894d020f5742175422341a0f38c53e12adec286fe654db10ce11ade97cd06943@35.197.133.117:30303"

# CONFIG
: ${PASSFILE:=./35c246d5}
: ${ETHSTATS:=nty2018@stats.nexty.io}
: ${BINARY_POSTFIX:=}
# KEY_LOCATION=~/.ssh/devop
: ${KEY_LOCATION:=~/.ssh/id_rsa}
if [ ! -z $KEY_LOCATION ]; then
	KEY_LOCATION=-i$KEY_LOCATION
fi
SSH="ssh -oStrictHostKeyChecking=no -oBatchMode=yes $KEY_LOCATION"
SCP="scp -oStrictHostKeyChecking=no -oBatchMode=yes $KEY_LOCATION -C"

: ${SSH_USER:=ubuntu}

# COMMAND SHORTCUTS
: ${GETH_CMD_LOCATION:=../gonex/build/bin}
: ${GETH_CMD:=gonex}
: ${GETH_CMD_BIN:=$GETH_CMD_LOCATION/$GETH_CMD}
GETH="./$GETH_CMD --syncmode=fast --gasprice=0 --targetgaslimit=42000000 --txpool.pricelimit=0 --networkid=66666 --ws --wsaddr=0.0.0.0 --wsport=8546 --wsapi=eth,net,web3,debug --wsorigins=''"

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

# deploy $ID
function deploy {
	ID=$1
	IP=${IPs[$ID]}
	$SCP $GETH_CMD_BIN $SSH_USER@$IP:./$GETH_CMD
}

# account ID
function account {
	ID=$1
	IP=${IPs[$ID]}
	ACC=`$SSH $SSH_USER@$IP "./$GETH_CMD account list" 2>/dev/null | grep 'Account #0:'`
	if [ -z "$ACC" ]; then
		return
	fi
	ACC=${ACC##*\{}
	ACC=${ACC%%\}*}
	echo $ACC
}

# create ID
function create {
	ID=$1
	IP=${IPs[$ID]}

	ACC=`account $IP`
	if [ ! -z "$ACC" ]; then
		echo "Node $IP already has an account:"
		echo "	Account:	"$ACC
		return
	fi
	echo "About to create a new account in $IP with:"
	PASSWORD=password
	read -s -p "	Keystore password: " PASS
	if [ ! -z $PASS ]; then
		PASSWORD=$PASS
	fi
	echo
	$SSH $SSH_USER@$IP "echo \"$PASSWORD\" >| $PASSFILE"
	unset PASSWORD

	ACC=`$SSH $SSH_USER@$IP "./$GETH_CMD account new --password=$PASSFILE"`
	ACC=${ACC##*\{}
	ACC=${ACC%%\}*}
	echo "	Account:	"$ACC
}

function init {
	ID=$1
	IP=${IPs[$ID]}
	NAME=${NAMEs[$ID]}

	create $ID

	# gonex.service
	echo "
[Unit]
Description=Nexty go client

[Service]
Type=simple
Restart=always
WorkingDirectory=%h
ExecStart=/bin/bash -x ./$GETH_CMD.sh

[Install]
WantedBy=default.target" >| /tmp/$GETH_CMD.service
	$SCP /tmp/$GETH_CMD.service $SSH_USER@$IP:/tmp/ &

	# gonex.sh
	echo "$GETH --mine --unlock=0 --password=$PASSFILE --ethstats=$NAME:$ETHSTATS &>./geth.log" >| /tmp/$GETH_CMD.sh
	chmod +x /tmp/$GETH_CMD.sh
	$SCP /tmp/$GETH_CMD.sh $SSH_USER@$IP:./$GETH_CMD.sh &

	wait
	$SSH $SSH_USER@$IP "systemctl --user enable /tmp/$GETH_CMD.service"
	$SSH $SSH_USER@$IP "loginctl enable-linger $SSH_USER"
}

function start {
	ID=$1
	IP=${IPs[$ID]}
	$SSH $SSH_USER@$IP "systemctl --user start $GETH_CMD"
}

function stop {
	ID=$1
	IP=${IPs[$ID]}
	$SSH $SSH_USER@$IP "systemctl --user stop $GETH_CMD"
}

function default_peers {
	ID=$1
	IP=${IPs[$ID]}

	for ENODE in $ENODEs; do
		$SSH $SSH_USER@$IP "./$GETH_CMD --exec=\"admin.addPeer('$ENODE')\" attach" &
	done
	wait
}

function reset_node_data {
	ID=$1
	IP=${IPs[$ID]}
	$SSH $SSH_USER@$IP "rm -rf ./.nexty"
}

load
"$@"
save
