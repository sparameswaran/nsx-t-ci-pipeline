#!/bin/bash

set -eu

export ROOT_DIR=`pwd`
source $ROOT_DIR/nsx-t-ci-pipeline/functions/copy_binaries.sh
source $ROOT_DIR/nsx-t-ci-pipeline/functions/check_versions.sh
source $ROOT_DIR/nsx-t-ci-pipeline/functions/generate_cert.sh
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

export NSX_MANAGER_CERT_ADDRESS=`cat /tmp/complete_nsx_manager_cert.log \
                        | grep Subject | grep "CN=" \
                        | tr , '\n' | grep 'CN=' \
                        | sed -e 's/.* CN=//' `

echo "Fully qualified domain name for NSX Manager: $NSX_API_MANAGER"
echo "Host name associated with NSX Manager cert: $NSX_MANAGER_CERT_ADDRESS"

# Get all certs from the nsx manager
openssl s_client -host $NSX_API_MANAGER \
                 -port 443 -prexit -showcerts \
                 </dev/null 2>/dev/null  \
                 >  /tmp/nsx_manager_all_certs.log

# Get the very last CA cert from the showcerts result
cat /tmp/nsx_manager_all_certs.log \
                  |  awk '/BEGIN /,/END / {print }' \
                  | tail -50                        \
                  |  awk '/BEGIN /,/END / {print }' \
                  >  /tmp/nsx_manager_cacert.log

# Strip newlines and replace them with \r\n
cat /tmp/nsx_manager_cacert.log | tr '\n' '#'| sed -e 's/#/\r\n/g'   > /tmp/nsx_manager_edited_cacert.log
export NSX_API_CA_CERT=$(cat /tmp/nsx_manager_edited_cacert.log)


check_bosh_version
check_available_product_version "pivotal-container-service"

if [ "$PKS_T0_ROUTER_NAME" == "" \
     -o "$PKS_CONTAINER_IP_BLOCK_NAME" == ""  \
     -o "$PKS_EXTERNAL_IP_POOL_NAME" == "" ]; then

   echo "The name of T0 Router or PKS Container IP block or the External IP pool are empty!!"
   echo "These need to be filled in to proceed with PKS tile config. Exiting !!"
   exit 1

   if [[ "$PRODUCT_VERSION" =~ ^1.0 ]]; then
     echo ""
   elif "$PKS_NODES_IP_BLOCK_NAME" == "" ]; then
     echo "The PKS node ip block name is empty!!"
     echo "These need to be filled in to proceed with PKS tile config. Exiting !!"
     exit 1
   fi
fi

export PKS_T0_ROUTER_ID=$(curl \
      -k -u "$NSX_API_USER:$NSX_API_PASSWORD" \
      https://$NSX_API_MANAGER:443/api/v1/logical-routers \
      2>/dev/null \
      | jq -r --arg search_name $PKS_T0_ROUTER_NAME '.results[] | select ( .display_name | contains($search_name) ) | .id ' )
if [ "$PKS_T0_ROUTER_ID" == "" -o "$PKS_T0_ROUTER_ID" == "null" ]; then
  echo "Error: Unable to find T0 Router with name: $PKS_T0_ROUTER_NAME in NSX Mgr"
  echo "Exiting !!"
  exit 1
fi

export PKS_EXTERNAL_IP_POOL_ID=$(curl \
      -k -u "$NSX_API_USER:$NSX_API_PASSWORD" \
      https://$NSX_API_MANAGER:443/api/v1/pools/ip-pools \
      2>/dev/null \
      | jq -r --arg search_name $PKS_EXTERNAL_IP_POOL_NAME '.results[] | select ( .display_name | contains($search_name) ) | .id ' )
if [ "$PKS_EXTERNAL_IP_POOL_ID" == "" -o "$PKS_EXTERNAL_IP_POOL_ID" == "null" ]; then
  echo "Error: Unable to find PKS External Pool with name: $PKS_EXTERNAL_IP_POOL_NAME in NSX Mgr"
  echo "Exiting !!"
  exit 1
fi

export PKS_CONTAINER_IP_BLOCK_ID=$(curl \
      -k -u "$NSX_API_USER:$NSX_API_PASSWORD" \
      https://$NSX_API_MANAGER:443/api/v1/pools/ip-blocks \
      2>/dev/null \
      | jq -r --arg search_name $PKS_CONTAINER_IP_BLOCK_NAME '.results[] | select ( .display_name | contains($search_name) ) | .id ' )
if [ "$PKS_CONTAINER_IP_BLOCK_ID" == "" -o "$PKS_CONTAINER_IP_BLOCK_ID" == "null" ]; then
  echo "Error: Unable to find PKS Container IP Block with name: $PKS_CONTAINER_IP_BLOCK_NAME in NSX Mgr"
  echo "Exiting !!"
  exit 1
fi

if [ "$PKS_NODES_IP_BLOCK_NAME" != "" ]; then
  export PKS_NODES_IP_BLOCK_ID=$(curl \
        -k -u "$NSX_API_USER:$NSX_API_PASSWORD" \
        https://$NSX_API_MANAGER:443/api/v1/pools/ip-blocks \
        2>/dev/null \
        | jq -r --arg search_name $PKS_NODES_IP_BLOCK_NAME '.results[] | select ( .display_name | contains($search_name) ) | .id ' )
  if [ "$PKS_NODES_IP_BLOCK_ID" == "" -o "$PKS_NODES_IP_BLOCK_ID" == "null" ]; then
    echo "Error: Unable to find Node IP Block with name: $PKS_NODES_IP_BLOCK_NAME in NSX Mgr"
    echo "Exiting !!"
    exit 1
  fi
fi

if [ -z "$PKS_SSL_CERT"  -o  "null" == "$PKS_SSL_CERT" ]; then
  domains=(
    "*.${PKS_SYSTEM_DOMAIN}"
    "*.api.${PKS_SYSTEM_DOMAIN}"
    "*.uaa.${PKS_SYSTEM_DOMAIN}"
  )

  certificates=$(generate_cert "${domains[*]}")
  export PKS_SSL_CERT=`echo $certificates | jq --raw-output '.certificate'`
  export PKS_SSL_PRIVATE_KEY=`echo $certificates | jq --raw-output '.key'`
fi


om-linux \
    -t https://$OPSMAN_DOMAIN_OR_IP_ADDRESS \
    -u $OPSMAN_USERNAME \
    -p $OPSMAN_PASSWORD \
    -k stage-product \
    -p $PRODUCT_NAME \
    -v $PRODUCT_VERSION

check_staged_product_guid "pivotal-container-service-"

pks_network=$(
  jq -n \
    --arg pks_deployment_network_name "$PKS_DEPLOYMENT_NETWORK_NAME" \
    --arg pks_cluster_service_network_name "$PKS_CLUSTER_SERVICE_NETWORK_NAME" \
    --arg other_azs "$PKS_NW_AZS" \
    --arg singleton_az "$PKS_SINGLETON_JOB_AZ" \
    '
    {
      "network": {
        "name": $pks_deployment_network_name
      },
      "service_network": {
        "name": $pks_cluster_service_network_name
      },
      "other_availability_zones": ($other_azs | split(",") | map({name: .})),
      "singleton_availability_zone": {
        "name": $singleton_az
      }
    }
   '
)

om-linux \
  -t https://$OPSMAN_DOMAIN_OR_IP_ADDRESS \
  -u $OPSMAN_USERNAME \
  -p $OPSMAN_PASSWORD \
  --skip-ssl-validation \
  configure-product \
  --product-name pivotal-container-service \
  --product-network "$pks_network"

echo "Finished configuring network properties"

  pks_syslog_properties=$(
    jq -n \
    --arg pks_syslog_enabled "$PKS_SYSLOG_MIGRATION_ENABLED" \
    --arg pks_syslog_address "$PKS_SYSLOG_ADDRESS" \
    --arg pks_syslog_port "$PKS_SYSLOG_PORT" \
    --arg pks_syslog_transport_protocol "$PKS_SYSLOG_TRANSPORT_PROTOCOL" \
    --arg pks_syslog_tls_enabled "$PKS_SYSLOG_TLS_ENABLED" \
    --arg pks_syslog_peer "$PKS_SYSLOG_PEER" \
    --arg pks_syslog_ca_cert "$PKS_SYSLOG_CA_CERT" \
      '

      # Syslog
      if $pks_syslog_enabled == "enabled" then
        {
          ".properties.syslog_selector": {
            "value": "enabled"
          },
          ".properties.syslog_selector.enabled.address": {
            "value": $pks_syslog_address
          }, 
          ".properties.syslog_selector.enabled.port": {
            "value": $pks_syslog_port
          },
          ".properties.syslog_selector.enabled.transport_protocol": {
            "value": $pks_syslog_transport_protocol
          },
          ".properties.syslog_selector.enabled.tls_enabled": {
            "value": $pks_syslog_tls_enabled
          },
          ".properties.syslog_selector.enabled.permitted_peer": {
            "value": $pks_syslog_peer
          },
          ".properties.syslog_selector.enabled.ca_cert": {
            "value": $pks_syslog_ca_cert
          }
        }
      else
        {
          ".properties.syslog_selector": {
            "value": "disabled"
          }
        }
      end
      '
  )


om-linux \
  -t https://$OPSMAN_DOMAIN_OR_IP_ADDRESS \
  -u $OPSMAN_USERNAME \
  -p $OPSMAN_PASSWORD \
  --skip-ssl-validation \
  configure-product \
  --product-name pivotal-container-service \
  --product-properties "$pks_syslog_properties"
echo "Finished configuring syslog properties"

# Check if product is older 1.0 or not
if [[ "$PRODUCT_VERSION" =~ ^1.0 ]]; then
  product_version=1.0
  echo ""
  echo "Starting configuration of PKS v1.0 properties"
  source $ROOT_DIR/nsx-t-ci-pipeline/tasks/config-pks/config-pks-1.0.sh
else
  product_version=1.1
  echo ""
  echo "Starting configuration of PKS v1.1+ properties"
  source $ROOT_DIR/nsx-t-ci-pipeline/tasks/config-pks/config-pks-superuser.sh
  source $ROOT_DIR/nsx-t-ci-pipeline/tasks/config-pks/config-pks-1.1.sh
fi

echo ""
echo "Finished configuring PKS Tile"
