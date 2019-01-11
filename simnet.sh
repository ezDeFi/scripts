#!/bin/bash
#
# Usage
# + Terminate bootnode:
# 		aws.sh terminate bn
# + Terminate all instances except bootnode
# 		aws.sh terminate all
# + Load N instances for each configured regions
# 		aws.sh load N
#
# Config
# 	export NETWORK_NAME=testnet
# 	export NETWORK_ID=50913
# 	export BINARY_POSTFIX=-linux-amd64
# 	export KEY_NAME=DevOp
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
: ${ETHSTATS:=nexty-testnet@198.13.40.85:80}
: ${CONTRACT_ADDR:=cafecafecafecafecafecafecafecafecafecafe}
: ${PREFUND_ADDR:=000007e01c1507147a0e338db1d029559db6cb19}
	# private: cd4bdb10b75e803d621f64cc22bffdfc5c4b9f8e63e67820cc27811664d43794
	# public:  a83433c26792c93eb56269976cffeb889636ff3f6193b60793fa98c74d9ccdbf4e3a80e2da6b86712e014441828520333828ac4f4605b5d0a8af544f1c5ca67e
	# address: 000007e01c1507147a0e338db1d029559db6cb19
: ${BLOCK_TIME:=2}
: ${EPOCH:=90}
: ${DATA_DIR:=~/.ethereum}

OUTPUT_TYPE=table

# Global Variables
BOOTNODE_STRING=

# COMMAND SHORTCUTS
: ${GETH_CMD:=./build/bin/geth$BINARY_POSTFIX}
: ${PUPPETH_CMD:=./build/bin/puppeth$BINARY_POSTFIX}
: ${BOOTNODE_CMD:=./build/bin/bootnode$BINARY_POSTFIX}
ETHKEY_CMD=`which ethkey`
GETH_CMD=`which geth`
PUPPETH_CMD=`which puppeth`
BOOTNODE_CMD=`which bootnode`
GETH_CMD="$GETH_CMD --datadir=$DATA_DIR"
GETH="$GETH_CMD --syncmode=full --cache 2048 --gcmode=archive --networkid $NETWORK_ID --rpc --rpcapi db,eth,net,web3,personal --rpccorsdomain \"*\" --rpcaddr 0.0.0.0 --gasprice 0 --targetgaslimit 42000000 --txpool.nolocals --txpool.pricelimit 0"

function trim {
	awk '{$1=$1};1'
}

function bootnode {
	if ! stat boot.key > /dev/null 2>&1; then
		# remote boot.key not exist
		$BOOTNODE_CMD --genkey=boot.key
	fi

	nohup yes | $BOOTNODE_CMD -nodekey=boot.key -verbosity 9 &>bootnode.log &

	echo enode://`$BOOTNODE_CMD -nodekey=boot.key -writeaddress`@127.0.0.1:33333
}

function load {
	COUNT=${1:-1}
	#BOOTNODE_STRING=`bootnode`

	rm -rf "$DATA_DIR"
	deploy $ALL_IPs | tr "\n" " " | awk '{$1=$1};1'
}

function create_account {
	echo password >| /tmp/password
	ACCOUNT=`$GETH_CMD account new --password /tmp/password`
	rm /tmp/password
	echo "${ACCOUNT:10:40}"
}

# load pre-fund account from keystore folder
function load_pre_fund_accounts {
	arr=()
	for file in ./.gonex/keystore/UTC--*; do
		if [[ -f $file ]]; then
			filename=$(basename -- "$file")
			arr=(${arr[@]} ${filename:37:78})
		fi
	done
	echo "${arr[@]}"
}

function test_load_pre_fund_accounts {
	echo `load_pre_fund_accounts`
}

# generate the genesis json file
function generate_genesis {
	ACs=($@)
	#PFACs=(`load_pre_fund_accounts`)

	(	echo 2
		echo 1
		echo 3
		echo $BLOCK_TIME
		echo $EPOCH
		for AC in "${ACs[@]}"; do
			echo $AC
		done
		echo
		echo 0
		echo $CONTRACT_ADDR
		echo $PREFUND_ADDR
		#for PFAC in "${PFACs[@]}"; do
		#	echo $PFAC
		#done
		echo
		echo no
		echo $NETWORK_ID
		echo 2
		echo 2
		echo
	) >| /tmp/puppeth.json

	GENESIS_JSON=$NETWORK_NAME.json
	rm $NETWORK_NAME-*.json ~/.puppeth/* /tmp/$GENESIS_JSON
	$PUPPETH_CMD --network=$NETWORK_NAME < /tmp/puppeth.json >/dev/null

	if [ ! -f "$GENESIS_JSON" ]; then
		>&2 echo "Unable to create genesis file with Puppeth"
		exit -1
	fi

	echo $GENESIS_JSON
}

function init_genesis {
	ACs=($@)

	GENESIS_JSON=`generate_genesis ${ACs[@]}`

	echo $GENESIS_JSON
}

function start {
	echo password >| /tmp/password
	CMD="$GETH --mine --unlock=0 --password=/tmp/password --ethstats=$IP:$ETHSTATS"
	if [ ! -z "$BOOTNODE_STRING" ]; then
		CMD="$CMD --bootnodes $BOOTNODE_STRING"
	fi
	$CMD
	#nohup $CMD #&>./geth.log
	rm /tmp/password
}

function init_geth {
	$GETH_CMD init $@
	start
}

function deploy {
	IPs=($@)
	ACs=(`create_account ${IPs[@]}`)
	
	GENESIS_JSON=`init_genesis ${ACs[@]}`

	init_geth $GENESIS_JSON
	start
}

function stop {
	killall -q --signal SIGINT $GETH_CMD &
}

"$@"
