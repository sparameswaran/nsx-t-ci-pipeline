#!/bin/bash
set -eu

echo "Note - pre-requisite for this task to work:"
echo "- Your PKS API endpoint [${PKS_UAA_DOMAIN_PREFIX}.${PKS_SYSTEM_DOMAIN}] should be routable and accessible via the NSX-T network."

check_dns_lookup=$(nslookup ${PKS_UAA_DOMAIN_PREFIX}.${PKS_SYSTEM_DOMAIN})
if [ "$?" != "0" ]; then
  echo "Warning!! Unable to resolve ${PKS_UAA_DOMAIN_PREFIX}.${PKS_SYSTEM_DOMAIN}"
  echo "Proceeding with the assumption that ${PKS_UAA_DOMAIN_PREFIX}.${PKS_SYSTEM_DOMAIN} would resolve to IP: PKS_UAA_SYSTEM_DOMAIN_IP ultimately"
  echo ""
fi

echo "Retrieving PKS Controller IP from Ops Manager [https://$OPSMAN_DOMAIN_OR_IP_ADDRESS]..."
# get PKS UAA admin credentails from OpsMgr

PRODUCTS=$(om-linux \
            -t https://$OPSMAN_DOMAIN_OR_IP_ADDRESS \
            -u $OPSMAN_USERNAME \
            -p $OPSMAN_PASSWORD \
            --skip-ssl-validation \
            curl -p /api/v0/deployed/products \
            2>/dev/null)

PKS_GUID=$(echo "$PRODUCTS" | jq -r '.[] | .guid' | grep pivotal-container-service)

PKS_CONTROLLER_IP=$(om-linux \
                    -t https://$OPSMAN_DOMAIN_OR_IP_ADDRESS \
                    -u $OPSMAN_USERNAME \
                    -p $OPSMAN_PASSWORD \
                    --skip-ssl-validation \
                    curl -p /api/v0/deployed/products/$PKS_GUID/status \
                    2>/dev/null \
                    | jq -r '.[][0].ips[0]' )

echo "Discovered PKS Controller running at: $PKS_CONTROLLER_IP"

echo "Going to create NAT entry between External Address: $PKS_UAA_SYSTEM_DOMAIN_IP and PKS Controller internal IP: $PKS_CONTROLLER_IP"
echo "   on T0Router: $PKS_T0_ROUTER_NAME in NSX Manager: $NSX_API_MANAGER"

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

dnat_rule_payload=$( jq -n \
  --arg pks_controller_ip $PKS_CONTROLLER_IP \
  --arg pks_uaa_system_domain_ip $PKS_UAA_SYSTEM_DOMAIN_IP \
  '
  {
    "resource_type": "NatRule",
    "enabled" : true,
    "rule_priority": 1001,
    "action": "DNAT",
    "match_destination_network": $pks_uaa_system_domain_ip,
    "translated_network" : $pks_controller_ip
  }
  '
)

snat_rule_payload=$( jq -n \
  --arg pks_controller_ip $PKS_CONTROLLER_IP \
  --arg pks_uaa_system_domain_ip $PKS_UAA_SYSTEM_DOMAIN_IP \
  '
  {
    "resource_type": "NatRule",
    "enabled" : true,
    "rule_priority": 1001,
    "action": "SNAT",
    "match_source_network": $pks_controller_ip,
    "translated_network" : $pks_uaa_system_domain_ip
  }
  '
)

dnat_output=$(curl -k -u "$NSX_API_USER:$NSX_API_PASSWORD" \
      https://$NSX_API_MANAGER:443/api/v1/logical-routers/${PKS_T0_ROUTER_ID}/nat/rules \
      -X POST \
      -H 'Content-type: application/json' \
      -d "$dnat_rule_payload")
if [ "$?" != 0 ]; then
  echo "Problem in creating DNAT entry: $dnat_output"
  exit 1
fi

dnat_output=$(curl -k -u "$NSX_API_USER:$NSX_API_PASSWORD" \
      https://$NSX_API_MANAGER:443/api/v1/logical-routers/${PKS_T0_ROUTER_ID}/nat/rules \
      -X POST \
      -H 'Content-type: application/json' \
      -d "$snat_rule_payload")
if [ "$?" != 0 ]; then
  echo "Problem in creating SNAT entry: $snat_output"
  exit 1
fi

echo "Created NAT rules for PKS Controller API IP $PKS_CONTROLLER_IP to be accessible from $PKS_UAA_SYSTEM_DOMAIN_IP over the NSX-T Manager's T0 Router $PKS_T0_ROUTER_NAME"
