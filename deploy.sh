#!/bin/bash
# Config Gonex Download link
# Run this command from terminal to deploy gonex
# wget -O - https://raw.githubusercontent.com/nextyio/scripts/master/deploy.sh | bash
# Or run this command if you want to update binary only
# wget -O - https://raw.githubusercontent.com/nextyio/scripts/master/deploy.sh | bash -s download

GONEX_RELEASE=https://github.com/nextyio/gonex/releases/download/v3.1.4/gonex-3.1.4.gz
GONEXSTATS=nty2018@stats.nexty.io
ENODEs="enode://97da1591ac141868c4eaef2428bb5bc308e5a6ba8d7e9e2165a307a0e21b61943e38f9231f7a34c05c8fbc4ca24e76a56ec35296c910508e80e3c89db8e63f91@212.83.148.104:30303
enode://06029d8c1c6a951c8878f7e02ba5a1128336d6f0f013ca77c2c83c52b15ffc0b2efe3898525e47586c1c24cd92d8f792f7853c4d34efc31861420f230ea4746f@23.108.65.227:30303
enode://3b8faa9989aa2301bdce62f6f1ae623a147e213e357e564391921e86767803c2a017b73f4c549728a11274bb8f3ec0398ced913be05ce6d82245c035741f3ac3@104.237.11.123:30303"

if [ "${USER}" = "root" ]; then
    REMOTE_HOME_PATH="/root"
    USER_PARAM=""
else
    REMOTE_HOME_PATH="/home/${USER}"
    USER_PARAM="--user"
fi

function download {
    systemctl $USER_PARAM stop gonex
    rm -rf $REMOTE_HOME_PATH/nexty/gonex
    mkdir -p $REMOTE_HOME_PATH/nexty/.gonex
    wget -O $REMOTE_HOME_PATH/nexty/gonex.gz $GONEX_RELEASE
    gunzip -f $REMOTE_HOME_PATH/nexty/gonex.gz
    chmod +x $REMOTE_HOME_PATH/nexty/gonex
    systemctl $USER_PARAM start gonex
}

function account {
	ID=$1
	IP=${IPs[$ID]}
	ACC=$($REMOTE_HOME_PATH/nexty/gonex account list | grep 'Account #0:')
	if [ -z "$ACC" ]; then
		return
	fi
	ACC=${ACC##*\{}
	ACC=${ACC%%\}*}
    echo "$(tput setaf 3)Use following account as signer address when joining Nexty Governance:$(tput sgr0)"
	echo "$(tput setaf 6)0x"$ACC"$(tput sgr0)"
}

# create account
function create {
	ACC=$(account)
	if [ ! -z "$ACC" ]; then
		echo "$(tput setaf 3)This node already has an account:$(tput sgr0)"
		echo "	Account:	"$ACC
		return
	fi
	echo "About to create a new account with:"
	PASSWORD=password
	read -s -p "$(tput setaf 3)	Keystore password: $(tput sgr0)" PASS
	if [ ! -z $PASS ]; then
		PASSWORD=$PASS
	fi
    echo $PASSWORD > $REMOTE_HOME_PATH/nexty/.kspw
	unset PASSWORD

	ACC=$($REMOTE_HOME_PATH/nexty/gonex account new --password="$REMOTE_HOME_PATH/nexty/.kspw")
	ACC=${ACC##*\{}
	ACC=${ACC%%\}*}
	SIGNERADDRs[$ID]="0x"$ACC
	echo "	Account:	"$ACC
}

function jsonify_enodes {
	JSONENODEs="["
	ARRAY_ENODEs=($ENODEs)
	for ENODE in "${ARRAY_ENODEs[@]::${#ARRAY_ENODEs[@]}-1}"; do
		JSONENODEs=$JSONENODEs'"'$ENODE'",'
	done
	JSONENODEs=$JSONENODEs'"'${ARRAY_ENODEs[@]: -1:1}'"]'
}

function deploy {
    #Download Gonex
    mkdir -p $REMOTE_HOME_PATH/nexty/.gonex
    download
    read -p "$(tput setaf 3)Please Enter Name of Your Sealer (Allow 0-9 a-Z . _ -): $(tput sgr0)" NAME_INPUT
    NAME=$(echo $NAME_INPUT | sed 's/[^[:alnum:]._-]//g')
    echo $NAME > $REMOTE_HOME_PATH/nexty/name
    #Create an account
    create
    #Create gonex.toml
    jsonify_enodes
    echo "[Node.P2P]
    StaticNodes = $JSONENODEs" > $REMOTE_HOME_PATH/nexty/gonex.toml
    #Create gonex.sh
	echo "mkdir -p $REMOTE_HOME_PATH/nexty/logs"$'\n'"TS=\$(date +%Y.%m.%d-%H.%M.%S)"$'\n'"mv $REMOTE_HOME_PATH/nexty/gonex.log $REMOTE_HOME_PATH/nexty/logs/\$TS.log"$'\n'"$REMOTE_HOME_PATH/nexty/gonex --gasprice=0 --targetgaslimit=42000000 --txpool.pricelimit=0 --networkid=66666 --config=$REMOTE_HOME_PATH/nexty/gonex.toml --mine --unlock=0 --password=$REMOTE_HOME_PATH/nexty/.kspw --ethstats=$NAME:$GONEXSTATS &>$REMOTE_HOME_PATH/nexty/gonex.log" >| $REMOTE_HOME_PATH/nexty/gonex.sh
    chmod +x $REMOTE_HOME_PATH/nexty/gonex.sh
    #Create gonex.service
	echo "[Unit]
Description=Nexty go client

[Service]
Type=simple
Restart=on-failure
RestartSec=5s
WorkingDirectory=%h
ExecStart=/bin/bash -x $REMOTE_HOME_PATH/nexty/gonex.sh

[Install]
WantedBy=default.target" >| $REMOTE_HOME_PATH/nexty/gonex.service
    if [ "${USER}" = "root" ]; then
        cp $REMOTE_HOME_PATH/nexty/gonex.service /etc/systemd/system/
    fi
	echo "$(tput setaf 3)Enabling gonex service...$(tput sgr0)"
	systemctl daemon-reload
	systemctl $USER_PARAM enable --force $REMOTE_HOME_PATH/nexty/gonex.service
	loginctl enable-linger $USER

	#Start service
	echo "$(tput setaf 3)Start gonex service...$(tput sgr0)"
	systemctl $USER_PARAM restart gonex
	echo "Done!"
    account
}

if [ ! -z $1 ]; then
    $1
else
    deploy
fi
