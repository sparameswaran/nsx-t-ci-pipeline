#!/bin/bash

set -eux

export CONFIG="${PWD}/integration-config/integration_config.json"
echo $CONFIG

echo "Moving cf-routing-acceptance-tests onto the gopath..."
mkdir -p $GOPATH
cp -R routing-release/src $GOPATH

go install github.com/onsi/ginkgo/ginkgo

cd ${GOPATH}/src/code.cloudfoundry.org/routing-acceptance-tests

packages=("http_routes")
for i in "${packages[@]}"
do
  ginkgo -r "$i" \
    -keepGoing \
    -randomizeAllSpecs \
    -skipPackage=helpers \
    -slowSpecThreshold=120 \
    -nodes="12"
done
