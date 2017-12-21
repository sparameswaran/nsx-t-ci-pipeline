#! /bin/bash

# command line used to deploy and upgrade vsphere bosh director
# BOSH_DIRECTOR_IP set in the vsphere-config.yml


if [ "$BOSH_DIR" != "" ]; then
  CUR_SCRIPT_DIR=$BOSH_DIR
else
  CUR_SCRIPT_DIR=$(dirname $BASH_SOURCE)
  CUR_SCRIPT_DIR=$(cd $CUR_SCRIPT_DIR && pwd)  
  export BOSH_DIR=$CUR_SCRIPT_DIR
fi

bosh create-env ./bosh.yml --state ./bosh-state.json \
								-o ./vsphere/cpi.yml \
								-o ./vsphere/resource-pool.yml \
								-l vsphere-config.yml \
								--vars-store ./creds.yml


if [ $? -nt 0 ]; then
    echo "Failure in creating bosh director setup... Exiting !!"
	exit 1
fi

# Set up login and cloud-config updates..
$BOSH_DIR/setup.sh