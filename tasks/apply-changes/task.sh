#!/bin/bash

set -eu

echo "Apply changes"

om-linux \
  --target "https://${OPSMAN_DOMAIN_OR_IP_ADDRESS}" \
  --skip-ssl-validation \
  --username "${OPS_MGR_USR}" \
  --password "${OPS_MGR_PWD}" \
  apply-changes \
  --ignore-warnings
