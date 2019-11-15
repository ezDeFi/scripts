#!/bin/bash
#Config Gonex Download link
GONEX_RELEASE=https://github.com/nextyio/gonex/releases/download/v3.1.1/gonex-3.1.1.gz
GONEXSTATS=nty2018@stats.nexty.io
ENODEs="enode://286d9b5690f0c2a322f5bf31775fb06f2992d3de001d9a9ab62513b813d48f5607a959a8e499f37153f2e78c74c751f1756e56588d02d032c1c4a92c002229ba@35.187.233.103:33333
enode://f3a6df4d7a1c1566f54deb0449770a88403d03313911e08af88d312011de7234d4a6231073678bacbb93df036d5f48e5c419cf6a58cda7fff0a04d6786175c37@139.180.137.154:33333
enode://866fbc2c7dd95adc8db8ceb91442ea276a788c92cb3b755b4adac52d2012343e49a35e6194224960e0257cb466be657354a680dfef78b227090ea1a417aa5bee@52.74.133.33:33333"

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
