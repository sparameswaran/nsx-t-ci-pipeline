#!/bin/bash

set -eu

export ROOT_DIR=`pwd`
source $ROOT_DIR/nsx-t-ci-pipeline/functions/copy_binaries.sh
source $ROOT_DIR/nsx-t-ci-pipeline/functions/check_versions.sh
source $ROOT_DIR/nsx-t-ci-pipeline/functions/generate_cert.sh
source $ROOT_DIR/nsx-t-ci-pipeline/functions/yaml2json.sh

openssl s_client  -servername $NSX_API_MANAGERS \
                  -connect ${NSX_API_MANAGERS}:443 \
                  </dev/null 2>/dev/null \
                  | openssl x509 -text \
                  >  /tmp/complete_nsx_manager_cert.log

NSX_MANAGER_CERT_ADDRESS=`cat /tmp/complete_nsx_manager_cert.log \
                        | grep Subject | grep "CN=" \
                        | awk '{print $NF}' \
                        | sed -e 's/CN=//g' `

echo "Fully qualified domain name for NSX Manager: $NSX_API_MANAGERS"
echo "Host name associated with NSX Manager cert: $NSX_MANAGER_CERT_ADDRESS"

# Get all certs from the nsx manager
openssl s_client -host $NSX_API_MANAGERS \
                 -port 443 -prexit -showcerts \
                 </dev/null 2>/dev/null  \
                 >  /tmp/nsx_manager_all_certs.log

# Get the very last CA cert from the showcerts result
cat /tmp/nsx_manager_all_certs.log \
                  |  awk '/BEGIN /,/END / {print }' \
                  | tail -30                        \
                  |  awk '/BEGIN /,/END / {print }' \
                  >  /tmp/nsx_manager_cacert.log

# Strip newlines and replace them with \r\n
cat /tmp/nsx_manager_cacert.log | tr '\n' '#'| sed -e 's/#/\r\n/g'   > /tmp/nsx_manager_edited_cacert.log
export NSX_API_CA_CERT=$(cat /tmp/nsx_manager_edited_cacert.log)

if [ "$NSX_PRODUCT_TILE_NAME" == "" ]; then
  export NSX_PRODUCT_TILE_NAME="nsx-cf-cni"
fi


nsx_t_properties=$(
  jq -n \
    --arg nsx_api_managers "$NSX_API_MANAGERS" \
    --arg nsx_api_user "$NSX_API_USER" \
    --arg nsx_api_password "$NSX_API_PASSWORD" \
    --arg nsx_api_ca_cert "$NSX_API_CA_CERT" \
    --arg subnet_prefix "$NSX_SUBNET_PREFIX" \
    --arg external_subnet_prefix "$NSX_EXTERNAL_SUBNET_PREFIX" \
    --arg log_dropped_traffic "$NSX_LOG_DROPPED_TRAFFIC" \
    --arg enable_snat "$NSX_ENABLE_SNAT" \
    --arg foundation_name "$NSX_FOUNDATION_NAME" \
    --arg ncp_debug_log "$NSX_NCP_DEBUG_LOG" \
    --arg nsx_auth "$NSX_AUTH_TYPE" \
    --arg nsx_client_cert_cert "$NSX_CLIENT_CERT_CERT" \
    --arg nsx_client_cert_private_key "$NSX_CLIENT_CERT_PRIVATE_KEY" \
    '
    {
      ".properties.nsx_api_managers": {
        "value": $nsx_api_managers
      },      
      ".properties.nsx_api_ca_cert": {
        "value": $nsx_api_ca_cert
      },
      ".properties.foundation_name": {
        "value": $foundation_name
      },
      ".properties.subnet_prefix": {
        "value": $subnet_prefix
      },
      ".properties.log_dropped_traffic": {
        "value": $log_dropped_traffic
      },
      ".properties.enable_snat": {
        "value": $enable_snat
      },
      ".properties.ncp_debug_log": {
        "value": $ncp_debug_log
      }
    }
    
    +


    if $nsx_auth == "simple" then
    {
      ".properties.nsx_auth": { 
        "value" : "simple" 
      },
      ".properties.nsx_auth.simple.nsx_api_user":  { 
        "value": $nsx_api_user 
      },
      ".properties.nsx_auth.simple.nsx_api_password":  { 
        "value": { 
          "secret": $nsx_api_password 
        } 
      }
    }
    else
    {
      ".properties.nsx_auth": { 
        "value": "client_cert" 
      },
      ".properties.nsx_auth.client_cert.nsx_api_client_cert": { 
        "value": {
          "cert_pem": $nsx_client_cert_cert, 
          "private_key_pem": $nsx_client_cert_private_key 
        }
      }
    }
    end
    '
)


TILE_RELEASE=$(om-linux -t https://$OPSMAN_DOMAIN_OR_IP_ADDRESS \
                          -u $OPSMAN_USERNAME \
                          -p $OPSMAN_PASSWORD \
                          -k available-products \
                          | grep -e "nsx-cf-cni\|VMware-NSX-T")

PRODUCT_NAME=`echo $TILE_RELEASE | cut -d"|" -f2 | tr -d " "`
PRODUCT_VERSION=`echo $TILE_RELEASE | cut -d"|" -f3 | tr -d " "`

om-linux -t https://$OPSMAN_DOMAIN_OR_IP_ADDRESS \
      -u $OPSMAN_USERNAME \
      -p $OPSMAN_PASSWORD \
      -k stage-product \
      -p $PRODUCT_NAME \
      -v $PRODUCT_VERSION


om-linux \
  --target https://$OPSMAN_DOMAIN_OR_IP_ADDRESS \
  --username $OPSMAN_USERNAME \
  --password $OPSMAN_PASSWORD \
  --skip-ssl-validation \
  configure-product \
  --product-name $PRODUCT_NAME \
  --product-properties "$nsx_t_properties"



check_available_product_version "VMware-NSX-T"
if [[ "$PRODUCT_VERSION" =~ "2.1.0" ]]; then
  return
fi

if [[ "$PRODUCT_VERSION" =~ "2.1.3" ]]; then
  # Set .properties.overlay_tz
  # Set .properties.tier0_router
  # Set .properties.container_ip_blocks[index][name]
  # Set .properties.container_ip_blocks[index][cidr] -> optional

  # Convert yaml to json using yaml2json function
  # strip off the tags
  container_ip_blocks=$(echo "$NSX_T_CONTAINER_IP_BLOCK_SPEC" \
                      | yaml2json \
                      | jq '.container_ip_blocks' \
                      | jq 'del(.[].tags)' )

  nsx_t_additional_configs=$(
    jq -n \
      --arg nsx_overlay_tz "$NSX_T_OVERLAY_TRANSPORT_ZONE" \
      --arg nsx_tier0_router "$NSX_T_T0ROUTER_NAME" \
      --arg container_ip_blocks "$container_ip_blocks" \
      '
      {
        ".properties.overlay_tz": {
          "value": $nsx_overlay_tz
        },      
        ".properties.tier0_router": {
          "value": $nsx_tier0_router
        },
        ".properties.container_ip_blocks": {
          "value": {
              "$container_ip_blocks"
          }
        }
      }'
    )

  echo "Additional NSX 2.1.3 configs: ${nsx_t_additional_configs}"

  om-linux \
    --target https://$OPSMAN_DOMAIN_OR_IP_ADDRESS \
    --username $OPSMAN_USERNAME \
    --password $OPSMAN_PASSWORD \
    --skip-ssl-validation \
    configure-product \
    --product-name $PRODUCT_NAME \
    --product-properties "${nsx_t_additional_configs}"

fi
