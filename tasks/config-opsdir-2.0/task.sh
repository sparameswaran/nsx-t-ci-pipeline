#!/bin/bash

set -eu

export ROOT_DIR=`pwd`
source $ROOT_DIR/nsx-t-ci-pipeline/functions/copy_binaries.sh
source $ROOT_DIR/nsx-t-ci-pipeline/functions/check_versions.sh
source $ROOT_DIR/nsx-t-ci-pipeline/functions/generate_cert.sh
source $ROOT_DIR/nsx-t-ci-pipeline/functions/yaml2json.sh
source $ROOT_DIR/nsx-t-ci-pipeline/functions/check_null_variables.sh

iaas_configuration=$(
  jq -n \
  --arg vcenter_host "$VCENTER_HOST" \
  --arg vcenter_username "$VCENTER_USR" \
  --arg vcenter_password "$VCENTER_PWD" \
  --arg datacenter "$VCENTER_DATA_CENTER" \
  --arg disk_type "$VCENTER_DISK_TYPE" \
  --arg ephemeral_datastores_string "$EPHEMERAL_STORAGE_NAMES" \
  --arg persistent_datastores_string "$PERSISTENT_STORAGE_NAMES" \
  --arg bosh_vm_folder "$BOSH_VM_FOLDER" \
  --arg bosh_template_folder "$BOSH_TEMPLATE_FOLDER" \
  --arg bosh_disk_path "$BOSH_DISK_PATH" \
  --arg ssl_verification_enabled false \
  --arg nsx_networking_enabled $NSX_NETWORKING_ENABLED \
  '
  {
    "vcenter_host": $vcenter_host,
    "vcenter_username": $vcenter_username,
    "vcenter_password": $vcenter_password,
    "datacenter": $datacenter,
    "disk_type": $disk_type,
    "ephemeral_datastores_string": $ephemeral_datastores_string,
    "persistent_datastores_string": $persistent_datastores_string,
    "bosh_vm_folder": $bosh_vm_folder,
    "bosh_template_folder": $bosh_template_folder,
    "bosh_disk_path": $bosh_disk_path,
    "ssl_verification_enabled": $ssl_verification_enabled,
    "nsx_networking_enabled": $nsx_networking_enabled
  }'
)

if [ "$NSX_NETWORKING_ENABLED" == "true" ]; then

  # Check if NSX Manager is accessible before pulling down its cert
  set +e
  curl -kv https://${NSX_ADDRESS} >/dev/null 2>/dev/null
  connect_status=$?
  set -e

  if [ "$connect_status" != "0" ]; then
    echo "Error in connecting to ${NSX_ADDRESS} over 443, please check and correct the NSX Mgr address or dns entries and retry!!"
    exit -1
  fi

  openssl s_client  -servername $NSX_ADDRESS \
                    -connect ${NSX_ADDRESS}:443 \
                    </dev/null 2>/dev/null \
                    | openssl x509 -text \
                    >  /tmp/complete_nsx_manager_cert.log

  export NSX_MANAGER_CERT_ADDRESS=`cat /tmp/complete_nsx_manager_cert.log \
                          | grep Subject | grep "CN=" \
                          | tr , '\n' | grep 'CN=' \
                          | sed -e 's/.* CN=//' `

  echo "Fully qualified domain name for NSX Manager: $NSX_ADDRESS"
  echo "Host name associated with NSX Manager cert: $NSX_MANAGER_CERT_ADDRESS"

  # Get all certs from the nsx manager
  openssl s_client -host $NSX_ADDRESS \
                   -port 443 -prexit -showcerts \
                   </dev/null 2>/dev/null  \
                   >  /tmp/nsx_manager_all_certs.log

  # Get the very last CA cert from the showcerts result
  cat /tmp/nsx_manager_all_certs.log \
                    |  awk '/BEGIN /,/END / {print }' \
                    | tail -40                        \
                    |  awk '/BEGIN /,/END / {print }' \
                    >  /tmp/nsx_manager_cacert.log

  # Strip newlines and replace them with \r\n
  cat /tmp/nsx_manager_cacert.log | tr '\n' '#'| sed -e 's/#/\r\n/g'   > /tmp/nsx_manager_edited_cacert.log
  export NSX_CA_CERTIFICATE=$(cat /tmp/nsx_manager_edited_cacert.log)

  iaas_configuration=$(echo $iaas_configuration | jq \
    --arg nsx_mode "$NSX_MODE" \
    --arg nsx_address "$NSX_ADDRESS" \
    --arg nsx_username "$NSX_USERNAME" \
    --arg nsx_password "$NSX_PASSWORD" \
    --arg nsx_ca_certificate "$NSX_CA_CERTIFICATE" \
  ' . +=
          {
            "nsx_mode": $nsx_mode,
            "nsx_address": $nsx_address,
            "nsx_username": $nsx_username,
            "nsx_password": $nsx_password,
            "nsx_ca_certificate": $nsx_ca_certificate
          }
  '
  )

fi

az_configuration=$(cat <<-EOF
{
  "availability_zones": [
    {
      "name": "$AZ_1",
      "cluster": "$AZ_1_CLUSTER_NAME",
      "resource_pool": "$AZ_1_RP_NAME"
    }
  ]
}
EOF
)

# Add additional AZs if defined
if [ "$AZ_2" != "" -a "$AZ_2" != "null" ]; then
  az_configuration=$(echo $az_configuration | jq \
    --arg az_name "$AZ_2" \
    --arg az_cluster "$AZ_2_CLUSTER_NAME" \
    --arg az_rp "$AZ_2_RP_NAME" \
  ' .availability_zones +=
          [{
            "name": $az_name,
            "cluster": $az_cluster,
            "resource_pool": $az_rp
          }]
  '
  )
fi

if [ "$AZ_3" != "" -a "$AZ_3" != "null" ]; then
  az_configuration=$(echo $az_configuration | jq \
    --arg az_name "$AZ_3" \
    --arg az_cluster "$AZ_3_CLUSTER_NAME" \
    --arg az_rp "$AZ_3_RP_NAME" \
  ' .availability_zones +=
          [{
            "name": $az_name,
            "cluster": $az_cluster,
            "resource_pool": $az_rp
          }]
  '
  )
fi

# if [ "$AZ_4" != "" -a "$AZ_4" != "null" ]; then
#   az_configuration=$(echo $az_configuration | jq \
#     --arg az4_name "$AZ_4" \
#     --arg az4_cluster "$AZ_4_CLUSTER_NAME" \
#     --arg az4_rp "$AZ_4_RP_NAME" \
# ' .availability_zones +=
#         [{
#           "name": $az4_name,
#           "cluster": $az4_cluster,
#           "resource_pool": $az4_rp
#         }]
# '
# )
# fi

network_configuration=$(
  jq -n \
    --argjson icmp_checks_enabled $ICMP_CHECKS_ENABLED \
    --arg infra_network_name "$INFRA_NETWORK_NAME" \
    --arg infra_vcenter_network "$INFRA_VCENTER_NETWORK" \
    --arg infra_network_cidr "$INFRA_NW_CIDR" \
    --arg infra_reserved_ip_ranges "$INFRA_EXCLUDED_RANGE" \
    --arg infra_dns "$INFRA_NW_DNS" \
    --arg infra_gateway "$INFRA_NW_GATEWAY" \
    --arg infra_availability_zones "$INFRA_NW_AZS" \
    '
    {
      "icmp_checks_enabled": $icmp_checks_enabled,
      "networks": [
        {
          "name": $infra_network_name,
          "service_network": false,
          "subnets": [
            {
              "iaas_identifier": $infra_vcenter_network,
              "cidr": $infra_network_cidr,
              "reserved_ip_ranges": $infra_reserved_ip_ranges,
              "dns": $infra_dns,
              "gateway": $infra_gateway,
              "availability_zone_names": ($infra_availability_zones | split(","))
            }
          ]
        }
      ]
    }'
)

if [ "$DEPLOYMENT_VCENTER_NETWORK" != "" -a "$DEPLOYMENT_VCENTER_NETWORK" != "null" ]; then
  network_configuration=$(echo $network_configuration | jq \
    --arg deployment_network_name "$DEPLOYMENT_NETWORK_NAME" \
    --arg services_vcenter_network "$DEPLOYMENT_VCENTER_NETWORK" \
    --arg deployment_network_cidr "$DEPLOYMENT_NW_CIDR" \
    --arg deployment_reserved_ip_ranges "$DEPLOYMENT_EXCLUDED_RANGE" \
    --arg deployment_dns "$DEPLOYMENT_NW_DNS" \
    --arg deployment_gateway "$DEPLOYMENT_NW_GATEWAY" \
    --arg deployment_availability_zones "$DEPLOYMENT_NW_AZS" \
' .networks +=
        [{
          "name": $deployment_network_name,
          "service_network": false,
          "subnets": [
            {
              "iaas_identifier": $services_vcenter_network,
              "cidr": $deployment_network_cidr,
              "reserved_ip_ranges": $deployment_reserved_ip_ranges,
              "dns": $deployment_dns,
              "gateway": $deployment_gateway,
              "availability_zone_names": ($deployment_availability_zones | split(","))
            }
          ]
        }]
'
)

fi

if [ "$SERVICES_VCENTER_NETWORK" != "" -a "$SERVICES_VCENTER_NETWORK" != "null" ]; then
  network_configuration=$(echo $network_configuration | jq \
    --arg services_network_name "$SERVICES_NETWORK_NAME" \
    --arg services_vcenter_network "$SERVICES_VCENTER_NETWORK" \
    --arg services_network_cidr "$SERVICES_NW_CIDR" \
    --arg services_reserved_ip_ranges "$SERVICES_EXCLUDED_RANGE" \
    --arg services_dns "$SERVICES_NW_DNS" \
    --arg services_gateway "$SERVICES_NW_GATEWAY" \
    --arg services_availability_zones "$SERVICES_NW_AZS" \
' .networks +=
        [{
          "name": $services_network_name,
          "service_network": false,
          "subnets": [
            {
              "iaas_identifier": $services_vcenter_network,
              "cidr": $services_network_cidr,
              "reserved_ip_ranges": $services_reserved_ip_ranges,
              "dns": $services_dns,
              "gateway": $services_gateway,
              "availability_zone_names": ($services_availability_zones | split(","))
            }
          ]
        }]
'
)

fi

if [ "$DYNAMIC_SERVICES_VCENTER_NETWORK" != "" -a "$DYNAMIC_SERVICES_VCENTER_NETWORK" != "null" ]; then
  network_configuration=$(echo $network_configuration | jq \
    --arg dynamic_services_network_name "$DYNAMIC_SERVICES_NETWORK_NAME" \
    --arg dynamic_services_vcenter_network "$DYNAMIC_SERVICES_VCENTER_NETWORK" \
    --arg dynamic_services_network_cidr "$DYNAMIC_SERVICES_NW_CIDR" \
    --arg dynamic_services_reserved_ip_ranges "$DYNAMIC_SERVICES_EXCLUDED_RANGE" \
    --arg dynamic_services_dns "$DYNAMIC_SERVICES_NW_DNS" \
    --arg dynamic_services_gateway "$DYNAMIC_SERVICES_NW_GATEWAY" \
    --arg dynamic_services_availability_zones "$DYNAMIC_SERVICES_NW_AZS" \
' .networks +=
        [{
          "name": $dynamic_services_network_name,
          "service_network": true,
          "subnets": [
            {
              "iaas_identifier": $dynamic_services_vcenter_network,
              "cidr": $dynamic_services_network_cidr,
              "reserved_ip_ranges": $dynamic_services_reserved_ip_ranges,
              "dns": $dynamic_services_dns,
              "gateway": $dynamic_services_gateway,
              "availability_zone_names": ($dynamic_services_availability_zones | split(","))
            }
          ]
        }]
'
)

fi

if [ "$PKS_VCENTER_NETWORK" != "" -a "$PKS_VCENTER_NETWORK" != "null" ]; then
  network_configuration=$(echo $network_configuration | jq \
    --arg pks_network_name "$PKS_NETWORK_NAME" \
    --arg pks_vcenter_network "$PKS_VCENTER_NETWORK" \
    --arg pks_network_cidr "$PKS_NW_CIDR" \
    --arg pks_reserved_ip_ranges "$PKS_EXCLUDED_RANGE" \
    --arg pks_dns "$PKS_NW_DNS" \
    --arg pks_gateway "$PKS_NW_GATEWAY" \
    --arg pks_availability_zones "$PKS_NW_AZS" \
' .networks +=
        [{
          "name": $pks_network_name,
          "service_network": true,
          "subnets": [
            {
              "iaas_identifier": $pks_vcenter_network,
              "cidr": $pks_network_cidr,
              "reserved_ip_ranges": $pks_reserved_ip_ranges,
              "dns": $pks_dns,
              "gateway": $pks_gateway,
              "availability_zone_names": ($pks_availability_zones | split(","))
            }
          ]
        }]
'
)

fi


director_config=$(cat <<-EOF
{
  "ntp_servers_string": "$NTP_SERVERS",
  "resurrector_enabled": true,
  "post_deploy_enabled": true,
  "bosh_recreate_on_next_deploy": true,
  "max_threads": null,
  "database_type": "internal",
  "blobstore_type": "local"
}
EOF
)

security_configuration=$(
  jq -n \
    --arg trusted_certificates "$TRUSTED_CERTIFICATES" \
    '
    {
        "security_configuration": {
            "trusted_certificates": $trusted_certificates,
            "generate_vm_passwords": true,
            "opsmanager_root_ca_trusted_certs": true
        }
    }'
)

network_az_assignment=$(
jq -n \
  --arg infra_availability_zones "$INFRA_NW_AZS" \
  --arg network "$INFRA_NETWORK_NAME" \
  '
  {
    "singleton_availability_zone": { "name": ($infra_availability_zones | split(",") | .[0]) },
    "network": { "name": $network }
  }'
)

echo "Configuring IaaS and Director..."

# om-linux has issues with handling boolean types
# wrapped as string for uknown flags like nsx_networking_enabled
# Error: configuring iaas specific options for bosh tile
# could not execute "configure-bosh":
# could not decode json:
# json: cannot unmarshal string into Go value of type bool
wrapped_iaas_config=$(cat << EOF
{
   "iaas_configuration" : $iaas_configuration
}
EOF
)
# om-linux has issues with handling boolean types
# wrapped as string for uknown flags like nsx_networking_enabled
# Error: configuring iaas specific options for bosh tile
# could not execute "configure-bosh":
# could not decode json:
# json: cannot unmarshal string into Go value of type bool
wrapped_iaas_config=$(cat << EOF
{
   "iaas_configuration" : $iaas_configuration
}
EOF
)


wrapped_network_az_assignment=$(cat << EOF
{
   "network_and_az" : $network_az_assignment
}
EOF
)

# So split the configure steps into iaas that uses curl to PUT and normal path for director config
om-linux \
  --target https://$OPSMAN_DOMAIN_OR_IP_ADDRESS \
  --skip-ssl-validation \
  --username $OPSMAN_USERNAME \
  --password $OPSMAN_PASSWORD \
  curl -p '/api/v0/staged/director/properties' \
  -x PUT -d  "$wrapped_iaas_config" \
  2>/dev/null

# Check for errors
if [ $? != 0 ]; then
  echo "IaaS configuration failed!!"
  exit 1
fi

om-linux \
  --target https://$OPSMAN_DOMAIN_OR_IP_ADDRESS \
  --skip-ssl-validation \
  --username $OPSMAN_USERNAME \
  --password $OPSMAN_PASSWORD \
  configure-bosh \
  --director-configuration "$director_config" \
  2>/dev/null
# Check for errors
if [ $? != 0 ]; then
  echo "Bosh Director configuration failed!!"
  exit 1
fi

#om-linux \
#  --target https://$OPSMAN_DOMAIN_OR_IP_ADDRESS \
#  --skip-ssl-validation \
#  --username $OPSMAN_USERNAME \
#  --password $OPSMAN_PASSWORD \
#  configure-bosh \
#  --security-configuration "$security_configuration" \
#  2>/dev/null
# Check for errors
#if [ $? != 0 ]; then
#  echo "Bosh Security configuration failed!!"
#  exit 1
#fi

om-linux \
  --target https://$OPSMAN_DOMAIN_OR_IP_ADDRESS \
  --skip-ssl-validation \
  --username $OPSMAN_USERNAME \
  --password $OPSMAN_PASSWORD \
  curl -p "/api/v0/staged/director/properties" \
  -x PUT -d  "$security_configuration"

# Check for errors
if [ $? != 0 ]; then
  echo "Bosh Security configuration failed!!"
  exit 1
fi

om-linux \
  --target https://$OPSMAN_DOMAIN_OR_IP_ADDRESS \
  --skip-ssl-validation \
  --username $OPSMAN_USERNAME \
  --password $OPSMAN_PASSWORD \
  curl -p "/api/v0/staged/director/availability_zones" \
  -x PUT -d "$az_configuration" \
  2>/dev/null
# Check for errors
if [ $? != 0 ]; then
  echo "Availability Zones configuration failed!!"
  exit 1
fi

om-linux \
  --target https://$OPSMAN_DOMAIN_OR_IP_ADDRESS \
  --skip-ssl-validation \
  --username $OPSMAN_USERNAME \
  --password $OPSMAN_PASSWORD \
  -k curl -p "/api/v0/staged/director/networks" \
  -x PUT -d "$network_configuration" \
  2>/dev/null
# Check for errors
if [ $? != 0 ]; then
  echo "Networks configuration failed!!"
  exit 1
fi

# Having trouble with om-cli with new network_assignment structure
# that wraps single_az and network inside json structure instead of string
om-linux \
  --target https://$OPSMAN_DOMAIN_OR_IP_ADDRESS \
  --skip-ssl-validation \
  --username $OPSMAN_USERNAME \
  --password $OPSMAN_PASSWORD \
  -k curl -p "/api/v0/staged/director/network_and_az" \
  -x PUT -d "$wrapped_network_az_assignment" \
   2>/dev/null
# Check for errors
if [ $? != 0 ]; then
  echo "Networks configuration and AZ assignment failed!!"
  exit 1
fi
