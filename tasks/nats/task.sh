#!/bin/bash

set -eu

export CONFIG="${PWD}/integration-config/integration_config.json"
echo $CONFIG

export NETWORK_STATS_FILE=$PWD/network-stats/stats.json

cd cf-networking
export GOPATH=$PWD

cd src/test/acceptance
export APPS_DIR=../../example-apps
ginkgo -r -v
