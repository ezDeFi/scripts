#!/bin/bash
#
# Usage
# + Terminate all instances
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
ROLLBACK=

# Initialize our own variables:

while getopts "h?r:" opt; do
    case "$opt" in
    h|\?)
        echo "$(basename ""$0"") [-h|-?] command"
        exit 0
        ;;
	r)
		ROLLBACK=$OPTARG
		;;
    esac
done

shift $((OPTIND-1))

[ "${1:-}" = "--" ] && shift

# CONSTANTS
declare -A IMAGE_ID

# Ubuntu 16 LTS
# IMAGE_ID=(
# 	[us-east-1]=ami-0ac019f4fcb7cb7e6
# 	[us-east-2]=ami-0f65671a86f061fcd
# 	[us-west-1]=ami-063aa838bd7631e0b
# 	[us-west-2]=ami-0bbe6b35405ecebdb
# 	[ap-southeast-1]=ami-0c5199d385b432989
# 	[ap-southeast-2]=ami-07a3bd4944eb120a0
# 	[ca-central-1]=ami-0427e8367e3770df1
# 	[eu-central-1]=ami-0bdf93799014acdc4
# 	[eu-west-2]=ami-0b0a60c0a2bd40612
# 	[eu-west-3]=ami-08182c55a1c188dee
# )

# Ubuntu 18.04 LTS
IMAGE_ID=(
	[us-east-1]=ami-0a313d6098716f372
	[us-east-2]=ami-0c55b159cbfafe1f0
	[us-west-1]=ami-06397100adf427136
	[us-west-2]=ami-005bdb005fb00e791
	[ap-southeast-1]=ami-0dad20bd1b9c8c004
	[ap-southeast-2]=ami-0b76c3b150c6b1423
	[ca-central-1]=ami-01b60a3259250381b
	[eu-central-1]=ami-090f10efc254eaf55
	[eu-west-2]=ami-07dc734dc14746eab
	[eu-west-3]=ami-03bca18cb3dc173c9
)

# CONFIG
: ${NETWORK_NAME:=zergity}
: ${CLIENT:=gonex}
: ${NETWORK_ID:=111111}
: ${BINARY_POSTFIX:=}
: ${INSTANCE_NAME:=${NETWORK_NAME}_Sealer}
: ${INSTANCE_TYPE:=t3a.micro}
declare -A INSTANCES
INSTANCES=(
	[us-east-1]=$INSTANCE_TYPE
	[us-east-2]=$INSTANCE_TYPE
	[us-west-1]=$INSTANCE_TYPE
	[us-west-2]=$INSTANCE_TYPE
	[ap-southeast-1]=$INSTANCE_TYPE
	[ap-southeast-2]=$INSTANCE_TYPE
	[eu-central-1]=$INSTANCE_TYPE
	[eu-west-2]=$INSTANCE_TYPE
	[eu-west-3]=$INSTANCE_TYPE
	[ca-central-1]=$INSTANCE_TYPE
)
: ${KEY_NAME:=DevOp}
: ${KEY_LOCATION:=~/.ssh/devop}
: ${ETHSTATS:=nexty-devnet@stats.testnet.nexty.io:8080}
: ${SSH_USER:=ubuntu}
: ${NET_DIR:=/tmp/aws.sh/$NETWORK_NAME}
: ${KP_FILE:=../scripts/keypairs}
: ${GENESIS_JSON:=$NETWORK_NAME.json}

: ${VERBOSITY:=5}
: ${MAX_PEER:=13}

: ${ETHSTATS:=nexty-devnet@stats.testnet.nexty.io:8080}
: ${STAKE_REQUIRE:=100}
: ${STAKE_LOCK_HEIGHT:=150}
: ${NTF_ACC:=000000270840d8ebdffc7d162193cc5ba1ad8707}
: ${NTF_KEY:=6fc22cccf0de9bb7fb63fa2926bdc5fc551d0ef5f496ff8a993ada505dd626d8}
: ${PREFUND_ADDR:=000007e01c1507147a0e338db1d029559db6cb19}
	# private: cd4bdb10b75e803d621f64cc22bffdfc5c4b9f8e63e67820cc27811664d43794
	# public:  a83433c26792c93eb56269976cffeb889636ff3f6193b60793fa98c74d9ccdbf4e3a80e2da6b86712e014441828520333828ac4f4605b5d0a8af544f1c5ca67e
	# address: 000007e01c1507147a0e338db1d029559db6cb19
PREFUND_ADDR=95e2fcBa1EB33dc4b8c6DCBfCC6352f0a253285d
	# private: a0cf475a29e527dcb1c35f66f1d78852b14d5f5109f75fa4b38fbe46db2022a5
: ${BLOCK_TIME:=1}
: ${EPOCH:=20}
: ${THANGLONG_BLOCK:=40}
: ${THANGLONG_EPOCH:=10}

: ${ENDURIO_BLOCK:=80}
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

OUTPUT_TYPE=table

# COMMAND SHORTCUTS
if [ -x "$(command -v pscp)" ]; then
	PSCP_CMD=pscp
elif [ -x "$(command -v parallel-ssh)" ]; then
	PSCP_CMD=parallel-scp
else
	echo 'Parallel-ssh/pscp not found.'
	exit -1
fi
: ${BIN_PATH:=`ls -d ../go{nex,-ethereum}/build/bin 2>/dev/null | head -n1`}
: ${ETHKEY_CMD:=ethkey$BINARY_POSTFIX}
: ${GETH_CMD:=${CLIENT}$BINARY_POSTFIX}
: ${PUPPETH_CMD:=$BIN_PATH/puppeth$BINARY_POSTFIX}
: ${VDF_CLI:=vdf-cli}
: ${VDF_PATH:=`type -p $VDF_CLI`}
: ${BOOTNODE_CMD:=bootnode$BINARY_POSTFIX}
SSH="ssh -oStrictHostKeyChecking=no -oBatchMode=yes -i$KEY_LOCATION"
SCP="scp -oStrictHostKeyChecking=no -oBatchMode=yes -i$KEY_LOCATION -C"
PSCP="$PSCP_CMD -OStrictHostKeyChecking=no -OBatchMode=yes -x-i$KEY_LOCATION -x-C"
SSH_COPY_ID="ssh-copy-id -i$KEY_LOCATION -f"
GETH_BARE="$GETH_CMD --nousb"
GETH="$GETH_BARE --networkid=$NETWORK_ID --rpc --rpcapi=db,eth,net,web3,personal --rpccorsdomain=\"*\" --rpcaddr=0.0.0.0 --gasprice=0 --targetgaslimit=42000000 --txpool.nolocals --txpool.pricelimit=0 --verbosity=$VERBOSITY --miner.recommit=500ms --allow-insecure-unlock --nodiscover"
GETH="$GETH --mine --unlock=0 --password=<(echo password)"
GETH="$GETH --syncmode=fast"
# GETH="$GETH --maxpeers=$MAX_PEER"
# GETH="$GETH --price.url=http://localhost:3000/price/NUSD_USD"
#GETH="$GETH --txpool.spammyage=0"

function trim {
	awk '{$1=$1};1'
}

function ips {
	if [ -z "$*" ]; then
		for F in $NET_DIR/*; do
			IP=`basename $F`
			printf "$IP "
		done
	elif [ "$1" == "random" ]; then
		for F in $NET_DIR/*; do
			if [ "$RANDOM" -le $((32768/${2:-2})) ]; then
				IP=`basename $F`
				printf "$IP "
			fi
		done
	else
		echo $@
	fi
}

function deploy {
	IPs=`ips $@`

	# strip and deploy gonex binary
	strip -s $BIN_PATH/$GETH_CMD
	$PSCP -h <(printf "%s\n" $IPs) -l ubuntu $BIN_PATH/$GETH_CMD /home/ubuntu/$GETH_CMD.new
}

function redeploy {
	IPs=`ips $@`

	stop $IPs
	deploy $IPs
	start $IPs
}

function deploy_once {
	IPs=`ips $@`

	# strip and deploy bootnode binary
	strip -s $BIN_PATH/$BOOTNODE_CMD
	$PSCP -h <(printf "%s\n" ${IPs[@]}) -l ubuntu $BIN_PATH/$BOOTNODE_CMD /home/ubuntu/

	# deploy vdf-cli binary
	$PSCP -h <(printf "%s\n" ${IPs[@]}) -l ubuntu $VDF_PATH /home/ubuntu/
	for IP in $IPs; do
		$SSH $SSH_USER@$IP "sudo mv /home/ubuntu/$VDF_CLI /usr/bin/" &
	done
}

function generate {
	IPs=`ips $@`
	ALL=(`ips`)

	# generate and deploy genesis.json
	GENESIS_JSON=`generate_genesis ${#ALL[@]}`
	mv $GENESIS_JSON /tmp/ # for debug
}

function init {
	IPs=`ips $@`
	ALL=(`ips`)

	$PSCP -h <(printf "%s\n" ${ALL[@]}) -l $SSH_USER /tmp/$GENESIS_JSON /home/ubuntu/

	for IP in $IPs; do
		ID=`id $IP`

		# clear the node key
		> $NET_DIR/$IP

		# set remote hostname
		CMD="sudo hostname ${IP//\./-}"

		# move the newly deployed binary
		CMD+=";mv ./$GETH_CMD.new ./$GETH_CMD"
		# reset gonex database
		CMD+=";rm -rf ./.nexty"

		# import_accounts
		KEY_PAIR=`prefund_keypair $ID`
		PREFUND_KEY=${KEY_PAIR#*=}
		KEY_PAIR=`sealing_keypair $ID`
		SEALING_KEY=${KEY_PAIR#*=}
		CMD+=" && ./$GETH_BARE account import --password=<(echo password) <(echo $SEALING_KEY)"
		CMD+=" && ./$GETH_BARE account import --password=<(echo password) <(echo $PREFUND_KEY)"
		CMD+=" && ./$GETH_BARE account import --password=<(echo password) <(echo $NTF_KEY)"

		# init database
		CMD+=" && ./$GETH_BARE init $GENESIS_JSON"

		# execute
		$SSH $SSH_USER@$IP "$CMD" &
	done
	wait
}

function start {
	IPs=`ips $@`

	for IP in $IPs; do
	(
		# random % of [0,32768)
		if [ "$RANDOM" -le 16384 ]; then
			CMD="$GETH --vdf.gen=$VDF_CLI"
		else
			CMD="$GETH"
		fi

		if [ ! -z "$ROLLBACK" ]; then
			CMD="$CMD --rollback=$ROLLBACK"
		fi

		$SSH $SSH_USER@$IP "mv ./$GETH_CMD.new ./$GETH_CMD; nohup ./$CMD --ethstats=$IP:$ETHSTATS &>./$CLIENT.log &"

		# fetch enode once
		if [ ! -s $NET_DIR/$IP ]; then
			NODEKEY=`$SSH $SSH_USER@$IP "./$BOOTNODE_CMD -nodekey=./.nexty/gonex/nodekey -writeaddress"`
			echo $NODEKEY >| $NET_DIR/$IP
		fi
	) &
	done
	wait

	sleep 3s
	peer $IPs
}

function stop {
	IPs=`ips $@`

	for IP in $IPs; do
		$SSH $SSH_USER@$IP killall -q --signal SIGINT $GETH_CMD &
	done
	wait
}

# restart InstantName
function restart {
	IPs=`ips $@`
	stop $IPs
	start $IPs
}

function peer {
	IPs=`ips $@`

	for IP in $IPs; do
		EXEC=
		for G in $NET_DIR/*; do
			# random % of [0,32768)
			if [ "$RANDOM" -le 16384 ]; then
				continue
			fi
			REMOTE_IP=`basename $G`
			if [ "$IP" == "$REMOTE_IP" ]; then
				continue
			fi
			NODEKEY=`cat $G`
			ENODE=enode://$NODEKEY@$REMOTE_IP:30303
			EXEC="$EXEC admin.addPeer('$ENODE');"
		done
		$SSH $SSH_USER@$IP "./$GETH_BARE --exec=\"$EXEC\" attach" &
	done
}

function rejoin {
	IPs=`ips $@`
	leave $IPs
	wait
	join $IPs
}

function leave {
	IPs=`ips $@`
	for IP in $IPs; do
		ID=`id $IP`
		KEY_PAIR=`prefund_keypair $ID`
		PREFUND_ACC=${KEY_PAIR%]*}
		PREFUND_ACC=${PREFUND_ACC:1}
		KEY_PAIR=`sealing_keypair $ID`
		SEALING_ACC=${KEY_PAIR%]*}
		SEALING_ACC=${SEALING_ACC:1}

		# NextyGovernance(0x12345).leave();
		EXEC="tx={from:eth.accounts[0],to:'0x1111111111111111111111111111111111111111',gas:'0x80000',data:'0x6080604052348015600f57600080fd5b506004361060285760003560e01c8063dffeadd014602d575b600080fd5b60336035565b005b6201234573ffffffffffffffffffffffffffffffffffffffff1663d66d9e196040518163ffffffff1660e01b8152600401602060405180830381600087803b158015607f57600080fd5b505af11580156092573d6000803e3d6000fd5b505050506040513d602081101560a757600080fd5b81019080805190602001909291905050505056'}"
		EXEC+=";personal.unlockAccount('0x${SEALING_ACC}', 'password')"
		EXEC+=";tx.from='0x${SEALING_ACC}';eth.sendTransaction(tx)"
		EXEC+=";personal.unlockAccount('0x${PREFUND_ACC}', 'password')"
		EXEC+=";tx.from='0x${PREFUND_ACC}';eth.sendTransaction(tx)"
		CMD="./$GETH_BARE --exec=\"$EXEC\" attach"
		$SSH $SSH_USER@$IP "$CMD" &
	done
}

# join $1 $2
function join {
	IPs=`ips $@`
	for IP in $IPs; do
		ID=`id $IP`
		KEY_PAIR=`prefund_keypair $ID`
		PREFUND_ACC=${KEY_PAIR%]*}
		PREFUND_ACC=${PREFUND_ACC:1}
		KEY_PAIR=`sealing_keypair $ID`
		SEALING_ACC=${KEY_PAIR%]*}
		SEALING_ACC=${SEALING_ACC:1}

		# pre-fund the holder
        # uint stakeRequire = 100 * 10**18;
        # IERC20 ntf = IERC20(0x2c783AD80ff980EC75468477E3dD9f86123EcBDa);
        # NextyGovernance gov = NextyGovernance(0x12345);
        # uint deposited = gov.getBalance(0x2222222222222222222222222222222222222222);
        # uint balance = ntf.balanceOf(0x2222222222222222222222222222222222222222);
        # if (stakeRequire <= deposited + balance) {
        #     return;
        # }
        # uint need = stakeRequire - deposited - balance; // safe
        # ntf.approve(0x2222222222222222222222222222222222222222, need);
		BINARY='608060405234801561001057600080fd5b506004361061002b5760003560e01c8063dffeadd014610030575b600080fd5b61003861003a565b005b600068056bc75e2d6310000090506000732c783ad80ff980ec75468477e3dd9f86123ecbda9050600062012345905060008173ffffffffffffffffffffffffffffffffffffffff1663f8b2cb4f7322222222222222222222222222222222222222226040518263ffffffff1660e01b8152600401808273ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200191505060206040518083038186803b1580156100fc57600080fd5b505afa158015610110573d6000803e3d6000fd5b505050506040513d602081101561012657600080fd5b8101908080519060200190929190505050905060008373ffffffffffffffffffffffffffffffffffffffff166370a082317322222222222222222222222222222222222222226040518263ffffffff1660e01b8152600401808273ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200191505060206040518083038186803b1580156101cc57600080fd5b505afa1580156101e0573d6000803e3d6000fd5b505050506040513d60208110156101f657600080fd5b81019080805190602001909291905050509050808201851161021c575050505050610303565b6000818387030390508473ffffffffffffffffffffffffffffffffffffffff1663095ea7b3732222222222222222222222222222222222222222836040518363ffffffff1660e01b8152600401808373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200182815260200192505050602060405180830381600087803b1580156102c057600080fd5b505af11580156102d4573d6000803e3d6000fd5b505050506040513d60208110156102ea57600080fd5b8101908080519060200190929190505050505050505050505b56'
		BINARY=${BINARY//2222222222222222222222222222222222222222/$PREFUND_ACC}
		EXEC="personal.unlockAccount('0x${NTF_ACC}', 'password')"
		EXEC+=";tx={from:'0x${NTF_ACC}',to:'0x1111111111111111111111111111111111111111',gas:'0x80000',gasPrice:'0x0',data:'0x${BINARY}'}"
		EXEC+=";eth.sendTransaction(tx)"
		# CMD+=";./$GETH_BARE --exec=\"$EXEC\" attach"

		# join the gov
        # uint stakeRequire = 100 * 10**18;
        # IERC20 ntf = IERC20(0x2c783AD80ff980EC75468477E3dD9f86123EcBDa);
        # NextyGovernance gov = NextyGovernance(0x12345);
        # uint status = gov.getStatus(msg.sender);
        # if (status == 1) { // ACTIVE
        #     gov.leave();
        # }
        # uint allowance = ntf.allowance(0x4444444444444444444444444444444444444444, msg.sender);
        # ntf.transferFrom(0x4444444444444444444444444444444444444444, msg.sender, allowance);
        # uint deposited = gov.getBalance(msg.sender);
        # if (deposited < stakeRequire) {
        #     uint need = stakeRequire - deposited;
        #     uint balance = ntf.balanceOf(msg.sender);
        #     if (balance < need) {
        #         revert("not enough mineral");
        #     }
        #     ntf.approve(address(gov), need);
        #     gov.deposit(need);
        # }
        # gov.join(0x2222222222222222222222222222222222222222);
		BINARY='608060405234801561001057600080fd5b506004361061002b5760003560e01c8063dffeadd014610030575b600080fd5b61003861003a565b005b600068056bc75e2d6310000090506000732c783ad80ff980ec75468477e3dd9f86123ecbda9050600062012345905060008173ffffffffffffffffffffffffffffffffffffffff166330ccebb5336040518263ffffffff1660e01b8152600401808273ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200191505060206040518083038186803b1580156100e857600080fd5b505afa1580156100fc573d6000803e3d6000fd5b505050506040513d602081101561011257600080fd5b8101908080519060200190929190505050905060018114156101b3578173ffffffffffffffffffffffffffffffffffffffff1663d66d9e196040518163ffffffff1660e01b8152600401602060405180830381600087803b15801561017657600080fd5b505af115801561018a573d6000803e3d6000fd5b505050506040513d60208110156101a057600080fd5b8101908080519060200190929190505050505b60008373ffffffffffffffffffffffffffffffffffffffff1663dd62ed3e734444444444444444444444444444444444444444336040518363ffffffff1660e01b8152600401808373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1681526020018273ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1681526020019250505060206040518083038186803b15801561027a57600080fd5b505afa15801561028e573d6000803e3d6000fd5b505050506040513d60208110156102a457600080fd5b810190808051906020019092919050505090508373ffffffffffffffffffffffffffffffffffffffff166323b872dd73444444444444444444444444444444444444444433846040518463ffffffff1660e01b8152600401808473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1681526020018373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1681526020018281526020019350505050602060405180830381600087803b15801561038657600080fd5b505af115801561039a573d6000803e3d6000fd5b505050506040513d60208110156103b057600080fd5b81019080805190602001909291905050505060008373ffffffffffffffffffffffffffffffffffffffff1663f8b2cb4f336040518263ffffffff1660e01b8152600401808273ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200191505060206040518083038186803b15801561044157600080fd5b505afa158015610455573d6000803e3d6000fd5b505050506040513d602081101561046b57600080fd5b8101908080519060200190929190505050905085811015610714576000818703905060008673ffffffffffffffffffffffffffffffffffffffff166370a08231336040518263ffffffff1660e01b8152600401808273ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200191505060206040518083038186803b15801561050c57600080fd5b505afa158015610520573d6000803e3d6000fd5b505050506040513d602081101561053657600080fd5b81019080805190602001909291905050509050818110156105bf576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260128152602001807f6e6f7420656e6f756768206d696e6572616c000000000000000000000000000081525060200191505060405180910390fd5b8673ffffffffffffffffffffffffffffffffffffffff1663095ea7b387846040518363ffffffff1660e01b8152600401808373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200182815260200192505050602060405180830381600087803b15801561064657600080fd5b505af115801561065a573d6000803e3d6000fd5b505050506040513d602081101561067057600080fd5b8101908080519060200190929190505050508573ffffffffffffffffffffffffffffffffffffffff1663b6b55f25836040518263ffffffff1660e01b815260040180828152602001915050602060405180830381600087803b1580156106d557600080fd5b505af11580156106e9573d6000803e3d6000fd5b505050506040513d60208110156106ff57600080fd5b81019080805190602001909291905050505050505b8373ffffffffffffffffffffffffffffffffffffffff166328ffe6c87322222222222222222222222222222222222222226040518263ffffffff1660e01b8152600401808273ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff168152602001915050602060405180830381600087803b1580156107a757600080fd5b505af11580156107bb573d6000803e3d6000fd5b505050506040513d60208110156107d157600080fd5b81019080805190602001909291905050505050505050505056'
		BINARY=${BINARY//4444444444444444444444444444444444444444/$NTF_ACC}
		BINARY=${BINARY//2222222222222222222222222222222222222222/$SEALING_ACC}
		EXEC+=";personal.unlockAccount('0x${PREFUND_ACC}', 'password')"
		EXEC+=";tx={from:'0x${PREFUND_ACC}',to:'0x1111111111111111111111111111111111111111',gas:'0x80000',gasPrice:'0x0',data:'0x${BINARY}'}"
		EXEC+=";eth.sendTransaction(tx)"
		# EXEC+=";personal.unlockAccount('0x${SEALING_ACC}', 'password')"
		CMD="./$GETH_BARE --exec=\"$EXEC\" attach"

		$SSH $SSH_USER@$IP "$CMD" &
	done
}

# id IP
function id {
	IPs=(`ips`)
	for ID in "${!IPs[@]}"; do
		IP=${IPs[ID]}
		if [ "$IP" == "$1" ]; then
			echo $ID
			return
		fi
	done
}

function sealing_keypair {
	ID=$1
	head -n$((ID+1)) $KP_FILE | tail -n1
}

function sealing_addresses {
	N=$1
	for ((ID=0; ID<N; ID++)); do
		KEY_PAIR=`sealing_keypair $ID`
		ACC=${KEY_PAIR%]*}
		echo ${ACC:1}
	done
}

function prefund_keypair {
	ID=$1
	tail -n$((ID+1)) $KP_FILE | head -n1
}

function prefund_addresses {
	N=$1
	for ((ID=0; ID<N; ID++)); do
		KEY_PAIR=`prefund_keypair $ID`
		ACC=${KEY_PAIR%]*}
		echo ${ACC:1}
	done
}

# generate the genesis json file
function generate_genesis {
	N=$1

	(	set +x
		echo 2
		echo 1
		echo 3 # DCCS
		echo $BLOCK_TIME
		echo $EPOCH
		sealing_addresses $N
		echo
		echo $THANGLONG_BLOCK
		echo $THANGLONG_EPOCH
		echo $STAKE_REQUIRE
		echo $STAKE_LOCK_HEIGHT
		echo $NTF_ACC

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

		echo $PREFUND_ADDR
		prefund_addresses 128
		echo
		echo no # Should the precompile-addresses (0x1 .. 0xff) be pre-funded with 1 wei?
		echo $NETWORK_ID
		echo 2
		echo 2
		echo
	) >| /tmp/puppeth.input

	rm -f $NETWORK_NAME-*.json ~/.puppeth/* /tmp/$GENESIS_JSON
	$PUPPETH_CMD --network=$NETWORK_NAME < /tmp/puppeth.input >/dev/null

	if [ ! -f "$GENESIS_JSON" ]; then
		>&2 echo "Unable to create genesis file with Puppeth"
		exit -1
	fi

	echo $GENESIS_JSON
}

function instance_ids {
	aws ec2 describe-instances\
			--region=$REGION\
			--filters Name=tag:$1,Values=$2 Name=instance-state-name,Values=running,stopped\
			--query="Reservations[].Instances[].[InstanceId]"\
			--output=text | tr "\n" " " | trim
}

function instance_state {
	aws ec2 describe-instance-status\
			--region=$REGION\
			--output=$OUTPUT_TYPE\
			--instance-id $1\
			--query "InstanceStatuses[].InstanceState[].[Name]"\
			--output=text | tr "\n" " " | trim
}

function instance_ip {
	aws ec2 describe-instances\
			--region=$REGION\
			--instance-ids $@\
			--query "Reservations[].Instances[].[PublicIpAddress]"\
			--output=text | tr "\n" " " | trim
}

function ssh_ready {
	(	set +x
	# Probe SSH connection until it's available 
	X_READY=''
	while [ ! $X_READY ]; do
		sleep 1s
		set +e
		OUT=$($SSH -oConnectTimeout=1 $@ exit &>/dev/null)
		[[ $? = 0 ]] && X_READY='ready'
		set -e
	done 
	)
}

function load {
	local COUNT=${1:-1}
	mkdir -p $NET_DIR

	for REGION in "${!INSTANCES[@]}"; do
	(
		IDs=`launch_instance $COUNT`
		aws ec2 wait instance-running --instance-ids $IDs --region=$REGION
		IPs=`instance_ip $IDs`
		for IP in $IPs; do
			touch $NET_DIR/$IP
			(
				# wait for SSH port to be ready
				ssh_ready $SSH_USER@$IP
				# swap on
				$SSH $SSH_USER@$IP "sudo fallocate -l 4G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile"
			) &
		done
		wait
	) &
	done
	wait

	IPs=
	for F in $NET_DIR/*; do
		IP=`basename $F`
		IPs="$IPs $IP"
	done

	deploy_once $IPs
	deploy $IPs
	generate $IPs
	init $IPs
	# start $IPs
}

function launch_instance {
	COUNT=${1:-1}
	aws ec2 run-instances\
	    --block-device-mappings="DeviceName=/dev/sda1,Ebs={VolumeSize=100,VolumeType=gp2}"\
			--region=$REGION\
			--image-id=${IMAGE_ID[$REGION]}\
			--instance-type=${INSTANCES[$REGION]}\
			--key-name=$KEY_NAME\
			--tag-specifications="ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]"\
			--count=$COUNT\
			--query "Instances[].[InstanceId]"\
			--output=text | tr "\n" " " | trim
}

# terminate all
function terminate {
	if [ "$1" = "all" ]; then
		for REGION in "${!IMAGE_ID[@]}"; do
			terminate_region &
		done
		wait
		rm -rf $NET_DIR
	fi
}

# REGION=abc terminate_region
function terminate_region {
	IDs=`instance_ids Name ${1:-$INSTANCE_NAME}`

	if [ -z "$IDs" ]; then
		return
	fi

	stop `instance_ip $IDs`

	aws ec2 terminate-instances\
			--region=$REGION\
			--instance-ids $IDs >/dev/null
}

"$@"
