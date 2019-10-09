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
declare -A IMAGE_ID

# Ubuntu 16 LTS
IMAGE_ID=(
	[us-east-1]=ami-0ac019f4fcb7cb7e6
	[us-east-2]=ami-0f65671a86f061fcd
	[us-west-1]=ami-063aa838bd7631e0b
	[us-west-2]=ami-0bbe6b35405ecebdb
	[ap-southeast-1]=ami-0c5199d385b432989
	[ap-southeast-2]=ami-07a3bd4944eb120a0
	[ca-central-1]=ami-0427e8367e3770df1
	[eu-central-1]=ami-0bdf93799014acdc4
	[eu-west-2]=ami-0b0a60c0a2bd40612
	[eu-west-3]=ami-08182c55a1c188dee
)

# Ubuntu 18.04 LTS
# IMAGE_ID=(
# 	[us-east-1]=ami-0a313d6098716f372
# 	[us-east-2]=ami-0c55b159cbfafe1f0
# 	[us-west-1]=ami-06397100adf427136
# 	[us-west-2]=ami-005bdb005fb00e791
# 	[ap-southeast-1]=ami-0dad20bd1b9c8c004
# 	[ap-southeast-2]=ami-0b76c3b150c6b1423
# 	[ca-central-1]=ami-01b60a3259250381b
# 	[eu-central-1]=ami-090f10efc254eaf55
# 	[eu-west-2]=ami-07dc734dc14746eab
# 	[eu-west-3]=ami-03bca18cb3dc173c9
# )

# CONFIG
: ${NETWORK_NAME:=zergity}
: ${CLIENT:=gonex}
: ${NETWORK_ID:=111111}
: ${BINARY_POSTFIX:=}
: ${INSTANCE_NAME:=${NETWORK_NAME}_Sealer}
: ${DEFAULT_INSTANCE_TYPE:=t3.micro}
declare -A INSTANCES
INSTANCES=(
	[ap-southeast-1]=t2.medium
	[ap-southeast-2]=t3.micro
	[us-east-2]=t3.micro
	[eu-west-2]=t2.large
	[us-west-1]=t2.medium
	[ca-central-1]=t2.medium
)
: ${KEY_NAME:=DevOp}
: ${KEY_LOCATION:=~/.ssh/devop}
: ${ETHSTATS:=nexty-devnet@stats.testnet.nexty.io:8080}
: ${SSH_USER:=ubuntu}
: ${NET_DIR:=/tmp/aws.sh/$NETWORK_NAME}
: ${KP_FILE:=../scripts/keypairs}

: ${VERBOSITY:=5}
: ${MAX_PEER:=13}

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
: ${EPOCH:=10}
: ${THANGLONG_BLOCK:=10}
: ${THANGLONG_EPOCH:=10}

: ${ENDURIO_BLOCK:=20}
: ${LEAK_DURATION:=64}
: ${APP_CONFIRMS:=8}
: ${RANDOM_ITERATION:=3000000}
: ${PRICE_SAMPLING_DURATION:=50}
: ${PRICE_SAMPLING_INTERVAL:=3}
: ${ABSORPTION_DURATION:=13}
: ${ABSORPTION_EXPIRATION:=26}
: ${SLASHING_DURATION:=13}
: ${LOCKDOWN_EXPIRATION:=39}

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
# GETH="$GETH --vdf.gen=vdf-cli"
# GETH="$GETH --price.url=http://localhost:3000/price/NUSD_USD"
#GETH="$GETH --txpool.spammyage=0"

function trim {
	awk '{$1=$1};1'
}

function instance_ids {
	aws ec2 describe-instances\
			--region=$REGION\
			--filters Name=tag:$1,Values=$2 Name=instance-state-name,Values=running,stopped\
			--query="Reservations[].Instances[].[InstanceId]"\
			--output=text | tr "\n" " " | awk '{$1=$1};1'
}

function instance_state {
	aws ec2 describe-instance-status\
			--region=$REGION\
			--output=$OUTPUT_TYPE\
			--instance-id $1\
			--query "InstanceStatuses[].InstanceState[].[Name]"\
			--output=text | tr "\n" " " | awk '{$1=$1};1'
}

function instance_ip {
	aws ec2 describe-instances\
			--region=$REGION\
			--instance-ids $@\
			--query "Reservations[].Instances[].[PublicIpAddress]"\
			--output=text | tr "\n" " " | awk '{$1=$1};1'
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
	rm -rf $NET_DIR
	mkdir -p $NET_DIR

	for REGION in "${!INSTANCES[@]}"; do
	(
		IDs=`launch_instance $COUNT`
		aws ec2 wait instance-running --instance-ids $IDs --region=$REGION
		IPs=`instance_ip $IDs`
		for IP in $IPs; do
			touch $NET_DIR/$IP
		done
		LAST_IP=${IPs##* }
		ssh_ready $SSH_USER@$LAST_IP
		# echo $IPs >| $NET_DIR/ips/$REGION
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
	wait
	init $IPs
	wait
	start $IPs
}

function deploy {
	if [ -z "$*" ]; then
		IPs=
		for F in $NET_DIR/*; do
			IP=`basename $F`
			IPs="$IPs $IP"
		done
	else
		IPs=$@
	fi

	# strip and deploy gonex binary
	strip -s $BIN_PATH/$GETH_CMD
	$PSCP -h <(printf "%s\n" $IPs) -l ubuntu $BIN_PATH/$GETH_CMD /home/ubuntu/
}

function deploy_once {
	if [ -z "$*" ]; then
		IPs=
		for F in $NET_DIR/*; do
			IP=`basename $F`
			IPs="$IPs $IP"
		done
	else
		IPs=$@
	fi

	# strip and deploy bootnode binary
	strip -s $BIN_PATH/$BOOTNODE_CMD
	$PSCP -h <(printf "%s\n" ${IPs[@]}) -l ubuntu $BIN_PATH/$BOOTNODE_CMD /home/ubuntu/

	# deploy vdf-cli binary
	$PSCP -h <(printf "%s\n" ${IPs[@]}) -l ubuntu $VDF_PATH /home/ubuntu/
	for IP in $IPs; do
		$SSH $SSH_USER@$IP "sudo mv /home/ubuntu/$VDF_CLI /usr/bin/" &
	done
}

function init {
	if [ -z "$*" ]; then
		IPs=()
		for F in $NET_DIR/*; do
			IP=`basename $F`
			IPs+=($IP)
		done
	else
		IPs=($@)
	fi

	# generate and deploy genesis.json
	GENESIS_JSON=`generate_genesis ${#IPs[@]}`
	$PSCP -h <(printf "%s\n" $@) -l $SSH_USER $GENESIS_JSON /home/ubuntu/
	mv $GENESIS_JSON /tmp/ # for debug

	for ID in "${!IPs[@]}"; do
	(
		IP=${IPs[ID]}

		# set remote hostname
		$SSH $SSH_USER@$IP "sudo hostname ${IP//\./-}" &

		# import_account
		KEY_PAIR=`head -n$((ID+1)) $KP_FILE | tail -n1`
		PRV_KEY=${KEY_PAIR#*=}
		$SSH $SSH_USER@$IP "./$GETH_BARE account import --password=<(echo password) <(echo $PRV_KEY)"

		# init database
		$SSH $SSH_USER@$IP "./$GETH_BARE init $NETWORK_NAME.json"
	) &
	done
}

function start {
	if [ -z "$*" ]; then
		IPs=
		for F in $NET_DIR/*; do
			IP=`basename $F`
			IPs="$IPs $IP"
		done
	else
		IPs=$@
	fi

	for IP in $IPs; do
	(
		# random % of [0,32768)
		if [ "$RANDOM" -le 16384 ]; then
			CMD="$GETH --vdf.gen=$VDF_CLI"
		else
			CMD="$GETH"
		fi
		$SSH $SSH_USER@$IP "nohup ./$CMD --ethstats=$IP:$ETHSTATS &>./$CLIENT.log &"

		# fetch enode once
		if [ ! -s $NET_DIR/$IP ]; then
			NODEKEY=`$SSH $SSH_USER@$IP "./$BOOTNODE_CMD -nodekey=./.nexty/gonex/nodekey -writeaddress"`
			echo $NODEKEY >| $NET_DIR/$IP
		fi
	) &
	done
	wait

	peers $IPs
}

function stop {
	if [ -z "$*" ]; then
		IPs=()
		for F in $NET_DIR/*; do
			IP=`basename $F`
			IPs+=($IP)
		done
	else
		IPs=($@)
	fi

	for IP in ${IPs[@]}; do
		$SSH $SSH_USER@$IP killall -q --signal SIGINT $GETH_CMD &
	done
}

# restart InstantName
function restart {
	stop $@
	wait
	start $@
}

function peers {
	if [ -z "$*" ]; then
		IPs=()
		for F in $NET_DIR/*; do
			IP=`basename $F`
			IPs+=($IP)
		done
	else
		IPs=($@)
	fi

	for IP in ${IPs[@]}; do
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

function sealing_addresses {
	N=$1
	for ((ID=0; ID<N; ID++)); do
		KEY_PAIR=`head -n$((ID+1)) $KP_FILE | tail -n1`
		ACC=${KEY_PAIR%]*}
		echo ${ACC:1}
	done
}

function prefund_addresses {
	N=$1
	for ((ID=0; ID<N; ID++)); do
		KEY_PAIR=`tail -n$((ID+1)) $KP_FILE | head -n1`
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
		echo $TOKEN_OWNER

		echo $ENDURIO_BLOCK
		echo $LEAK_DURATION
		echo $APP_CONFIRMS
		echo $RANDOM_ITERATION
		echo $PRICE_SAMPLING_DURATION
		echo $PRICE_SAMPLING_INTERVAL
		echo $ABSORPTION_DURATION
		echo $ABSORPTION_EXPIRATION
		echo $SLASHING_DURATION
		echo $LOCKDOWN_EXPIRATION

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
			--output=text | tr "\n" " " | awk '{$1=$1};1'
}

function terminate {
	if [ "$1" = "all" ]; then
		for REGION in "${!IMAGE_ID[@]}"; do
			_terminate &
		done
		wait
	fi
}

function _terminate {
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
