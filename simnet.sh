#!/bin/bash

# A POSIX variable
OPTIND=1         # Reset in case getopts has been used previously in the shell.
ROLLBACK=
MS=
UL=

# Initialize our own variables:

while getopts "h?r:m:u:t" opt; do
    case "$opt" in
    h|\?)
        echo "$(basename ""$0"") [-h|-?|-m MS|-u UL] command"
        exit 0
        ;;
	r)
		ROLLBACK=$OPTARG
		;;
	m)
		MS=$OPTARG
		;;
	u)
		UL=$OPTARG
		;;
	t)
		NET=--testnet
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
# ETHSTATS=nexty-devnet@localhost:8080
#ETHSTATS=nty2018@stats.nexty.io
: ${ETHSTATS:=nexty-devnet@stats.testnet.nexty.io:8080}
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
: ${EPOCH:=20}
: ${THANGLONG_BLOCK:=20}
: ${THANGLONG_EPOCH:=10}

: ${ENDURIO_BLOCK:=23}
: ${LEAK_DURATION:=64}
: ${APP_CONFIRMS:=8}
: ${RANDOM_ITERATION:=3000000}

: ${PRICE_SAMPLING_INTERVAL:=3}
: ${STABLECOIN_RATE:=6000}
# : ${PRICE_SAMPLING_DURATION:=50}
# : ${ABSORPTION_DURATION:=13}
# : ${ABSORPTION_EXPIRATION:=26}
# : ${SLASHING_DURATION:=13}
# : ${LOCKDOWN_EXPIRATION:=39}

: ${MELINH_BLOCK:=27}

OUTPUT_TYPE=table

# Global Variables
BOOTNODE_STRING=

# COMMAND SHORTCUTS
# bin path can be either gonex or go-ethereum
: ${BIN_PATH:=`ls -d ../go{nex,-ethereum}/build/bin 2>/dev/null | head -n1`}
: ${ETHKEY_CMD:=$BIN_PATH/ethkey$BINARY_POSTFIX}
: ${GETH_CMD:=$BIN_PATH/${CLIENT}$BINARY_POSTFIX}
: ${PUPPETH_CMD:=$BIN_PATH/puppeth$BINARY_POSTFIX}
: ${BOOTNODE_CMD:=$BIN_PATH/bootnode$BINARY_POSTFIX}
#GETH_CMD="$GETH_CMD --datadir=$DATA_DIR"
GETH="$GETH_CMD $NET"
GETH="$GETH --networkid=$NETWORK_ID  --gasprice=0 --targetgaslimit=42000000 --txpool.nolocals --txpool.pricelimit=0 --verbosity=$VERBOSITY --miner.recommit=500ms"
GETH="$GETH --rpc --rpcapi=db,eth,net,web3,personal --rpccorsdomain=\"*\" --rpcaddr=0.0.0.0"
# GETH="$GETH --ws --wsapi=db,eth,net,web3,personal --wsorigins=\"*\" --wsaddr=0.0.0.0"
GETH="$GETH --syncmode=fast"
# GETH="$GETH --gcmode=archive"
GETH="$GETH --vdf.gen=vdf-cli"
# GETH="$GETH --price.url=http://localhost:3000/price/NUSD_USD"
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

function import_account {
	IDs=($@)
	: ${KP_FILE:=../scripts/keypairs}
	: ${MS:=1}
		for ((i=0; i<MS; i++)); do
		for ID in "${IDs[@]}"; do
			K=$((i+ID+1))
			KEY_PAIR=`head -n$K $KP_FILE | tail -n1`
			PRV_KEY=${KEY_PAIR#*=}
			ACC=${KEY_PAIR%]*}
			$GETH_CMD --datadir=$DATA_DIR/$ID account import --password=<(echo password) <(echo $PRV_KEY)
			if ((i==0)); then
				echo ${ACC:1}
			fi
		done &
		done
}

function prefund_addresses {
	N=$1
	: ${KP_FILE:=../scripts/keypairs}
	for ((ID=0; ID<N; ID++)); do
		KEY_PAIR=`tail -n$((ID+1)) $KP_FILE | head -n1`
		ACC=${KEY_PAIR%]*}
		echo ${ACC:1}
	done
}

# generate the genesis json file
function generate_genesis {
	ACs=($@)

	(	set +x
		echo 2
		echo 1
		echo 3 # DCCS
		echo $BLOCK_TIME
		echo $EPOCH
		for AC in "${ACs[@]}"; do
			echo $AC
		done
		echo
		echo $THANGLONG_BLOCK
		echo $THANGLONG_EPOCH
		echo $STAKE_REQUIRE
		echo $STAKE_LOCK_HEIGHT
		echo $TOKEN_OWNER

		echo $ENDURIO_BLOCK
		echo $LEAK_DURATION
		echo $APP_CONFIRMS
		echo $RANDOM_ITERATION
		echo $PRICE_SAMPLING_INTERVAL
		echo $STABLECOIN_RATE
		# echo $PRICE_SAMPLING_DURATION
		# echo $ABSORPTION_DURATION
		# echo $ABSORPTION_EXPIRATION
		# echo $SLASHING_DURATION
		# echo $LOCKDOWN_EXPIRATION

		echo $MELINH_BLOCK

		echo $PREFUND_ADDR
		prefund_addresses 128
		echo
		echo no # Should the precompile-addresses (0x1 .. 0xff) be pre-funded with 1 wei?
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

function console {
	ID=$1
	$GETH_CMD --datadir=$DATA_DIR/$ID attach
}

function peer {
	IDs=($@)
	for ID in "${IDs[@]}"; do
		for D in `find $DATA_DIR -mindepth 1 -maxdepth 1 -type d`
		do
			I=`basename $D`
			test "$ID" = "$I" && continue
			NODEKEY=$DATA_DIR/$I/$CLIENT/nodekey
			test -f "$NODEKEY" || continue
			ENODE=`$BOOTNODE_CMD -nodekey=$DATA_DIR/$I/$CLIENT/nodekey -writeaddress`
			test "$ENODE" || continue
			ENODE=enode://$ENODE@127.0.0.1:$((30303 + I))
			$GETH_CMD --datadir=$DATA_DIR/$ID --exec="admin.addPeer('$ENODE')" attach
		done
	done
}

function start {
	IDs=($@)
	CMD_BASE="$GETH --mine"
	: ${MS:=1}
	: ${UL:=$MS}
	if ((UL>0)); then
		UNLOCKs="0"
		PASSWDs="echo password"
		for ((i=1; i<UL; i++)); do
			UNLOCKs="$UNLOCKs,$i"
			PASSWDs="$PASSWDs;echo password"
		done
		CMD_BASE="$CMD_BASE --unlock=$UNLOCKs --password=<($PASSWDs)"
	fi
	# add --allow-insecure-unlock for geth 1.9+
	$GETH --help | grep "allow-insecure-unlock" && CMD_BASE="$CMD_BASE --allow-insecure-unlock"
	if [ ! -z "$BOOTNODE_STRING" ]; then
		CMD_BASE="$CMD_BASE --bootnodes $BOOTNODE_STRING"
	else
		CMD_BASE="$CMD_BASE --nodiscover"
	fi
	
	if [ ! -z "$ROLLBACK" ]; then
		CMD_BASE="$CMD_BASE --rollback=$ROLLBACK"
	fi

	for ID in "${IDs[@]}"; do
		CMD="$CMD_BASE --datadir=$DATA_DIR/$ID"
		CMD="$CMD --ethstats=$ID:$ETHSTATS"
		CMD="$CMD --port=$((30303 + ID))"
		CMD="$CMD --rpcport=$((8545 + ID))"

		# mesh peering
		if [ -z "$BOOTNODE_STRING" ]; then
		(	sleep $((3+LAST_ID))s
			peer $ID
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
	ACs=(`import_account ${IDs[@]}`)
	
	# stock network, no need to generate genesis
	test "$NET" && return	

	GENESIS_JSON=`init_genesis ${ACs[@]}`

	for ID in "${IDs[@]}"; do
		init_geth $ID $GENESIS_JSON &
	done
	wait

	# start "${IDs[@]}"
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
	sleep 2s
	start "$@"
}

function killall {
	killall -q --signal SIGINT $(basename -- "$GETH_CMD") &
}

"$@"
