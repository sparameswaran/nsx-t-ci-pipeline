#!/bin/bash

set -eu

pks_nsx_vcenter_properties=$(
  jq -n \
    --arg nsx_api_manager "$NSX_API_MANAGER" \
    --arg nsx_api_user "$NSX_API_USER" \
    --arg nsx_api_password "$NSX_API_PASSWORD" \
    --arg nsx_api_ca_cert "$NSX_API_CA_CERT" \
    --arg nsx_skip_ssl_verification "$NSX_SKIP_SSL_VERIFICATION" \
    --arg pks_t0_router_id "$PKS_T0_ROUTER_ID" \
    --arg ip_block_id "$PKS_IP_BLOCK_ID" \
    --arg floating_ip_pool_id "$PKS_FLOATING_IP_POOL_ID" \
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
          "value": $floating_ip_pool_id
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

plan_props='{}'

for plan_selection in $(echo "$PKS_PLAN_DETAILS" | jq  -r '.[].plan_detail.plan_selector')
do
  # echo "Plan selection is ${plan_selection}"
  # echo ""

  az_value=$(echo  "$PKS_PLAN_DETAILS"  \
             | jq  --arg plan_selection $plan_selection \
               '.[].plan_detail | select(.plan_selector | contains($plan_selection) ) | select(.is_active == true ) | .az_placement ' )
  az_json=$(echo "{ \".properties.${plan_selection}.active.az_placement\": { \"value\": $az_value } }" )

  new_plan_entry=$(echo "$PKS_PLAN_DETAILS"  \
               | jq  --arg plan_selection $plan_selection \
                 '.[].plan_detail | select(.plan_selector | contains($plan_selection) ) | select(.is_active == true ) | del(.is_active) | del(.plan_selector) | del(.worker_persistent_disk_type)| del(.az_placement) | to_entries | .[] |  { ".properties.\($plan_selection).active.\(.key)" : { "value" : (.value) } }' | jq -s add  )

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
    new_plan_entry=$(echo "{ \".properties.${plan_selection}\": { \"value\": \"Plan Active\" } }  $az_json " "$new_plan_entry" | jq -s add)
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

echo "Finished configuring PKS plan and other properties!!"

errand="pks-nsx-t-precheck"

om-linux \
  -t https://$OPSMAN_DOMAIN_OR_IP_ADDRESS \
  -u $OPSMAN_USERNAME \
  -p $OPSMAN_PASSWORD \
  --skip-ssl-validation \
  set-errand-state \
  --product-name "$PRODUCT_NAME" \
  --errand-name $errand \
  --post-deploy-state enabled

echo "Configured $errand to always run ..."
