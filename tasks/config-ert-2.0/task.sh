#!/bin/bash

set -eu

export ROOT_DIR=`pwd`
source $ROOT_DIR/nsx-t-ci-pipeline/functions/copy_binaries.sh
source $ROOT_DIR/nsx-t-ci-pipeline/functions/check_versions.sh
source $ROOT_DIR/nsx-t-ci-pipeline/functions/generate_cert.sh
source $ROOT_DIR/nsx-t-ci-pipeline/functions/check_null_variables.sh

if [ -z "$SSL_CERT"  -o "null" == "$SSL_CERT" ]; then
  domains=(
    "*.${SYSTEM_DOMAIN}"
    "*.${APPS_DOMAIN}"
    "*.login.${SYSTEM_DOMAIN}"
    "*.uaa.${SYSTEM_DOMAIN}"
  )

  certificates=$(generate_cert "${domains[*]}")
  SSL_CERT=`echo $certificates | jq --raw-output '.certificate'`
  SSL_PRIVATE_KEY=`echo $certificates | jq --raw-output '.key'`
fi


if [ -z "$SAML_SSL_CERT"  -o "null" == "$SAML_SSL_CERT" ]; then
  saml_cert_domains=(
    "*.${SYSTEM_DOMAIN}"
    "*.login.${SYSTEM_DOMAIN}"
    "*.uaa.${SYSTEM_DOMAIN}"
  )

  saml_certificates=$(generate_cert "${saml_cert_domains[*]}")
  SAML_SSL_CERT=$(echo $saml_certificates | jq --raw-output '.certificate')
  SAML_SSL_PRIVATE_KEY=$(echo $saml_certificates | jq --raw-output '.key')
fi

# SABHA
# Change in ERT 2.0
# from: ".push-apps-manager.company_name"
# to: ".properties.push_apps_manager_company_name"

# Generate CredHub passwd
if [ "$CREDHUB_PASSWORD" == "" -o  "$CREDHUB_PASSWORD" == "null" ]; then
  CREDHUB_PASSWORD=$(echo $OPSMAN_PASSWORD{,,,,} | sed -e 's/ //g' | cut -c1-25)
fi


check_bosh_version
check_available_product_version "cf"

om-linux \
    -t https://$OPSMAN_DOMAIN_OR_IP_ADDRESS \
    -u $OPSMAN_USERNAME \
    -p $OPSMAN_PASSWORD \
	  --connect-timeout 3200 \
	  --request-timeout 3200 \
    -k stage-product \
    -p $PRODUCT_NAME \
    -v $PRODUCT_VERSION

check_staged_product_guid "cf-"

has_blobstore_internal_access_subnet=$(cat "/tmp/staged_product_${PRODUCT_GUID}.json" | jq . | grep ".nfs_server\.blobstore_internal_access_rules" | wc -l || true)
has_grootfs=$(cat "/tmp/staged_product_${PRODUCT_GUID}.json" | jq . | grep ".properties\.enable_grootfs" | wc -l || true)

# Check if product is older 2.0 or not
if [[ "$PRODUCT_VERSION" =~ ^2.0 ]]; then
  product_version=2.0
else
  product_version=2.1

fi

# Set Router as default routing ssl terminator
if [ "$ROUTING_SSL_TERMINATOR" == "" -o  "$ROUTING_SSL_TERMINATOR" == "null" ]; then
  ROUTING_SSL_TERMINATOR=router
fi

cf_properties=$(
  jq -n \
    --arg tcp_routing "$TCP_ROUTING" \
    --arg tcp_routing_ports "$TCP_ROUTING_PORTS" \
    --arg loggregator_endpoint_port "$LOGGREGATOR_ENDPOINT_PORT" \
    --arg route_services "$ROUTE_SERVICES" \
    --arg ignore_ssl_cert "$IGNORE_SSL_CERT" \
    --arg security_acknowledgement "$SECURITY_ACKNOWLEDGEMENT" \
    --arg system_domain "$SYSTEM_DOMAIN" \
    --arg apps_domain "$APPS_DOMAIN" \
    --arg default_quota_memory_limit_in_mb "$DEFAULT_QUOTA_MEMORY_LIMIT_IN_MB" \
    --arg default_quota_max_services_count "$DEFAULT_QUOTA_MAX_SERVICES_COUNT" \
    --arg allow_app_ssh_access "$ALLOW_APP_SSH_ACCESS" \
    --arg ha_proxy_ips "$HA_PROXY_IPS" \
    --arg skip_cert_verify "$SKIP_CERT_VERIFY" \
    --arg router_static_ips "$ROUTER_STATIC_IPS" \
    --arg disable_insecure_cookies "$DISABLE_INSECURE_COOKIES" \
    --arg router_request_timeout_seconds "$ROUTER_REQUEST_TIMEOUT_IN_SEC" \
    --arg mysql_monitor_email "$MYSQL_MONITOR_EMAIL" \
    --arg tcp_router_static_ips "$TCP_ROUTER_STATIC_IPS" \
    --arg company_name "$COMPANY_NAME" \
    --arg ssh_static_ips "$SSH_STATIC_IPS" \
    --arg cert_pem "$SSL_CERT" \
    --arg private_key_pem "$SSL_PRIVATE_KEY" \
    --arg haproxy_forward_tls "$HAPROXY_FORWARD_TLS" \
    --arg haproxy_backend_ca "$HAPROXY_BACKEND_CA" \
    --arg router_tls_ciphers "$ROUTER_TLS_CIPHERS" \
    --arg haproxy_tls_ciphers "$HAPROXY_TLS_CIPHERS" \
    --arg disable_http_proxy "$DISABLE_HTTP_PROXY" \
    --arg smtp_from "$SMTP_FROM" \
    --arg smtp_address "$SMTP_ADDRESS" \
    --arg smtp_port "$SMTP_PORT" \
    --arg smtp_user "$SMTP_USER" \
    --arg smtp_password "$SMTP_PWD" \
    --arg smtp_auth_mechanism "$SMTP_AUTH_MECHANISM" \
    --arg enable_security_event_logging "$ENABLE_SECURITY_EVENT_LOGGING" \
    --arg syslog_host "$SYSLOG_HOST" \
    --arg syslog_drain_buffer_size "$SYSLOG_DRAIN_BUFFER_SIZE" \
    --arg syslog_port "$SYSLOG_PORT" \
    --arg syslog_protocol "$SYSLOG_PROTOCOL" \
    --arg authentication_mode "$AUTHENTICATION_MODE" \
    --arg ldap_url "$LDAP_URL" \
    --arg ldap_user "$LDAP_USER" \
    --arg ldap_password "$LDAP_PWD" \
    --arg ldap_search_base "$SEARCH_BASE" \
    --arg ldap_search_filter "$SEARCH_FILTER" \
    --arg ldap_group_search_base "$GROUP_SEARCH_BASE" \
    --arg ldap_group_search_filter "$GROUP_SEARCH_FILTER" \
    --arg ldap_mail_attr_name "$MAIL_ATTR_NAME" \
    --arg ldap_first_name_attr "$FIRST_NAME_ATTR" \
    --arg ldap_last_name_attr "$LAST_NAME_ATTR" \
    --arg saml_cert_pem "$SAML_SSL_CERT" \
    --arg saml_key_pem "$SAML_SSL_PRIVATE_KEY" \
    --arg mysql_backups "$MYSQL_BACKUPS" \
    --arg mysql_backups_s3_endpoint_url "$MYSQL_BACKUPS_S3_ENDPOINT_URL" \
    --arg mysql_backups_s3_bucket_name "$MYSQL_BACKUPS_S3_BUCKET_NAME" \
    --arg mysql_backups_s3_bucket_path "$MYSQL_BACKUPS_S3_BUCKET_PATH" \
    --arg mysql_backups_s3_access_key_id "$MYSQL_BACKUPS_S3_ACCESS_KEY_ID" \
    --arg mysql_backups_s3_secret_access_key "$MYSQL_BACKUPS_S3_SECRET_ACCESS_KEY" \
    --arg mysql_backups_s3_cron_schedule "$MYSQL_BACKUPS_S3_CRON_SCHEDULE" \
    --arg mysql_backups_scp_server "$MYSQL_BACKUPS_SCP_SERVER" \
    --arg mysql_backups_scp_port "$MYSQL_BACKUPS_SCP_PORT" \
    --arg mysql_backups_scp_user "$MYSQL_BACKUPS_SCP_USER" \
    --arg mysql_backups_scp_key "$MYSQL_BACKUPS_SCP_KEY" \
    --arg mysql_backups_scp_destination "$MYSQL_BACKUPS_SCP_DESTINATION" \
    --arg mysql_backups_scp_cron_schedule "$MYSQL_BACKUPS_SCP_CRON_SCHEDULE" \
    --arg container_networking_nw_cidr "$CONTAINER_NETWORKING_NW_CIDR" \
    --arg credhub_password "$CREDHUB_PASSWORD" \
    --arg container_networking_interface_plugin "$CONTAINER_NETWORKING_INTERFACE_PLUGIN" \
    --arg has_blobstore_internal_access_subnet "$has_blobstore_internal_access_subnet" \
    --arg blobstore_internal_access_subnet "$BLOBSTORE_INTERNAL_ACCESS_SUBNET" \
    --arg has_grootfs "$has_grootfs" \
    --arg enable_grootfs "${ENABLE_GROOTFS}" \
    --arg product_version "$product_version" \
    --arg routing_tls_terminator "$ROUTING_SSL_TERMINATOR" \
    '
    {
      ".properties.system_blobstore": {
        "value": "internal"
      },
      ".properties.logger_endpoint_port": {
        "value": $loggregator_endpoint_port
      },
      ".properties.security_acknowledgement": {
        "value": $security_acknowledgement
      },
      ".cloud_controller.system_domain": {
        "value": $system_domain
      },
      ".cloud_controller.apps_domain": {
        "value": $apps_domain
      },
      ".cloud_controller.default_quota_memory_limit_mb": {
        "value": $default_quota_memory_limit_in_mb
      },
      ".cloud_controller.default_quota_max_number_services": {
        "value": $default_quota_max_services_count
      },
      ".cloud_controller.allow_app_ssh_access": {
        "value": $allow_app_ssh_access
      },
      ".ha_proxy.static_ips": {
        "value": $ha_proxy_ips
      },
      ".ha_proxy.skip_cert_verify": {
        "value": $skip_cert_verify
      },
      ".router.static_ips": {
        "value": $router_static_ips
      },
      ".router.disable_insecure_cookies": {
        "value": $disable_insecure_cookies
      },
      ".router.request_timeout_in_seconds": {
        "value": $router_request_timeout_seconds
      },
      ".mysql_monitor.recipient_email": {
        "value": $mysql_monitor_email
      },
      ".tcp_router.static_ips": {
        "value": $tcp_router_static_ips
      },
      ".properties.push_apps_manager_company_name": {
        "value": $company_name
      },
      ".diego_brain.static_ips": {
        "value": $ssh_static_ips
      }
    }

    +

    # Blobstore access subnet
    if $has_blobstore_internal_access_subnet != "0" then
    {
        ".nfs_server.blobstore_internal_access_rules": {
        "value": $blobstore_internal_access_subnet
      }
    }
    else
    .
    end

    +

    # Grootfs option
    if $has_grootfs != "0" then
    {
        ".properties.enable_grootfs": {
        "value": $enable_grootfs
      }
    }
    else
    .
    end

    +

    # Route Services
    if $route_services == "enable" then
     {
       ".properties.route_services": {
         "value": "enable"
       },
       ".properties.route_services.enable.ignore_ssl_cert_verification": {
         "value": $ignore_ssl_cert
       }
     }
    else
     {
       ".properties.route_services": {
         "value": "disable"
       }
     }
    end

    +

    # TCP Routing
    if $tcp_routing == "enable" then
     {
       ".properties.tcp_routing": {
          "value": "enable"
        },
        ".properties.tcp_routing.enable.reservable_ports": {
          "value": $tcp_routing_ports
        }
      }
    else
      {
        ".properties.tcp_routing": {
          "value": "disable"
        }
      }
    end

    +

    # SSL Termination
    # SABHA - Change structure to take multiple certs.. for PCF 2.0
    {
      ".properties.networking_poe_ssl_certs": {
        "value": [
          {
            "name": "certificate",
            "certificate": {
              "cert_pem": $cert_pem,
              "private_key_pem": $private_key_pem
            }
          }
        ]
      }
    }

    +
    # PAS 2.1 has new flag for routing tls temrination: .properties.routing_tls_termination
    if $product_version != "2.0" then
    {
      ".properties.routing_tls_termination": {
        "value": $routing_tls_terminator
      }
    }
    else
      .
    end

    +

    # SABHA - Credhub integration
    {
     ".properties.credhub_key_encryption_passwords": {
        "value": [
          {
            "name": "primary-encryption-key",
            "key": { "secret": $credhub_password },
            "primary": true
          }
        ]
      }
    }

    +


    # SABHA - NSX-T Vs Silk integration
    if $container_networking_interface_plugin != "silk" then
      {
        ".properties.container_networking_interface_plugin": {
          "value": "external"
        }
      }
    else
      {
        ".properties.container_networking_interface_plugin": {
          "value": "silk"
        }
      }
    end

    +

    # HAProxy Forward TLS
    if $haproxy_forward_tls == "enable" then
      {
        ".properties.haproxy_forward_tls": {
          "value": "enable"
        },
        ".properties.haproxy_forward_tls.enable.backend_ca": {
          "value": $haproxy_backend_ca
        }
      }
    else
      {
        ".properties.haproxy_forward_tls": {
          "value": "disable"
        }
      }
    end

    +

    {
      ".properties.routing_disable_http": {
        "value": $disable_http_proxy
      }
    }

    +

    # TLS Cipher Suites
    {
      ".properties.gorouter_ssl_ciphers": {
        "value": $router_tls_ciphers
      },
      ".properties.haproxy_ssl_ciphers": {
        "value": $haproxy_tls_ciphers
      }
    }

    +

    # SMTP Configuration
    if $smtp_address != "" and $smtp_address != "null" then
      {
        ".properties.smtp_from": {
          "value": $smtp_from
        },
        ".properties.smtp_address": {
          "value": $smtp_address
        },
        ".properties.smtp_port": {
          "value": $smtp_port
        },
        ".properties.smtp_credentials": {
          "value": {
            "identity": $smtp_user,
            "password": $smtp_password
          }
        },
        ".properties.smtp_enable_starttls_auto": {
          "value": true
        },
        ".properties.smtp_auth_mechanism": {
          "value": $smtp_auth_mechanism
        }
      }
    else
      .
    end

    +

    # Syslog
    if $syslog_host != "" and $syslog_host != "null" then
      {
        ".doppler.message_drain_buffer_size": {
          "value": $syslog_drain_buffer_size
        },
        ".cloud_controller.security_event_logging_enabled": {
          "value": $enable_security_event_logging
        },
        ".properties.syslog_host": {
          "value": $syslog_host
        },
        ".properties.syslog_port": {
          "value": $syslog_port
        },
        ".properties.syslog_protocol": {
          "value": $syslog_protocol
        }
      }
    else
      .
    end

    +

    # Authentication
    if $authentication_mode == "internal" then
      {
        ".properties.uaa": {
          "value": "internal"
        }
      }
    elif $authentication_mode == "ldap" then
      {
        ".properties.uaa": {
          "value": "ldap"
        },
        ".properties.uaa.ldap.url": {
          "value": $ldap_url
        },
        ".properties.uaa.ldap.credentials": {
          "value": {
            "identity": $ldap_user,
            "password": $ldap_password
          }
        },
        ".properties.uaa.ldap.search_base": {
          "value": $ldap_search_base
        },
        ".properties.uaa.ldap.search_filter": {
          "value": $ldap_search_filter
        },
        ".properties.uaa.ldap.group_search_base": {
          "value": $ldap_group_search_base
        },
        ".properties.uaa.ldap.group_search_filter": {
          "value": $ldap_group_search_filter
        },
        ".properties.uaa.ldap.mail_attribute_name": {
          "value": $ldap_mail_attr_name
        },
        ".properties.uaa.ldap.first_name_attribute": {
          "value": $ldap_first_name_attr
        },
        ".properties.uaa.ldap.last_name_attribute": {
          "value": $ldap_last_name_attr
        }
      }
    else
      .
    end

    +

    # UAA SAML Credentials
    {
      ".uaa.service_provider_key_credentials": {
        value: {
          "cert_pem": $saml_cert_pem,
          "private_key_pem": $saml_key_pem
        }
      }
    }

    +

    # MySQL Backups
    if $mysql_backups == "s3" then
      {
        ".properties.mysql_backups": {
          "value": "s3"
        },
        ".properties.mysql_backups.s3.endpoint_url":  {
          "value": $mysql_backups_s3_endpoint_url
        },
        ".properties.mysql_backups.s3.bucket_name":  {
          "value": $mysql_backups_s3_bucket_name
        },
        ".properties.mysql_backups.s3.bucket_path":  {
          "value": $mysql_backups_s3_bucket_path
        },
        ".properties.mysql_backups.s3.access_key_id":  {
          "value": $mysql_backups_s3_access_key_id
        },
        ".properties.mysql_backups.s3.secret_access_key":  {
          "value": $mysql_backups_s3_secret_access_key
        },
        ".properties.mysql_backups.s3.cron_schedule":  {
          "value": $mysql_backups_s3_cron_schedule
        }
      }
    elif $mysql_backups == "scp" then
      {
        ".properties.mysql_backups": {
          "value": "scp"
        },
        ".properties.mysql_backups.scp.server": {
          "value": $mysql_backups_scp_server
        },
        ".properties.mysql_backups.scp.port": {
          "value": $mysql_backups_scp_port
        },
        ".properties.mysql_backups.scp.user": {
          "value": $mysql_backups_scp_user
        },
        ".properties.mysql_backups.scp.key": {
          "value": $mysql_backups_scp_key
        },
        ".properties.mysql_backups.scp.destination": {
          "value": $mysql_backups_scp_destination
        },
        ".properties.mysql_backups.scp.cron_schedule" : {
          "value": $mysql_backups_scp_cron_schedule
        }
      }
    else
      .
    end
    '
)

## SABHA - removed cidr
# ".properties.container_networking_network_cidr": {
#         "value": $container_networking_nw_cidr
#       },




cf_network=$(
  jq -n \
    --arg network_name "$NETWORK_NAME" \
    --arg other_azs "$DEPLOYMENT_NW_AZS" \
    --arg singleton_az "$ERT_SINGLETON_JOB_AZ" \
    '
    {
      "network": {
        "name": $network_name
      },
      "other_availability_zones": ($other_azs | split(",") | map({name: .})),
      "singleton_availability_zone": {
        "name": $singleton_az
      }
    }
    '

)

cf_resources=$(
  jq -n \
    --arg iaas "$IAAS" \
    --argjson consul_server_instances $CONSUL_SERVER_INSTANCES \
    --argjson nats_instances $NATS_INSTANCES \
    --argjson nfs_server_instances $NFS_SERVER_INSTANCES \
    --argjson mysql_proxy_instances $MYSQL_PROXY_INSTANCES \
    --argjson mysql_instances $MYSQL_INSTANCES \
    --argjson backup_prepare_instances $BACKUP_PREPARE_INSTANCES \
    --argjson diego_database_instances $DIEGO_DATABASE_INSTANCES \
    --argjson uaa_instances $UAA_INSTANCES \
    --argjson cloud_controller_instances $CLOUD_CONTROLLER_INSTANCES \
    --argjson ha_proxy_instances $HA_PROXY_INSTANCES \
    --argjson router_instances $ROUTER_INSTANCES \
    --argjson mysql_monitor_instances $MYSQL_MONITOR_INSTANCES \
    --argjson clock_global_instances $CLOCK_GLOBAL_INSTANCES \
    --argjson cloud_controller_worker_instances $CLOUD_CONTROLLER_WORKER_INSTANCES \
    --argjson diego_brain_instances $DIEGO_BRAIN_INSTANCES \
    --argjson diego_cell_instances $DIEGO_CELL_INSTANCES \
    --argjson loggregator_tc_instances $LOGGREGATOR_TC_INSTANCES \
    --argjson tcp_router_instances $TCP_ROUTER_INSTANCES \
    --argjson syslog_adapter_instances $SYSLOG_ADAPTER_INSTANCES \
    --argjson doppler_instances $DOPPLER_INSTANCES \
    --argjson internet_connected $INTERNET_CONNECTED \
    --arg ha_proxy_elb_name "$HA_PROXY_LB_NAME" \
    --arg ha_proxy_floating_ips "$HAPROXY_FLOATING_IPS" \
    --arg tcp_router_nsx_security_group "${TCP_ROUTER_NSX_SECURITY_GROUP}" \
    --arg tcp_router_nsx_lb_edge_name "${TCP_ROUTER_NSX_LB_EDGE_NAME}" \
    --arg tcp_router_nsx_lb_pool_name "${TCP_ROUTER_NSX_LB_POOL_NAME}" \
    --arg tcp_router_nsx_lb_security_group "${TCP_ROUTER_NSX_LB_SECURITY_GROUP}" \
    --arg tcp_router_nsx_lb_port "${TCP_ROUTER_NSX_LB_PORT}" \
    --arg router_nsx_security_group "${ROUTER_NSX_SECURITY_GROUP}" \
    --arg router_nsx_lb_edge_name "${ROUTER_NSX_LB_EDGE_NAME}" \
    --arg router_nsx_lb_pool_name "${ROUTER_NSX_LB_POOL_NAME}" \
    --arg router_nsx_lb_security_group "${ROUTER_NSX_LB_SECURITY_GROUP}" \
    --arg router_nsx_lb_port "${ROUTER_NSX_LB_PORT}" \
    --arg diego_brain_nsx_security_group "${DIEGO_BRAIN_NSX_SECURITY_GROUP}" \
    --arg diego_brain_nsx_lb_edge_name "${DIEGO_BRAIN_NSX_LB_EDGE_NAME}" \
    --arg diego_brain_nsx_lb_pool_name "${DIEGO_BRAIN_NSX_LB_POOL_NAME}" \
    --arg diego_brain_nsx_lb_security_group "${DIEGO_BRAIN_NSX_LB_SECURITY_GROUP}" \
    --arg diego_brain_nsx_lb_port "${DIEGO_BRAIN_NSX_LB_PORT}" \
    '
    {
      "consul_server": { "instances": $consul_server_instances },
      "nats": { "instances": $nats_instances },
      "nfs_server": { "instances": $nfs_server_instances },
      "mysql_proxy": { "instances": $mysql_proxy_instances },
      "mysql": { "instances": $mysql_instances },
      "backup-prepare": { "instances": $backup_prepare_instances },
      "diego_database": { "instances": $diego_database_instances },
      "uaa": { "instances": $uaa_instances },
      "cloud_controller": { "instances": $cloud_controller_instances },
      "ha_proxy": { "instances": $ha_proxy_instances },
      "router": { "instances": $router_instances },
      "mysql_monitor": { "instances": $mysql_monitor_instances },
      "clock_global": { "instances": $clock_global_instances },
      "cloud_controller_worker": { "instances": $cloud_controller_worker_instances },
      "diego_brain": { "instances": $diego_brain_instances },
      "diego_cell": { "instances": $diego_cell_instances },
      "loggregator_trafficcontroller": { "instances": $loggregator_tc_instances },
      "tcp_router": { "instances": $tcp_router_instances },
      "syslog_adapter": { "instances": $syslog_adapter_instances },
      "doppler": { "instances": $doppler_instances }
    }

    +

    if $ha_proxy_elb_name != "" and $ha_proxy_elb_name != "null" then
      .ha_proxy |= . + { "elb_names": [ $ha_proxy_elb_name ] }
    else
      .
    end

    +

    if $ha_proxy_floating_ips != "" and $ha_proxy_floating_ips != "null" then
      .ha_proxy |= . + { "floating_ips": $ha_proxy_floating_ips }
    else
      .
    end

    +

    # NSX LBs

    if $tcp_router_nsx_lb_edge_name != "" and $tcp_router_nsx_lb_edge_name != "null" then
      .tcp_router |= . + {
        "nsx_security_groups": [$tcp_router_nsx_security_group],
        "nsx_lbs": [
          {
            "edge_name": $tcp_router_nsx_lb_edge_name,
            "pool_name": $tcp_router_nsx_lb_pool_name,
            "security_group": $tcp_router_nsx_lb_security_group,
            "port": $tcp_router_nsx_lb_port
          }
        ]
      }
    else
      .
    end

    +

    if $router_nsx_lb_edge_name != "" and $router_nsx_lb_edge_name != "null" then
      .router |= . + {
        "nsx_security_groups": [$router_nsx_security_group],
        "nsx_lbs": [
          {
            "edge_name": $router_nsx_lb_edge_name,
            "pool_name": $router_nsx_lb_pool_name,
            "security_group": $router_nsx_lb_security_group,
            "port": $router_nsx_lb_port
          }
        ]
      }
    else
      .
    end

    +

    if $diego_brain_nsx_lb_edge_name != "" and $diego_brain_nsx_lb_edge_name != "null" then
      .diego_brain |= . + {
        "nsx_security_groups": [$diego_brain_nsx_security_group],
        "nsx_lbs": [
          {
            "edge_name": $diego_brain_nsx_lb_edge_name,
            "pool_name": $diego_brain_nsx_lb_pool_name,
            "security_group": $diego_brain_nsx_lb_security_group,
            "port": $diego_brain_nsx_lb_port
          }
        ]
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
  --product-name cf \
  --product-properties "$cf_properties" \
  --product-network "$cf_network" \
  --product-resources "$cf_resources"
