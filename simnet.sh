#!/bin/bash

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
: ${CLIENT:=gonex}
: ${DATA_DIR:=/tmp/$CLIENT}
: ${VERBOSITY:=5}
: ${NETWORK_NAME:=simnet}
: ${NETWORK_ID:=111111}
: ${BINARY_POSTFIX:=}
#ETHSTATS=nexty-devnet@localhost:8080
#ETHSTATS=nty2018@stats.nexty.io:80
: ${ETHSTATS:=nexty-devnet@stats.testnet.nexty.io:8080}
: ${CONTRACT_ADDR:=0000000000000000000000000000000000012345}
: ${STAKE_REQUIRE:=100}
: ${STAKE_LOCK_HEIGHT:=150}
: ${TOKEN_OWNER:=000000270840d8ebdffc7d162193cc5ba1ad8707}
: ${PREFUND_ADDR:=000007e01c1507147a0e338db1d029559db6cb19}
	# private: cd4bdb10b75e803d621f64cc22bffdfc5c4b9f8e63e67820cc27811664d43794
	# public:  a83433c26792c93eb56269976cffeb889636ff3f6193b60793fa98c74d9ccdbf4e3a80e2da6b86712e014441828520333828ac4f4605b5d0a8af544f1c5ca67e
	# address: 000007e01c1507147a0e338db1d029559db6cb19
PREFUND_ADDR=95e2fcBa1EB33dc4b8c6DCBfCC6352f0a253285d
	# private: a0cf475a29e527dcb1c35f66f1d78852b14d5f5109f75fa4b38fbe46db2022a5
: ${BLOCK_TIME:=1}
: ${EPOCH:=10}
: ${THANGLONG_BLOCK:=10}
: ${THANGLONG_EPOCH:=10}

: ${ENDURIO_BLOCK:=20}
: ${PRICE_SAMPLING_DURATION:=50}
: ${PRICE_SAMPLING_INTERVAL:=3}
: ${ABSORPTION_DURATION:=13}
: ${ABSORPTION_EXPIRATION:=26}
: ${SLASHING_DURATION:=13}
: ${LOCKDOWN_EXPIRATION:=39}

OUTPUT_TYPE=table

# Global Variables
BOOTNODE_STRING=

# COMMAND SHORTCUTS
: ${ETHKEY_CMD:=./build/bin/ethkey$BINARY_POSTFIX}
: ${GETH_CMD:=./build/bin/${CLIENT}$BINARY_POSTFIX}
: ${PUPPETH_CMD:=./build/bin/puppeth$BINARY_POSTFIX}
: ${BOOTNODE_CMD:=./build/bin/bootnode$BINARY_POSTFIX}
#GETH_CMD="$GETH_CMD --datadir=$DATA_DIR"
GETH="$GETH_CMD --syncmode=fast --networkid=$NETWORK_ID --rpc --rpcapi=db,eth,net,web3,personal --rpccorsdomain=\"*\" --rpcaddr=0.0.0.0 --gasprice=0 --targetgaslimit=42000000 --txpool.nolocals --txpool.pricelimit=0 --verbosity=$VERBOSITY"
#GETH="$GETH --txpool.spammyage=0"

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
	IDs=($@)
	#BOOTNODE_STRING=`bootnode`

	rm -rf "$DATA_DIR"
	stop ${IDs[@]}
	load ${IDs[@]} # | tr "\n" " " | awk '{$1=$1};1'
}

function create_account {
	IDs=($@)
	for ID in "${IDs[@]}"; do
		ACCOUNT=`$GETH_CMD account new --password=<(echo password) --datadir=$DATA_DIR/$ID`
		ACCOUNT=`echo "${ACCOUNT##*0x}" | head -n1`
		ACCOUNT="${ACCOUNT#*\{}"
		ACCOUNT="${ACCOUNT%\}*}"
		echo $ACCOUNT
	done
}

# load pre-fund account from keystore folder
function load_pre_fund_accounts {
	arr=()
	for file in ./.$CLIENT/keystore/UTC--*; do
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
		echo 3
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
		echo $ABSORPTION_DURATION
		echo $ABSORPTION_EXPIRATION
		echo $SLASHING_DURATION
		echo $LOCKDOWN_EXPIRATION

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
	rm -f $NETWORK_NAME-*.json ~/.puppeth/* /tmp/$GENESIS_JSON
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
	IDs=($@)
	CMD_BASE="$GETH --mine --unlock=0 --password=<(echo password)"
	# add --allow-insecure-unlock for geth 1.9+
	$GETH --help | grep "allow-insecure-unlock" && CMD_BASE="$CMD_BASE --allow-insecure-unlock"
	if [ ! -z "$BOOTNODE_STRING" ]; then
		CMD_BASE="$CMD_BASE --bootnodes $BOOTNODE_STRING"
	else
		CMD_BASE="$CMD_BASE --nodiscover"
	fi
	for ID in "${IDs[@]}"; do
		CMD="$CMD_BASE --datadir=$DATA_DIR/$ID"
		CMD="$CMD --ethstats=$ID:$ETHSTATS"
		CMD="$CMD --port=$((30303 + ID))"
		CMD="$CMD --rpcport=$((8545 + ID))"

		# mesh peering
		if [ -z "$BOOTNODE_STRING" ]; then
		(	sleep $((5+2*LAST_ID))s
			for D in `find $DATA_DIR -mindepth 1 -maxdepth 1 -type d`
			do
				I=`basename $D`
				test "$ID" = "$I" && continue
				ENODE=`$BOOTNODE_CMD -nodekey=$DATA_DIR/$I/$CLIENT/nodekey -writeaddress`
				ENODE=enode://$ENODE@127.0.0.1:$((30303 + I))
				$GETH_CMD --datadir=$DATA_DIR/$ID --exec="admin.addPeer('$ENODE')" attach
			done
			)&

		bash -ic "nohup $CMD &>$DATA_DIR/$ID/$CLIENT.log &"
		continue;

		### UNUSED ###

		# single node
		if [ ${#IDs[@]} -eq 1 ]; then
			bash -ic "$CMD"
			break;
		fi

		# multiple nodes
		gnome-terminal --title="node $ID" -- bash -ic "$CMD || read line"
	fi
	done
	#nohup $CMD --password=<(echo password) &>$DATA_DIR/$ID.log
}

function init_geth {
	$GETH_CMD init $2 --datadir=$DATA_DIR/$1
}

function load {
	IDs=($@)
	ACs=(`create_account ${IDs[@]}`)
	
	GENESIS_JSON=`init_genesis ${ACs[@]}`

	for ID in "${IDs[@]}"; do
		init_geth $ID $GENESIS_JSON &
	done
	wait

	start "${IDs[@]}"
}

function stop {
	IDs=($@)
	for ID in "${IDs[@]}"; do
		PID=`ps all | grep -v 'grep' | grep /tmp/$CLIENT/$ID | awk '{print $3}'`
		test ! -z "$PID" && kill $PID
	done
}

function restart {
	stop "$@"
	start "$@"
}

function killall {
	killall -q --signal SIGINT $(basename -- "$GETH_CMD") &
}

"$@"
