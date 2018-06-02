#!/bin/bash

set -eu

export ROOT_DIR=`pwd`
source $ROOT_DIR/nsx-t-ci-pipeline/functions/copy_binaries.sh
source $ROOT_DIR/nsx-t-ci-pipeline/functions/check_versions.sh
source $ROOT_DIR/nsx-t-ci-pipeline/functions/generate_cert.sh
source $ROOT_DIR/nsx-t-ci-pipeline/functions/yaml2json.sh
source $ROOT_DIR/nsx-t-ci-pipeline/functions/check_null_variables.sh

openssl s_client  -servername $NSX_API_MANAGER \
                  -connect ${NSX_API_MANAGER}:443 \
                  </dev/null 2>/dev/null \
                  | openssl x509 -text \
                  >  /tmp/complete_nsx_manager_cert.log

NSX_MANAGER_CERT_ADDRESS=`cat /tmp/complete_nsx_manager_cert.log \
                        | grep Subject | grep "CN=" \
                        | awk '{print $NF}' \
                        | sed -e 's/CN=//g' `

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
                  | tail -30                        \
                  |  awk '/BEGIN /,/END / {print }' \
                  >  /tmp/nsx_manager_cacert.log

# Strip newlines and replace them with \r\n
cat /tmp/nsx_manager_cacert.log | tr '\n' '#'| sed -e 's/#/\r\n/g'   > /tmp/nsx_manager_edited_cacert.log
export NSX_API_CA_CERT=$(cat /tmp/nsx_manager_edited_cacert.log)


if [ -z "$PKS_SSL_CERT"  -o  "null" == "$PKS_SSL_CERT" ]; then
  domains=(
    "*.${PKS_SYSTEM_DOMAIN}"
  )

  certificates=$(generate_cert "${domains[*]}")
  PKS_SSL_CERT=`echo $certificates | jq --raw-output '.certificate'`
  PKS_SSL_PRIVATE_KEY=`echo $certificates | jq --raw-output '.key'`
fi

check_bosh_version
check_available_product_version "pivotal-container-service"

om-linux \
    -t https://$OPSMAN_DOMAIN_OR_IP_ADDRESS \
    -u $OPSMAN_USERNAME \
    -p $OPSMAN_PASSWORD \
    -k stage-product \
    -p $PRODUCT_NAME \
    -v $PRODUCT_VERSION

check_staged_product_guid "pivotal-container-service-"

# Check if product is older 1.0 or not
if [[ "$PRODUCT_VERSION" =~ "1.0" ]]; then
  product_version=1.0
else
  product_version=1.1

fi

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

pks_nsx_vcenter_properties=$(
  jq -n \
    --arg nsx_api_manager "$NSX_API_MANAGER" \
    --arg nsx_api_user "$NSX_API_USER" \
    --arg nsx_api_password "$NSX_API_PASSWORD" \
    --arg nsx_api_ca_cert "$NSX_API_CA_CERT" \
    --arg nsx_skip_ssl_verification "$NSX_SKIP_SSL_VERIFICATION" \
    --arg pks_t0_router_id "$PKS_T0_ROUTER_ID" \
    --arg ip_block_id "$PKS_IP_BLOCK_ID" \
    --arg floating_ip_pool_ids "$PKS_FLOATING_IP_POOL_IDS" \
    --arg vcenter_host "$PKS_VCENTER_HOST" \
    --arg vcenter_username "$PKS_VCENTER_USR" \
    --arg vcenter_password "$PKS_VCENTER_PWD" \
    --arg pks_vcenter_cluster "$PKS_VCENTER_CLUSTER" \
    --arg vcenter_datacenter "$PKS_VCENTER_DATA_CENTER" \
    --arg pks_vm_folder "$PKS_VM_FOLDER" \
    --arg vcenter_datastore "$PKS_VCENTER_DATASTORE" \
    '
    {
      ".properties.cloud_provider": {
        "value": "vSphere"
      },
      ".properties.cloud_provider.vsphere.vcenter_master_creds": {
        "value": {
          "identity": $vcenter_username,
          "password": $vcenter_password
        }
      },
      ".properties.cloud_provider.vsphere.vcenter_worker_creds": {
        "value": {
          "identity": $vcenter_username,
          "password": $vcenter_password
        }
      },
      ".properties.cloud_provider.vsphere.vcenter_ip": {
        "value": $vcenter_host
      },
      ".properties.cloud_provider.vsphere.vcenter_dc": {
        "value": $vcenter_datacenter
      },
      ".properties.cloud_provider.vsphere.vcenter_ds": {
        "value": $vcenter_datastore
      },
      ".properties.cloud_provider.vsphere.vcenter_vms": {
        "value": $pks_vm_folder
      },
      ".properties.network_selector": {
          "value": "nsx"
      },
      ".properties.network_selector.nsx.nsx-t-host": {
          "value": $nsx_api_manager
      },
      ".properties.network_selector.nsx.credentials": {
          "value": {
            "identity": $nsx_api_user,
            "password": $nsx_api_password
          }
      },
      ".properties.network_selector.nsx.nsx-t-ca-cert": {
          "value": $nsx_api_ca_cert
      },
      ".properties.network_selector.nsx.nsx-t-insecure": {
          "value": $nsx_skip_ssl_verification
      },
      ".properties.network_selector.nsx.vcenter_cluster": {
          "value": $pks_vcenter_cluster
      },
      ".properties.network_selector.nsx.t0-router-id": {
          "value": $pks_t0_router_id
      },
      ".properties.network_selector.nsx.ip-block-id": {
          "value": $ip_block_id
      },
      ".properties.network_selector.nsx.floating-ip-pool-ids": {
          "value": $floating_ip_pool_ids
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
  --product-properties "$pks_nsx_vcenter_properties"

echo "Finished configuring NSX/vCenter properties"

pks_syslog_properties=$(
  jq -n \
  --arg pks_syslog_migration_enabled "$PKS_SYSLOG_MIGRATION_ENABLED" \
  --arg pks_syslog_address "$PKS_SYSLOG_ADDRESS" \
  --arg pks_syslog_port "$PKS_SYSLOG_PORT" \
  --arg pks_syslog_transport_protocol "$PKS_SYSLOG_TRANSPORT_PROTOCOL" \
  --arg pks_syslog_tls_enabled "$PKS_SYSLOG_TLS_ENABLED" \
  --arg pks_syslog_peer "$PKS_SYSLOG_PEER" \
  --arg pks_syslog_ca_cert "$PKS_SYSLOG_CA_CERT" \
    '

    # Syslog
    if $pks_syslog_migration_enabled == "enabled" then
      {
        ".properties.syslog_migration_selector.enabled.address": {
          "value": $pks_syslog_address
        },
        ".properties.syslog_migration_selector.enabled.port": {
          "value": $pks_syslog_port
        },
        ".properties.syslog_migration_selector.enabled.transport_protocol": {
          "value": $pks_syslog_transport_protocol
        },
        ".properties.syslog_migration_selector.enabled.tls_enabled": {
          "value": $pks_syslog_tls_enabled
        },
        ".properties.syslog_migration_selector.enabled.permitted_peer": {
          "value": $pks_syslog_peer
        },
        ".properties.syslog_migration_selector.enabled.ca_cert": {
          "value": $pks_syslog_ca_cert
        }
      }
    else
      {
        ".properties.syslog_migration_selector": {
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

plan_props='{}'

for plan_selection in $(echo "$PKS_PLAN_DETAILS" | jq  -r '.[].plan_detail.plan_selector')
do
  # echo "Plan selection is ${plan_selection}"
  # echo ""
  new_plan_entry=$(echo "$PKS_PLAN_DETAILS"  \
               | jq  --arg plan_selection $plan_selection \
                 '.[].plan_detail | select(.plan_selector | contains($plan_selection) ) | select(.is_active == true ) | del(.is_active)| del(.plan_selector) | to_entries | .[] |  { ".properties.\($plan_selection).active.\(.key)" : { "value" : (.value) } }' | jq -s add  )

    # Pushing the properties under .properties.$plan_selection.active wrapper
    # does not work with Ops Mgr
    # new_plan_entry=$(echo "{ \".properties.${plan_selection}\": { \"value\": \"Plan Active\" } }" \
    # | jq --argjson current_entry "$new_plan_entry" \
    #      --arg plan_selection $plan_selection \
    #   '
    #   {
    #     ".properties.\($plan_selection)": {
    #       "value": "Plan Active",
    #       "active": $current_entry
    #     }
    #   }
    #   '
    # )

  if [ "$new_plan_entry" == ''  -o "$new_plan_entry" == "null" ]; then
      new_plan_entry=$(echo "{ \".properties.${plan_selection}\": { \"value\": \"Plan Inactive\" } }")
  else
    new_plan_entry=$(echo "{ \".properties.${plan_selection}\": { \"value\": \"Plan Active\" } }" "$new_plan_entry" | jq -s add)
  fi

  #echo "New plan entry is $new_plan_entry"
  plan_props=$(echo $plan_props $new_plan_entry | jq -s add )
done
#echo "Final PKS Plan Properties is $plan_props"

pks_main_properties=$(
  echo $plan_props | jq  \
    --arg pks_system_domain "$PKS_SYSTEM_DOMAIN" \
    --arg pks_uaa_domain "${PKS_UAA_DOMAIN_PREFIX}.${PKS_SYSTEM_DOMAIN}" \
    --arg pks_cli_user "$PKS_CLI_USER" \
    --arg pks_cli_password "$PKS_CLI_PASSWORD" \
    --arg pks_cli_email "$PKS_CLI_EMAIL" \
    --arg cert_pem "$PKS_SSL_CERT" \
    --arg private_key_pem "$PKS_SSL_PRIVATE_KEY" \
    --argjson plan_props "$plan_props" \
    '
    .
    +

    {
      ".pivotal-container-service.pks_tls": {
        "value": {
          "private_key_pem":$private_key_pem,
          "cert_pem": $cert_pem
        }
      },
      ".properties.uaa_url": {
          "value": $pks_uaa_domain
      },
      ".properties.uaa_pks_cli_access_token_lifetime": {
          "value": "86400"
      },
      ".properties.uaa_pks_cli_refresh_token_lifetime": {
          "value": "172800"
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
  --product-name "$PRODUCT_NAME" \
  --product-properties "$pks_main_properties"

echo "Finished configuring PKS plan and other config properties!!"

errand="pks-nsx-t-precheck"

om-linux \
  -t https://$OPSMAN_DOMAIN_OR_IP_ADDRESS \
  -u $OPSMAN_USERNAME \
  -p $OPSMAN_PASSWORD \
  --skip-ssl-validation \
  set-errand-state \
  --product-name "$PRODUCT_NAME" \
  --errand-name $errand \
  --post-deploy-state "true"

echo "Configured $errand to always run ..."
