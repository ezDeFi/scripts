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

# CONFIG
: ${NETWORK_NAME:=testnet}
: ${NETWORK_ID:=50913}
: ${BINARY_POSTFIX:=}
: ${BOOTNODE_NAME:=${NETWORK_NAME}_BootNode}
: ${INSTANCE_NAME:=${NETWORK_NAME}_Sealer}
: ${DEFAULT_INSTANCE_TYPE:=t3.xlarge}
declare -A INSTANCES
INSTANCES=(
	[ap-southeast-1]=$DEFAULT_INSTANCE_TYPE
	[ap-southeast-2]=c5d.2xlarge
	[us-east-1]=$DEFAULT_INSTANCE_TYPE
)
: ${KEY_NAME:=DevOp}
: ${BOOTNODE_REGION:=ap-southeast-1}
: ${BOOTNODE_INSTANCE_TYPE:=t3.micro}
: ${ETHSTATS:=nexty-testnet@198.13.40.85:80}
: ${CONTRACT_ADDR:=cafecafecafecafecafecafecafecafecafecafe}
: ${BLOCK_TIME:=2}
: ${EPOCH:=90}
: ${SSH_USER:=ubuntu}

OUTPUT_TYPE=table

# Global Variables
BOOTNODE_STRING=

# COMMAND SHORTCUTS
if [ -x "$(command -v pscp)" ]; then
	PSCP_CMD=pscp
elif [ -x "$(command -v parallel-ssh)" ]; then
	PSCP_CMD=parallel-scp
else
	echo 'Parallel-ssh/pscp not found.'
	exit -1
fi
: ${GETH_CMD:=geth$BINARY_POSTFIX}
: ${PUPPETH_CMD:=puppeth$BINARY_POSTFIX}
: ${BOOTNODE_CMD:=bootnode$BINARY_POSTFIX}
SSH="ssh -oStrictHostKeyChecking=no -oBatchMode=yes"
SCP="scp -oStrictHostKeyChecking=no -oBatchMode=yes"
PSCP="$PSCP_CMD -OStrictHostKeyChecking=no -OBatchMode=yes"
SSH_COPY_ID="ssh-copy-id -f"
GETH="./$GETH_CMD --syncmode full --cache 2048 --gcmode=archive --networkid $NETWORK_ID --rpc --rpcapi db,eth,net,web3,personal --rpccorsdomain \"*\" --rpcaddr 0.0.0.0 --gasprice 0 --targetgaslimit 42000000 --txpool.nolocals --txpool.pricelimit 0"

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
	# Probe SSH connection until it's avalable 
	X_READY=''
	while [ ! $X_READY ]; do
		sleep 1s
		set +e
		OUT=$($SSH -oConnectTimeout=1 $@ exit &>/dev/null)
		[[ $? = 0 ]] && X_READY='ready'
		set -e
	done 
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

	$SSH $SSH_USER@$IP "nohup yes | ./$BOOTNODE_CMD -nodekey=boot.key -verbosity 9 &>bootnode.log &"

	echo enode://`./build/bin/$BOOTNODE_CMD -nodekey=boot.key -writeaddress`@$IP:33333
}

function load {
	COUNT=${1:-1}
	BOOTNODE_STRING=`bootnode`

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

	deploy $ALL_IPs &&\
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
	PFACs=(`load_pre_fund_accounts`)

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
		for PFAC in "${PFACs[@]}"; do
			echo $PFAC
		done
		echo
		echo no
		echo $NETWORK_ID
		echo 2
		echo 2
		echo
	) >| /tmp/puppeth.json

	GENESIS_JSON=$NETWORK_NAME.json
	rm *.json ~/.puppeth/* /tmp/$GENESIS_JSON
	./build/bin/$PUPPETH_CMD --network=$NETWORK_NAME < /tmp/puppeth.json >/dev/null

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
			$SSH $SSH_USER@$IP "nohup $GETH --bootnodes $BOOTNODE_STRING --mine --unlock 0 --password <(echo password) --ethstats $IP:$ETHSTATS &>./geth.log &"
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
	$PSCP -h <(printf "%s\n" $IPs) -l ubuntu ./build/bin/$GETH_CMD /home/ubuntu/
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
