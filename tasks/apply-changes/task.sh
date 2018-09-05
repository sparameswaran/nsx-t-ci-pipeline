#!/usr/bin/env bash

set -eu
chmod +x om/om-linux
export PATH="$PATH:$(pwd)/om"
echo "Apply changes"

om-linux \
	--target "https://${OPSMAN_DOMAIN_OR_IP_ADDRESS}" \
	--skip-ssl-validation \
	--username "${OPSMAN_USERNAME}" \
	--password "${OPSMAN_PASSWORD}" \
	--connect-timeout 3200 \
	--request-timeout 3200 \
	apply-changes \
	--ignore-warnings
