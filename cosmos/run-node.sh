#!/bin/bash

while true
do

# Logo

echo "========================================================================================================================"
curl -s https://raw.githubusercontent.com/StakeTake/script/main/logo.sh | bash
echo "========================================================================================================================"

# Menu

PS3='Select an action: '
options=(
"Install Node"
"Check Log"
"Check balance"
"Request tokens in website"
"Create Validator"
"Exit")
select opt in "${options[@]}"
do
case $opt in

"Install Node")
echo "============================================================"
echo "Install start"
echo "============================================================"
echo "Setup NodeName:"
echo "============================================================"
read NODENAME
echo "============================================================"
echo "Setup WalletName:"
echo "============================================================"
read WALLETNAME
echo export NODENAME=${NODENAME} >> $HOME/.bash_profile
echo export WALLETNAME=${WALLETNAME} >> $HOME/.bash_profile
echo export CHAIN_ID=evmos_9000-4 >> $HOME/.bash_profile
source ~/.bash_profile

#UPDATE APT
sudo apt update && sudo apt upgrade -y
sudo apt install curl tar wget clang pkg-config libssl-dev jq build-essential bsdmainutils git make ncdu unzip snapd -y

#INSTALL GO
wget https://golang.org/dl/go1.17.9.linux-amd64.tar.gz; \
rm -rv /usr/local/go; \
tar -C /usr/local -xzf go1.17.9.linux-amd64.tar.gz && \
rm -v go1.17.9.linux-amd64.tar.gz && \
echo "export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin" >> ~/.bash_profile && \
source ~/.bash_profile && \
go version

#INSTALL
git clone https://github.com/tharsis/evmos.git
cd evmos
git checkout tags/v3.0.0-beta1
make install
evmosd version

evmosd config chain-id evmos_9000-4

rm ~/.evmosd/config/genesis.json
evmosd init $NODENAME --chain-id $CHAIN_ID


rm ~/.evmosd/config/genesis.json
wget -P ~/.evmosd/config https://github.com/tharsis/testnets/raw/main/evmos_9000-4/genesis.zip
cd ~/.evmosd/config
unzip genesis.zip
rm genesis.zip
PEERS=`curl -sL https://raw.githubusercontent.com/tharsis/testnets/main/evmos_9000-4/peers.txt | sort -R | head -n 10 | awk '{print $1}' | paste -s -d, -`
sed -i.bak -e "s/^persistent_peers *=.*/persistent_peers = \"$PEERS\"/" ~/.evmosd/config/config.toml
SEEDS=`curl -sL https://raw.githubusercontent.com/tharsis/testnets/main/evmos_9000-4/seeds.txt | awk '{print $1}' | paste -s -d, -`
sed -i.bak -e "s/^seeds =.*/seeds = \"$SEEDS\"/" ~/.evmosd/config/config.toml


echo "============================================================"
echo "Be sure to write down the mnemonic!"
echo "============================================================"
#WALLET
evmosd keys add $WALLETNAME

external_address=$(wget -qO- eth0.me)
sed -i.bak -e "s/^external_address *=.*/external_address = \"$external_address:26656\"/" $HOME/.evmosd/config/config.toml

sudo tee /etc/systemd/system/evmosd.service > /dev/null <<EOF
[Unit]
Description=Evmos
After=network.target
[Service]
Type=simple
User=$USER
ExecStart=$(which evmosd) start
Restart=on-failure
RestartSec=10
LimitNOFILE=65535
[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable evmosd


evmosd unsafe-reset-all
cd
wget https://raw.githubusercontent.com/StakeTake/guidecosmos/main/evmos/evmos_9000-4/addrbook.json -O ~/.evmosd/config/addrbook.json
rm -rf ~/.evmosd/data; \
wget -O - http://144.76.224.246:8000/archive.tar.gz | tar xf -
mv $HOME/root/.evmosd/data/ $HOME/.evmosd
rm -rf $HOME/root
sudo systemctl restart evmosd

break
;;

"Check Log")

journalctl -u evmosd -f -o cat

break
;;


"Check balance")
evmosd q bank balances $WALLETNAME
break
;;

"Create Validator")
evmosd tx staking create-validator \
  --amount 1000000000000000000atevmos \
  --pubkey=$(evmosd tendermint show-validator) \
  --moniker=$NODENAME \
  --chain-id=$CHAIN_ID \
  --commission-rate="0.10" \
  --commission-max-rate="0.20" \
  --commission-max-change-rate="0.01" \
  --min-self-delegation="1000000" \
  --gas=300000 \
  --gas-prices="0.025atevmos" \
  --from=$WALLETNAME \
  -y
  
break
;;

"Request tokens in website")
echo "========================================================================================================================"
echo "In order to receive tokens, you need to go to the website https://faucet.evmos.dev/
and request your address wallet. If the faucet does not work, try asking for tokens in the validator discord channel"
echo "========================================================================================================================"

break
;;

"Exit")
exit
;;
*) echo "invalid option $REPLY";;
esac
done
done
