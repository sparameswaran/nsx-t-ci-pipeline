#!/bin/bash
set -eu
export ROOT_DIR=`pwd`
source $ROOT_DIR/nsx-t-ci-pipeline/functions/copy_binaries.sh
source $ROOT_DIR/nsx-t-ci-pipeline/functions/check_versions.sh
source $ROOT_DIR/nsx-t-ci-pipeline/functions/generate_cert.sh
source $ROOT_DIR/nsx-t-ci-pipeline/functions/yaml2json.sh
source $ROOT_DIR/nsx-t-ci-pipeline/functions/check_null_variables.sh

root=$(pwd)

export GOVC_TLS_CA_CERTS=/tmp/vcenter-ca.pem
echo "$GOVC_CA_CERT" > $GOVC_TLS_CA_CERTS

source "${root}/nsx-t-ci-pipeline/functions/check_opsman_available.sh"

opsman_available=$(check_opsman_available $OPSMAN_DOMAIN_OR_IP_ADDRESS)
if [[ $opsman_available == "available" ]]; then

  # Check for pending changes before starting deletion
  pending_changes=$( om-linux \
    -f json \
    --target "https://${OPSMAN_DOMAIN_OR_IP_ADDRESS}" \
    --skip-ssl-validation \
    --client-id "${OPSMAN_CLIENT_ID}" \
    --client-secret "${OPSMAN_CLIENT_SECRET}" \
    --username "$OPSMAN_USERNAME" \
    --password "$OPSMAN_PASSWORD" \
    --connect-timeout 3200 --request-timeout 3200 \
    pending-changes
    )
  # If there are any pending changes, then revert them before starting deletion
  if [ "$pending_changes" != '[]' ]; then
    om-linux \
      -f json \
      --target "https://${OPSMAN_DOMAIN_OR_IP_ADDRESS}" \
      --skip-ssl-validation \
      --client-id "${OPSMAN_CLIENT_ID}" \
      --client-secret "${OPSMAN_CLIENT_SECRET}" \
      --username "$OPSMAN_USERNAME" \
      --password "$OPSMAN_PASSWORD" \
      --connect-timeout 3200 --request-timeout 3200 \
      revert-staged-changes
  fi

  om-linux \
    --target "https://${OPSMAN_DOMAIN_OR_IP_ADDRESS}" \
    --skip-ssl-validation \
    --client-id "${OPSMAN_CLIENT_ID}" \
    --client-secret "${OPSMAN_CLIENT_SECRET}" \
    --username "$OPSMAN_USERNAME" \
    --password "$OPSMAN_PASSWORD" \
    --connect-timeout 3200 --request-timeout 3200 \
    delete-installation
fi

# Delete Active OpsMan
resource_pool_path=$(govc find . -name ${GOVC_RESOURCE_POOL} | grep -i resource )
possible_opsmans=$(govc find $resource_pool_path -type m -guest.ipAddress ${OPSMAN_IP} -runtime.powerState poweredOn)

for opsman in ${possible_opsmans}; do
  network="$(govc vm.info -r=true -json ${opsman} | jq -r '.VirtualMachines[0].Guest.Net[0].Network')"
  if [[ ${network} == ${GOVC_NETWORK} || ${network} == "" ]]; then
    echo "Powering off and removing ${opsman}..."
    set +e
    govc vm.power -vm.ipath=${opsman} -off
    set -e
    govc vm.destroy -vm.ipath=${opsman}
  fi
done
