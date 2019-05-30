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
: ${NETWORK_ID:=50913}
: ${BINARY_POSTFIX:=}
: ${BOOTNODE_NAME:=${NETWORK_NAME}_BootNode}
: ${INSTANCE_NAME:=${NETWORK_NAME}_Sealer}
: ${DEFAULT_INSTANCE_TYPE:=t3.xlarge}
declare -A INSTANCES
INSTANCES=(
	 [ap-southeast-1]=t2.medium
	[ap-southeast-2]=t2.large
	[us-east-2]=t3.xlarge
	[eu-west-2]=t2.large
	[us-west-1]=t2.medium
	[ca-central-1]=t2.medium
)
: ${KEY_NAME:=DevOp}
: ${KEY_LOCATION:=~/.ssh/devop}
: ${BOOTNODE_REGION:=ap-southeast-1}
: ${BOOTNODE_INSTANCE_TYPE:=t3.micro}
: ${ETHSTATS:=nexty-devnet@stats.testnet.nexty.io:8080}
: ${SSH_USER:=ubuntu}
: ${VERBOSITY:=5}
: ${MAX_PEER:=13}

: ${PREFUND_ADDR:=000007e01c1507147a0e338db1d029559db6cb19}
: ${BLOCK_TIME:=1}
: ${EPOCH:=30}

: ${THANGLONG_BLOCK:=60}
: ${THANGLONG_EPOCH:=20}
: ${CONTRACT_ADDR:=0000000000000000000000000000000000012345}
: ${STAKE_REQUIRE:=100}
: ${STAKE_LOCK_HEIGHT:=150}
: ${TOKEN_OWNER:=000000270840d8ebdffc7d162193cc5ba1ad8707}

: ${ENDURIO_BLOCK:=80}
: ${PRICE_DURATION:=30}
: ${PRICE_INTERVAL:=2}


OUTPUT_TYPE=table

# Global Variables
BOOTNODE_ENODE=

# COMMAND SHORTCUTS
if [ -x "$(command -v pscp)" ]; then
	PSCP_CMD=pscp
elif [ -x "$(command -v parallel-ssh)" ]; then
	PSCP_CMD=parallel-scp
else
	echo 'Parallel-ssh/pscp not found.'
	exit -1
fi
: ${GETH_CMD:=gonex$BINARY_POSTFIX}
: ${GETH_CMD_BIN:=gonex}
: ${PUPPETH_CMD:=puppeth$BINARY_POSTFIX}
: ${BOOTNODE_CMD:=bootnode$BINARY_POSTFIX}
SSH="ssh -oStrictHostKeyChecking=no -oBatchMode=yes -i$KEY_LOCATION"
SCP="scp -oStrictHostKeyChecking=no -oBatchMode=yes -i$KEY_LOCATION -C"
PSCP="$PSCP_CMD -OStrictHostKeyChecking=no -OBatchMode=yes -x-i$KEY_LOCATION -x-C"
SSH_COPY_ID="ssh-copy-id -i$KEY_LOCATION -f"
GETH="./$GETH_CMD --syncmode=fast --networkid=$NETWORK_ID --rpc --rpcapi=db,eth,net,web3,personal --rpccorsdomain=\"*\" --rpcaddr=0.0.0.0 --gasprice=0 --targetgaslimit=42000000 --txpool.nolocals --txpool.pricelimit=0 --verbosity=$VERBOSITY --maxpeers=$MAX_PEER"

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

function bootnode {
	REGION=$BOOTNODE_REGION
	ID=`instance_ids Name $BOOTNODE_NAME | awk {'print $NF'}`

	if [ -n "$ID" ]; then
		STATE=`instance_state $ID`
		if [ "$STATE" != "running" ]; then
			aws ec2 start-instances --instance-ids $ID &>/dev/null
			aws ec2 wait instance-running --instance-ids $ID
		fi
	fi

	if [ -z "$ID" ]; then
		ID=$(aws ec2 run-instances\
				--block-device-mappings="DeviceName=/dev/sda1,Ebs={VolumeSize=100,VolumeType=gp2}"\
				--image-id=${IMAGE_ID[$REGION]}\
				--instance-type=$BOOTNODE_INSTANCE_TYPE\
				--region=$REGION\
				--key-name=$KEY_NAME\
				--tag-specifications="ResourceType=instance,Tags=[{Key=Name,Value=$BOOTNODE_NAME}]"\
				--query "Instances[].[InstanceId]"\
				--output=text | tr "\n" " " | awk '{$1=$1};1')
		aws ec2 wait instance-running --region $REGION --instance-ids $ID
	fi

	IP=`instance_ip $ID`
	ssh_ready $SSH_USER@$IP

	if ! $SSH $SSH_USER@$IP stat boot.key \> /dev/null 2\>\&1; then
		# remote boot.key not exist
		./build/bin/$BOOTNODE_CMD --genkey=boot.key
		$SCP build/bin/$BOOTNODE_CMD $SSH_USER@$IP:./
		$SCP boot.key $SSH_USER@$IP:./
	fi

	$SSH $SSH_USER@$IP "nohup yes | ./$BOOTNODE_CMD -nodekey=boot.key -addr=:33333 -verbosity=9 &>bootnode.log &"

	echo enode://`./build/bin/$BOOTNODE_CMD -nodekey=boot.key -writeaddress`@$IP:33333
}

function load {
	COUNT=${1:-1}
	: ${BOOTNODE_ENODE:=`bootnode`}

	rm -rf /tmp/aws.sh/ips
	mkdir -p /tmp/aws.sh/ips
	for REGION in "${!INSTANCES[@]}"; do
		(	IDs=`launch_instance $COUNT`
			aws ec2 wait instance-running --instance-ids $IDs --region=$REGION
			IPs=`instance_ip $IDs`
			LAST_IP=${IPs##* }
			ssh_ready $SSH_USER@$LAST_IP
			echo $IPs >| /tmp/aws.sh/ips/$REGION
		) &
	done
	wait

	ALL_IPs=`cat /tmp/aws.sh/ips/* | tr "\n" " "`

	for IP in $ALL_IPS; do
		$SSH $SSH_USER@$IP "sudo hostname ${IP//\./-}" &
	done

	deploy $ALL_IPs
	start $ALL_IPs | tr "\n" " " | awk '{$1=$1};1'
	wait

	# ssh_key_copy $ALL_IPs
}

function ssh_key_copy {
	for pk in ./sshpubkeys/*.pub; do
		for IP in $@; do
			$SSH_COPY_ID -i $pk $SSH_USER@$IP &>/dev/null &
		done
	done
	wait
}

function create_account {
	IPs=($@)
	rm -rf /tmp/aws.sh/account
	mkdir -p /tmp/aws.sh/account
	for i in "${!IPs[@]}"; do
		$SSH $SSH_USER@${IPs[$i]} "./$GETH_CMD account new --password <(echo password)" >| /tmp/aws.sh/account/$i &
	done
	wait
	arr=()
	for i in "${!IPs[@]}"; do
		ACCOUNT=$(cat /tmp/aws.sh/account/$i)
		arr=(${arr[@]} ${ACCOUNT:10:40})
	done
	echo "${arr[@]}"
}

# load pre-fund account from keystore folder
function load_pre_fund_accounts {(
	set +x
	arr=()
	for file in ./.gonex/keystore/UTC--*; do
		if [[ -f $file ]]; then
			filename=$(basename -- "$file")
			arr=(${arr[@]} ${filename:37:78})
		fi
	done
	echo "${arr[@]}"
)}

function test_load_pre_fund_accounts {
	echo `load_pre_fund_accounts`
}

# generate the genesis json file
function generate_genesis {
	ACs=($@)
	PFACs=(`load_pre_fund_accounts`)

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
		echo $PREFUND_ADDR
		for PFAC in "${PFACs[@]}"; do
			echo $PFAC
		done
		echo
		echo no
		echo $NETWORK_ID
		echo 2
		echo 2
		echo
	) >| /tmp/puppeth.input

	GENESIS_JSON=$NETWORK_NAME.json
	rm *.json ~/.puppeth/* /tmp/$GENESIS_JSON
	./build/bin/$PUPPETH_CMD --network=$NETWORK_NAME < /tmp/puppeth.input >/dev/null

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

function geth_start {
	IPs=($@)
	for IP in "${IPs[@]}"; do
		(	$SSH $SSH_USER@$IP "./$GETH_CMD init *.json"
			$SSH $SSH_USER@$IP "nohup $GETH --bootnodes $BOOTNODE_ENODE --mine --unlock 0 --password <(echo password) --ethstats $IP:$ETHSTATS &>./geth.log &"
			$SSH $SSH_USER@$IP "printf \"$NETWORK_ID\" >| networkid.info; printf \"$BOOTNODE_ENODE\" >| bootnode.info; printf \"$ETHSTATS\" > ethstats.info;"
		) &
	done
	wait
}

function start {
	IPs=($@)
	ACs=(`create_account ${IPs[@]}`)
	
	GENESIS_JSON=`init_genesis ${ACs[@]}`

	$PSCP -h <(printf "%s\n" $@) -l $SSH_USER $GENESIS_JSON /home/ubuntu/

	mv $GENESIS_JSON /tmp/

	geth_start ${IPs[@]}
}

# restart InstantName
function restart {
	for REGION in "${!IMAGE_ID[@]}"; do
		(	IDs=`instance_ids Name ${1:-$INSTANCE_NAME}`
			geth_restart `instance_ip $IDs`
		) &
	done
	wait
}

function deploy {
	IPs="$@"
	$PSCP -h <(printf "%s\n" $IPs) -l ubuntu ./build/bin/$GETH_CMD_BIN /home/ubuntu/$GETH_CMD
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
	if [ "$1" = "bn" ]; then
		REGION=$BOOTNODE_REGION
		_terminate $BOOTNODE_NAME
	elif [ "$1" = "all" ]; then
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

function stop {
	for IP in $@; do
		$SSH $SSH_USER@$IP killall -q --signal SIGINT $GETH_CMD &
	done
	wait
}

"$@"
