#!/bin/bash
set -eu

ADMIN_PASSWORD=$(cat integration-config/integration_config.json | jq -r .admin_password)
ADMIN_USER=$(cat integration-config/integration_config.json | jq -r .admin_user)
API=$(cat integration-config/integration_config.json | jq -r .api)
cf api --skip-ssl-validation $API
cf login -s system -o system -u $ADMIN_USER -p $ADMIN_PASSWORD

cf enable-feature-flag diego_docker
