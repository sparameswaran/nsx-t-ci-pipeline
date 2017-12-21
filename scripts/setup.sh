#!/bin/bash

SCRIPTS_DIR=$(dirname $BASH_SOURCE)
export SCRIPTS_DIR=$(cd $SCRIPTS_DIR && pwd)

base_dir=$(basename $SCRIPTS_DIR)
if [ "$base_dir" == "bosh" ]; then
	export SCRIPTS_DIR=$(cd $SCRIPTS_DIR/../../scripts && pwd)
fi

export CONCOURSE_DIR=$SCRIPTS_DIR/../concourse
if [ ! -d $CONCOURSE_DIR ]; then
  echo "Target directory $CONCOURSE_DIR does not exist!!"
  echo "Exiting!!"
  return
fi

export BOSH_DIR=$CONCOURSE_DIR/bosh

echo "Concourse dir set to : $CONCOURSE_DIR"
echo "Bosh dir set to : $BOSH_DIR"
echo ""

# Default deployment name
export BOSH_ENV=bosh-concourse
export CONCOURSE_DEPLOYMENT=concourse-test

echo "BOSH Env name: $BOSH_ENV"
echo "Concourse Deployment name: $CONCOURSE_DEPLOYMENT"
echo ""

echo "Notes:"
echo "If this is the first time, setup Bosh director followed by deployment of concourse"
echo "Skip below steps if there is already a concourse install up and running"
echo ""
echo "Go to the concourse/bosh directory and edit the configurations in vsphere-config.yml and vsphere/cloud-config.yml"
echo "Then run bosh-create-env.sh under it"
echo ""
echo "Then go to the concourse directory and edit the configurations in concourse-params.yml"
echo "Then run deploy.sh under it"
