#!/bin/bash

# EDIT name and domain 
CONCOURSE_ENDPOINT=concourse.some-domain.com
CONCOURSE_TARGET=nsx-concourse
PIPELINE_NAME=install-pcf-with-nsx

alias fly-s="fly -t $CONCOURSE_TARGET set-pipeline -p $PIPELINE_NAME -c install-pcf-pipeline.yml -l params.yml"
alias fly-l="fly -t $CONCOURSE_TARGET containers | grep $PIPELINE_NAME"
alias fly-h="fly -t $CONCOURSE_TARGET hijack -b "

echo "Concourse target set to $CONCOURSE_ENDPOINT"
echo "Login using fly"
echo ""

fly --target $CONCOURSE_TARGET login --insecure --concourse-url https://${CONCOURSE_ENDPOINT} -n main
