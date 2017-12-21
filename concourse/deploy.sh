#!/bin/bash

CUR_DIR=$(dirname $BASH_SOURCE)
export SCRIPTS_DIR=$(cd $CUR_DIR/../scripts && pwd)

source $SCRIPTS_DIR/setup.sh
source $BOSH_DIR/setup.sh

# Following set when sourcing setup.sh
# BOSH_ENV=bosh-test-env
# CONCOURSE_DEPLOYMENT=concourse-test

export CONCOURSE_VERSION="3.6.0"
export GARDEN_RUNC_VERSION="1.9.0"
export STEMCELL_VERSION="3468.1"

#bosh -e $BOSH_ENV update-cloud-config bosh/vsphere/cloud-config.yml 
#bosh -e $BOSH_ENV upload-release \
#   https://github.com/concourse/concourse/releases/download/v${CONCOURSE_VERSION}/garden-runc-${GARDEN_RUNC_VERSION}.tgz
#bosh -e $BOSH_ENV upload-release \
#   https://github.com/concourse/concourse/releases/download/v${CONCOURSE_VERSION}/concourse-${CONCOURSE_VERSION}.tgz

bosh -e $BOSH_ENV upload-stemcell \
 https://s3.amazonaws.com/bosh-core-stemcells/vsphere/bosh-stemcell-${STEMCELL_VERSION}-vsphere-esxi-ubuntu-trusty-go_agent.tgz

bosh -e $BOSH_ENV -d $CONCOURSE_DEPLOYMENT  \
                     deploy concourse-manifest.yml \
                     -l concourse-params.yml \
                     --vars-store=creds.yml
