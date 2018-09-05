#!/bin/bash

set -eu
chmod +x om/om-linux
export PATH:$PATH:/om
echo "Apply changes"

om-linux \
	--target "https://${OPSMAN_DOMAIN_OR_IP_ADDRESS}" \
	--skip-ssl-validation \
	--username "${OPSMAN_USERNAME}" \
	--password "${OPSMAN_PASSWORD}" \
	apply-changes \
	--ignore-warnings
