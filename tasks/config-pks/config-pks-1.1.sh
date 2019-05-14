#!/bin/bash

set -eu

BOSH_CREDS=$(om-linux  \
              -t https://$OPSMAN_DOMAIN_OR_IP_ADDRESS  \
              -u $OPSMAN_USERNAME  \
              -p $OPSMAN_PASSWORD  \
               -k curl -p '/api/v0/deployed/director/credentials/bosh_commandline_credentials' \
               2>/dev/null \
               | grep BOSH_CLIENT)

export BOSH_CLIENT_ID=$(echo $BOSH_CREDS | tr ' ' '\n' | grep 'BOSH_CLIENT=' | awk -F '=' '{print $2}' | tr -d ' ')
export BOSH_CLIENT_SECRET=$(echo $BOSH_CREDS | tr ' ' '\n' |grep 'BOSH_CLIENT_SECRET=' | awk -F '=' '{print $2}' | tr -d ' ')

if [ "$PKS_VRLI_ENABLED" == "true" ]; then

  pks_vrli_properties=$(
    jq -n \
    --arg pks_vrli_host "$PKS_VRLI_HOST" \
    --arg pks_vrli_use_ssl "$PKS_VRLI_USE_SSL" \
    --arg pks_vrli_skip_cert_verify "$PKS_VRLI_SKIP_CERT_VERIFY" \
    --arg pks_vrli_ca_cert "$PKS_VRLI_CA_CERT" \
    --arg pks_vrli_rate_limit "$PKS_VRLI_RATE_LIMIT" \
      '{
          ".properties.pks-vrli": {
            "value": "enabled"
          },
          ".properties.pks-vrli.enabled.host": {
            "value": $pks_vrli_host
          },
          ".properties.pks-vrli.enabled.use_ssl": {
            "value": $pks_vrli_use_ssl
          },
          ".properties.pks-vrli.enabled.skip_cert_verify": {
            "value": $pks_vrli_skip_cert_verify
          },
          ".properties.pks-vrli.enabled.ca_cert": {
            "value": $pks_vrli_ca_cert
          }
#          ".properties.pks-vrli.enabled.rate_limit_msec": {
#            "value": $pks_vrli_rate_limit
#          }
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
  --product-properties "$pks_vrli_properties"
  echo "Finished configuring vRealize Log Insight properties"

fi

if [ "$PKS_ENABLE_HTTP_PROXY" == "true" ]; then

  pks_proxy_properties=$(
    jq -n \
    --arg pks_http_proxy_url "$PKS_HTTP_PROXY_URL" \
    --arg pks_http_proxy_user "$PKS_HTTP_PROXY_USER" \
    --arg pks_http_proxy_password "$PKS_HTTP_PROXY_PASSWORD" \
    --arg pks_https_proxy_url "$PKS_HTTPS_PROXY_URL" \
    --arg pks_https_proxy_user "$PKS_HTTPS_PROXY_USER" \
    --arg pks_https_proxy_password "$PKS_HTTPS_PROXY_PASSWORD" \
    --arg pks_no_proxy "$PKS_NO_PROXY" \
      '{
          ".properties.proxy_selector": {
            "value": "Enabled"
          },
          ".properties.proxy_selector.enabled.http_proxy_url": {
            "value": $pks_http_proxy_url
          },
          ".properties.proxy_selector.enabled.http_proxy_credentials": {
            "value": {
              "identity": $pks_http_proxy_user,
              "password": $pks_http_proxy_password
            }
          },
          ".properties.proxy_selector.enabled.https_proxy_url": {
            "value": $pks_https_proxy_url
          },
          ".properties.proxy_selector.enabled.https_proxy_credentials": {
            "value": {
              "identity": $pks_https_proxy_user,
              "password": $pks_https_proxy_password
            }
          },
          ".properties.proxy_selector.enabled.no_proxy": {
            "value": $pks_no_proxy
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
  --product-properties "$pks_proxy_properties"
  echo "Finished configuring Proxy properties"
fi

if [ "$PKS_UAA_USE_LDAP" == "ldap" ]; then
  pks_uaa_properties=$(
    jq -n \
    --arg pks_ldap_url "$PKS_LDAP_URL" \
    --arg pks_ldap_use_oidc "$PKS_LDAP_USE_OIDC" \
    --arg pks_ldap_user "$PKS_LDAP_USER" \
    --arg pks_ldap_password "$PKS_LDAP_PASSWORD" \
    --arg pks_ldap_search_base "$PKS_LDAP_SEARCH_BASE" \
    --arg pks_ldap_search_filter "$PKS_LDAP_SEARCH_FILTER" \
    --arg pks_ldap_group_search_base "$PKS_LDAP_GROUP_SEARCH_BASE" \
    --arg pks_ldap_group_search_filter "$PKS_LDAP_GROUP_SEARCH_FILTER" \
    --arg pks_ldap_server_ssl_cert "$PKS_LDAP_SERVER_SSL_CERT" \
    --arg pks_ldap_server_ssl_cert_alias "$PKS_LDAP_SERVER_SSL_CERT_ALIAS" \
    --arg pks_ldap_email_domains "$PKS_LDAP_EMAIL_DOMAINS" \
    --arg pks_ldap_first_name_attribute "$PKS_LDAP_FIRST_NAME_ATTRIBUTE" \
    --arg pks_ldap_last_name_attribute "$PKS_LDAP_LAST_NAME_ATTRIBUTE" \
      '{
          ".properties.uaa": {
            "value": "ldap"
          },
          ".properties.uaa_oidc": {
            "value": $pks_ldap_use_oidc
          },        
          ".properties.uaa.ldap.url": {
            "value": $pks_ldap_url
          },
          ".properties.uaa.ldap.credentials": {
            "value": {
              "identity": $pks_ldap_user,
              "password": $pks_ldap_password
            }
          },
          ".properties.uaa.ldap.search_base": {
            "value": $pks_ldap_search_base
          },
          ".properties.uaa.ldap.search_filter": {
            "value": $pks_ldap_search_filter
          },
          ".properties.uaa.ldap.group_search_base": {
            "value": $pks_ldap_group_search_base
          },
          ".properties.uaa.ldap.group_search_filter": {
            "value": $pks_ldap_group_search_filter
          },
          ".properties.uaa.ldap.server_ssl_cert": {
            "value": $pks_ldap_server_ssl_cert
          },
          ".properties.uaa.ldap.server_ssl_cert_alias": {
            "value": $pks_ldap_server_ssl_cert_alias
          },
          ".properties.uaa.ldap.mail_attribute_name": {
            "value": "mail"
          },
          ".properties.uaa.ldap.email_domains": {
            "value": $pks_ldap_email_domains
          },
          ".properties.uaa.ldap.first_name_attribute": {
            "value": $pks_ldap_first_name_attribute
          },
          ".properties.uaa.ldap.last_name_attribute": {
            "value": $pks_ldap_last_name_attribute
          },
          ".properties.uaa.ldap.ldap_referrals": {
            "value": "follow"
          }
        }
      '
  )
else
  pks_uaa_properties=$( echo \
  '{
    ".properties.uaa": {
      "value": "internal"
    }
  }'
  )
fi

om-linux \
-t https://$OPSMAN_DOMAIN_OR_IP_ADDRESS \
-u $OPSMAN_USERNAME \
-p $OPSMAN_PASSWORD \
--skip-ssl-validation \
configure-product \
--product-name pivotal-container-service \
--product-properties "$pks_uaa_properties"
echo "Finished configuring UAA properties"

if [ "$PKS_WAVEFRONT_API_URL" != "" -a "$PKS_WAVEFRONT_API_URL" != "null" ]; then
  pks_wavefront_properties=$(
    jq -n \
    --arg pks_wavefront_api_url "$PKS_WAVEFRONT_API_URL" \
    --arg pks_wavefront_token "$PKS_WAVEFRONT_TOKEN" \
    --arg pks_wavefront_alert_targets "$PKS_WAVEFRONT_ALERT_TARGETS" \
    '{
          ".properties.wavefront": {
            "value": "enabled"
          },
          ".properties.wavefront.enabled.wavefront_api_url": {
            "value": $pks_wavefront_api_url
          },
          ".properties.wavefront.enabled.wavefront_token": {
            "value": {
              "secret": $pks_wavefront_token
            }
          },
          ".properties.wavefront.enabled.wavefront_alert_targets": {
            "value": $pks_wavefront_alert_targets
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
  --product-properties "$pks_wavefront_properties"
  echo "Finished configuring Wavefront Monitoring properties"
fi

if [ "$PKS_ENABLE_CADVISOR" == "true" ]; then
  pks_vrops_properties=$(
    jq -n \
    --arg pks_vrops_cadvisor "enabled" \
    '{
          ".properties.pks-vrops": {
            "value": "enabled"
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
  --product-properties "$pks_vrops_properties"
  echo "Finished configuring vROPS properties"
fi

has_bosh_client_creds=$(cat "/tmp/staged_product_${PRODUCT_GUID}.json" | jq . | grep ".properties.network_selector.nsx.bosh-client" | wc -l || true)
has_vcenter_worker_creds=$(cat "/tmp/staged_product_${PRODUCT_GUID}.json" | jq . | grep ".cloud_provider.vsphere.vcenter_worker_creds" | wc -l || true)
has_nsx_t_superuser_certificate=$(cat "/tmp/staged_product_${PRODUCT_GUID}.json" | jq . | grep ".nsx-t-superuser-certificate" | wc -l || true)

# New PKS 1.1 GA has added 2 new flags
has_cloud_config_dns=$(cat "/tmp/staged_product_${PRODUCT_GUID}.json" | jq . | grep ".properties.network_selector.nsx.cloud-config-dns" | wc -l || true)
has_vcenter_clusters=$(cat "/tmp/staged_product_${PRODUCT_GUID}.json" | jq . | grep ".properties.network_selector.nsx.vcenter_cluster" | wc -l || true)

if [ "$PKS_NSX_NAT_MODE" == '' -o "$PKS_NSX_NAT_MODE" == "null" ]; then
  PKS_NSX_NAT_MODE=true
fi

pks_nsx_vcenter_properties=$(
  jq -n \
    --arg nsx_api_manager "$NSX_API_MANAGER" \
    --arg nsx_api_user "$NSX_API_USER" \
    --arg nsx_api_password "$NSX_API_PASSWORD" \
    --arg nsx_api_ca_cert "$NSX_API_CA_CERT" \
    --arg nsx_skip_ssl_verification "$NSX_SKIP_SSL_VERIFICATION" \
    --arg pks_t0_router_id "$PKS_T0_ROUTER_ID" \
    --arg ip_block_id "$PKS_CONTAINER_IP_BLOCK_ID" \
    --arg floating_ip_pool_id "$PKS_EXTERNAL_IP_POOL_ID" \
    --arg vcenter_host "$PKS_VCENTER_HOST" \
    --arg vcenter_username "$PKS_VCENTER_USR" \
    --arg vcenter_password "$PKS_VCENTER_PWD" \
    --arg pks_vcenter_cluster "$PKS_VCENTER_CLUSTER" \
    --arg vcenter_datacenter "$PKS_VCENTER_DATA_CENTER" \
    --arg pks_vm_folder "$PKS_VM_FOLDER" \
    --arg vcenter_datastore "$PKS_VCENTER_DATASTORE" \
    --arg nodes_ip_block_id "$PKS_NODES_IP_BLOCK_ID" \
    --arg bosh_client_id "$BOSH_CLIENT_ID" \
    --arg bosh_client_secret "$BOSH_CLIENT_SECRET" \
    --arg product_version "$product_version" \
    --arg has_bosh_client_creds "$has_bosh_client_creds" \
    --arg has_vcenter_worker_creds "$has_vcenter_worker_creds" \
    --arg has_nsx_t_superuser_certificate "$has_nsx_t_superuser_certificate" \
    --arg has_cloud_config_dns "$has_cloud_config_dns" \
    --arg pks_nodes_dns_list "$PKS_NODES_DNS_LIST" \
    --arg pks_vcenter_cluster_list "$PKS_VCENTER_CLUSTER_LIST" \
    --arg pks_nsx_nat_mode "$PKS_NSX_NAT_MODE" \
    --arg has_vcenter_clusters "$has_vcenter_clusters" \
    --arg nsx_superuser_cert "$NSX_SUPERUSER_CERT" \
    --arg nsx_superuser_key "$NSX_SUPERUSER_KEY" \
    '
    {
      ".properties.cloud_provider": {
        "value": "vSphere"
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
      ".properties.network_selector.nsx.nat_mode": {
          "value": $pks_nsx_nat_mode
      },
      ".properties.network_selector.nsx.nsx-t-host": {
          "value": $nsx_api_manager
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
      },
      ".properties.cloud_provider.vsphere.vcenter_master_creds": {
        "value": {
          "identity": $vcenter_username,
          "password": $vcenter_password
        }
      },
      ".properties.network_selector.nsx.nodes-ip-block-id": {
        "value": $nodes_ip_block_id
      }
    }

    +

    if $has_vcenter_worker_creds != "0" then
    {
      ".properties.cloud_provider.vsphere.vcenter_worker_creds": {
        "value": {
          "identity": $vcenter_username,
          "password": $vcenter_password
        }
      }
    }
    else
    .
    end

    +

    if $has_bosh_client_creds != "0" then
    {
      ".properties.network_selector.nsx.bosh-client-id": {
        "value": $bosh_client_id
      },
      ".properties.network_selector.nsx.bosh-client-secret": {
        "value": {
          "secret" : $bosh_client_secret
        }
      }
    }
    else
    .
    end

    +

    # Set the super user private key and cert only on first generation
    # On rerunning the config, the cert/key wont get recreated as it was already created on nsx Mgr
    # In those cases, the cert and key would be empty
    if $has_nsx_t_superuser_certificate != "0" and $nsx_superuser_key != "" and $nsx_superuser_cert != "" then
    {
      ".properties.network_selector.nsx.nsx-t-superuser-certificate": {
          "value": {
            "cert_pem": $nsx_superuser_cert,
            "private_key_pem": $nsx_superuser_key
          }
        }
    }
    elif $has_nsx_t_superuser_certificate == "0" then
    {
      ".properties.network_selector.nsx.credentials": {
          "value": {
            "identity": $nsx_api_user,
            "password": $nsx_api_password
          }
        }
    }
    else
    .
    end
    +
    if $has_cloud_config_dns != "0" then
    {
      ".properties.network_selector.nsx.cloud-config-dns": {
        "value": $pks_nodes_dns_list
      }
    }
    else
    .
    end
    +
    if $has_vcenter_clusters != "0" then
    {
      ".properties.network_selector.nsx.vcenter_cluster": {
        "value": $pks_vcenter_cluster_list
      }
    }
    else
    .
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
  --product-properties "$pks_nsx_vcenter_properties"

echo "Finished configuring NSX/vCenter properties"

PKS_TELEMETRY=${PKS_TELEMETRY:-disabled}
pks_telemetry_properties=$(
  jq -n \
  --arg pks_telemetry_enabled "$PKS_TELEMETRY" \
  '{
        ".properties.telemetry_selector": {
          "value": $pks_telemetry_enabled
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
  --product-properties "$pks_telemetry_properties"

echo "Finished configuring Telemetry properties"

plan_props='{}'

for plan_selection in $(echo "$PKS_PLAN_DETAILS" | jq  -r '.[].plan_detail.plan_selector')
do
  # echo "Plan selection is ${plan_selection}"
  # echo ""

  az_value=$(echo "$PKS_PLAN_DETAILS"  \
               | jq  --arg plan_selection $plan_selection \
                 '.[].plan_detail | select(.plan_selector | contains($plan_selection) ) | select(.is_active == true ) | .az_placement |  split(",") ')
  az_json=$(echo "{ \".properties.${plan_selection}.active.master_az_placement\": { \"value\": $az_value } } { \".properties.${plan_selection}.active.worker_az_placement\": { \"value\": $az_value } } " )

  new_plan_entry=$(echo "$PKS_PLAN_DETAILS"  \
               | jq  --arg plan_selection $plan_selection \
                 '.[].plan_detail | select(.plan_selector | contains($plan_selection) ) | select(.is_active == true ) | del(.is_active) | del(.plan_selector) | del(.persistent_disk_type) | del(.az_placement) | to_entries | .[] |  { ".properties.\($plan_selection).active.\(.key)" : { "value" : (.value) } }' | jq -s add  )

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
      ".properties.pks_api_hostname": {
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

pksv1_1_properties='{}'
if [ "$PKS_ALLOW_PUBLIC_IP" == "true" ]; then
  pksv1_1_properties=$(jq -n  \
      --arg pks_allow_public_ip "$PKS_ALLOW_PUBLIC_IP" \
      '
      {
        ".properties.vm_extensions": {
          "value" :[
            "public_ip"
          ]
        }
      }
      '
  )
fi

om-linux \
  -t https://$OPSMAN_DOMAIN_OR_IP_ADDRESS \
  -u $OPSMAN_USERNAME \
  -p $OPSMAN_PASSWORD \
  --skip-ssl-validation \
  configure-product \
  --product-name "$PRODUCT_NAME" \
  --product-properties "$pksv1_1_properties"
echo "Finished configuring additional PKS v1.1 specific properties!!"

if [ "$PKS_DISABLE_NSX_T_PRECHECK_ERRAND" == ""      \
  -o "$PKS_DISABLE_NSX_T_PRECHECK_ERRAND" == "false" \
  -o "$PKS_DISABLE_NSX_T_PRECHECK_ERRAND" == "null"  ]; then
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
fi
