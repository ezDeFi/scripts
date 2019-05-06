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
: ${DATA_DIR:=~/.ethereum}
: ${VERBOSITY:=5}
: ${NETWORK_NAME:=simnet}
: ${NETWORK_ID:=50613}
: ${BINARY_POSTFIX:=}
: ${ETHSTATS:=nexty-devnet@198.13.40.85:8080}
: ${CONTRACT_ADDR:=0000000000000000000000000000000000012345}
: ${STAKE_REQUIRE:=100}
: ${STAKE_LOCK_HEIGHT:=150}
: ${TOKEN_OWNER:=000000270840d8ebdffc7d162193cc5ba1ad8707}
: ${PREFUND_ADDR:=000007e01c1507147a0e338db1d029559db6cb19}
	# private: cd4bdb10b75e803d621f64cc22bffdfc5c4b9f8e63e67820cc27811664d43794
	# public:  a83433c26792c93eb56269976cffeb889636ff3f6193b60793fa98c74d9ccdbf4e3a80e2da6b86712e014441828520333828ac4f4605b5d0a8af544f1c5ca67e
	# address: 000007e01c1507147a0e338db1d029559db6cb19
: ${BLOCK_TIME:=1}
: ${EPOCH:=10}
: ${THANGLONG_BLOCK:=10}
: ${THANGLONG_EPOCH:=10}

: ${ENDURIO_BLOCK:=20}
: ${PRICE_SAMPLING_DURATION:=40}
: ${PRICE_SAMPLING_INTERVAL:=3}
: ${ABSORPTION_TIME:=40}

OUTPUT_TYPE=table

# Global Variables
BOOTNODE_STRING=

# COMMAND SHORTCUTS
: ${ETHKEY_CMD:=./build/bin/ethkey$BINARY_POSTFIX}
: ${GETH_CMD:=./build/bin/gonex$BINARY_POSTFIX}
: ${PUPPETH_CMD:=./build/bin/puppeth$BINARY_POSTFIX}
: ${BOOTNODE_CMD:=./build/bin/bootnode$BINARY_POSTFIX}
#GETH_CMD="$GETH_CMD --datadir=$DATA_DIR"
GETH="$GETH_CMD --syncmode=fast --networkid=$NETWORK_ID --rpc --rpcapi=db,eth,net,web3,personal --rpccorsdomain=\"*\" --rpcaddr=0.0.0.0 --gasprice=0 --targetgaslimit=42000000 --txpool.nolocals --txpool.pricelimit=0 --verbosity=$VERBOSITY"

function trim {
	awk '{$1=$1};1'
}

function bootnode {
	if ! stat boot.key > /dev/null 2>&1; then
		# remote boot.key not exist
		$BOOTNODE_CMD --genkey=boot.key
	fi

	nohup yes | $BOOTNODE_CMD -nodekey=boot.key -verbosity=9 &>bootnode.log &

	echo enode://`$BOOTNODE_CMD -nodekey=boot.key -writeaddress`@127.0.0.1:33333
}

function reload {
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

	(	set +x
		echo 2
		echo 1
		echo 4 # Dccs-E
		echo $BLOCK_TIME
		echo $EPOCH
		for AC in "${ACs[@]}"; do
			echo $AC
		done
		echo
		echo $THANGLONG_BLOCK
		echo $THANGLONG_EPOCH
		echo $CONTRACT_ADDR
		echo $STAKE_REQUIRE
		echo $STAKE_LOCK_HEIGHT
		echo $TOKEN_OWNER

		echo $ENDURIO_BLOCK
		echo $PRICE_SAMPLING_DURATION
		echo $PRICE_SAMPLING_INTERVAL
		echo $ABSORPTION_TIME

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
	) >| /tmp/puppeth.input

	GENESIS_JSON=$NETWORK_NAME.json
	rm $NETWORK_NAME-*.json ~/.puppeth/* /tmp/$GENESIS_JSON
	$PUPPETH_CMD --network=$NETWORK_NAME < /tmp/puppeth.input >/dev/null

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
	CMD="$GETH --mine --unlock=0 --password=/tmp/password --ethstats=simnet:$ETHSTATS"
	if [ ! -z "$BOOTNODE_STRING" ]; then
		CMD="$CMD --bootnodes $BOOTNODE_STRING"
	fi
	$CMD
	#nohup $CMD #&>./geth.log
	rm /tmp/password
}

function init_geth {
	$GETH_CMD init $@
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
