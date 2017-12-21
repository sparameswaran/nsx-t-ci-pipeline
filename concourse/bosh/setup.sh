#!/bin/bash

if [ "$BOSH_DIR" != "" ]; then
  CUR_SCRIPT_DIR=$BOSH_DIR
else
  CUR_SCRIPT_DIR=$(dirname $BASH_SOURCE)
  CUR_SCRIPT_DIR=$(cd $CUR_SCRIPT_DIR && pwd)  
  export BOSH_DIR=$CUR_SCRIPT_DIR
fi

export SCRIPTS_DIR=$(cd $BOSH_DIR/../../scripts && pwd)
source $SCRIPTS_DIR/setup.sh

# Get the Bosh Director IP from vsphere-config.yml
BOSH_DIRECTOR_IP=$(grep internal_ip $BOSH_DIR/vpshere-config.yml | awk '{print $2}' )
echo "Using Bosh Director IP: $BOSH_DIRECTOR_IP"

netcat_check=$(nc  -z -G 2 -w 3 -v $BOSH_DIRECTOR_IP 25555 &> /dev/null && echo "Online" || echo "Offline")
if [ "$netcat_check" == "Offline" ]; then
  echo "Errror: Unable to reach Bosh Director at $BOSH_DIRECTOR_IP:25555 !!"
  echo "Ensure Bosh Director is already up or created!"
  echo "Use $BOSH_DIR/bosh-create-env.sh to create it!"
  echo ""
  exit 1
fi

echo "Setting up Bosh Target : $TARGET against Director: $BOSH_DIRECTOR_IP with alias set to $BOSH_ENV"
echo ""

bosh int $CUR_SCRIPT_DIR/creds.yml --path /director_ssl/ca > $CUR_SCRIPT_DIR/ca-certs.yml
bosh int $CUR_SCRIPT_DIR/creds.yml --path /director_ssl/private_key > $CUR_SCRIPT_DIR/director-ssl-key.priv

bosh alias-env $BOSH_ENV -e $BOSH_DIRECTOR_IP --ca-cert $CUR_SCRIPT_DIR/ca-certs.yml

export BOSH_CLIENT=admin
export BOSH_CLIENT_SECRET=`bosh int $CUR_SCRIPT_DIR/creds.yml --path /admin_password`
export BOSH_CA_CERT=$CUR_SCRIPT_DIR/ca-certs.yml

bosh -e $BOSH_ENV --ca-cert $CUR_SCRIPT_DIR/ca-certs.yml login
bosh -e $BOSH_ENV update-cloud-config $BOSH_DIR/vsphere/cloud-config.yml

echo "Logged in and updated cloud-config"
echo ""
bosh -e $BOSH_ENV env
echo ""