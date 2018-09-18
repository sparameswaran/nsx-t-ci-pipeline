#!/bin/bash

set -eu

export ROOT_DIR=`pwd`
export TASKS_DIR=$(dirname $BASH_SOURCE)
export PIPELINE_DIR=$(cd $TASKS_DIR/../../ && pwd)
export PYTHON_LIB_DIR=$(cd $PIPELINE_DIR/python && pwd)

source $ROOT_DIR/nsx-t-ci-pipeline/functions/yaml2json.sh
source $ROOT_DIR/nsx-t-ci-pipeline/functions/check_null_variables.sh

# Check if NSX Manager is accessible before pulling down its cert
set +e
curl -kv https://${NSX_API_MANAGER} >/dev/null 2>/dev/null
connect_status=$?
set -e

if [ "$connect_status" != "0" ]; then
  echo "Error in connecting to ${NSX_API_MANAGER} over 443, please check and correct the NSX Mgr address or dns entries and retry!!"
  exit -1
fi

openssl s_client  -servername $NSX_API_MANAGER \
                  -connect ${NSX_API_MANAGER}:443 \
                  </dev/null 2>/dev/null \
                  | openssl x509 -text \
                  >  /tmp/complete_nsx_manager_cert.log

NSX_MANAGER_CERT_ADDRESS=`cat /tmp/complete_nsx_manager_cert.log \
                        | grep Subject | grep "CN=" \
                        | tr , '\n' | grep 'CN=' \
                        | sed -e 's/.* CN=//g' `

echo "Fully qualified domain name for NSX Manager: $NSX_API_MANAGER"
echo "Host name associated with NSX Manager cert: $NSX_MANAGER_CERT_ADDRESS"

error=""
if [ "$NSX_API_MANAGER" != "$NSX_MANAGER_CERT_ADDRESS" ]; then
  echo "Error!! Specified NSX_API_MANAGER FQDN $NSX_API_MANAGER not matching Cert's Common Name: $NSX_MANAGER_CERT_ADDRESS"
  error="true"
fi

set +e
check_dns_lookup=$(nslookup api.${PKS_SYSTEM_DOMAIN})
if [ "$?" != "0" ]; then
  echo "Warning!! Unable to resolve api.${PKS_SYSTEM_DOMAIN}"
  echo "Proceeding with the assumption that api.${PKS_SYSTEM_DOMAIN} would resolve to a Loadbalancer VIP redirecting to GoRouter ultimately"
  echo ""
else
  resolved_ip=$(echo $check_dns_lookup | grep -A1 ${PKS_SYSTEM_DOMAIN} | awk '{print $NF}' )
  echo "Resolved api.${PKS_SYSTEM_DOMAIN} to $resolved_ip"
fi

set -e

echo ""

export VALIDATE_FOR_PAS=false
python $PYTHON_LIB_DIR/nsx_t_validator.py
STATUS=$?

exit $STATUS
