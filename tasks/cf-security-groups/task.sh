#!/bin/bash
set -eu

ADMIN_PASSWORD=$(cat integration-config/integration_config.json | jq -r .admin_password)
ADMIN_USER=$(cat integration-config/integration_config.json | jq -r .admin_user)
API=$(cat integration-config/integration_config.json | jq -r .api)
cf api --skip-ssl-validation $API
cf login -s system -o system -u $ADMIN_USER -p $ADMIN_PASSWORD

# SABHA - 12/1/17
# NSX has issues around 0.0.0.0
# Use 0.0.0.1 as starting ip instead
cf create-security-group public_networks <(cat <<EOF
[
		{
			"destination": "0.0.0.1-9.255.255.255",
			"protocol": "all"
		},
		{
			"destination": "10.85.24.0-169.253.255.255",
			"protocol": "all"
		},
		{
			"destination": "169.255.0.0-172.15.255.255",
			"protocol": "all"
		},
		{
			"destination": "172.32.0.0-192.167.255.255",
			"protocol": "all"
		},
		{
			"destination": "192.169.0.0-255.255.255.255",
			"protocol": "all"
		}
	]
EOF
)
cf bind-staging-security-group public_networks
cf bind-running-security-group public_networks

cf create-security-group dns <(cat <<EOF
[
		{
			"destination": "0.0.0.0/0",
			"ports": "53",
			"protocol": "tcp"
		},
		{
			"destination": "0.0.0.0/0",
			"ports": "53",
			"protocol": "udp"
		}
	]
EOF
)

cf bind-staging-security-group dns
cf bind-running-security-group dns
