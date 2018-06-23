#!/bin/bash
set -eu

export ROOT_DIR=`pwd`
source $ROOT_DIR/nsx-t-ci-pipeline/functions/copy_binaries.sh
source $ROOT_DIR/nsx-t-ci-pipeline/functions/check_versions.sh
source $ROOT_DIR/nsx-t-ci-pipeline/functions/generate_cert.sh
source $ROOT_DIR/nsx-t-ci-pipeline/functions/yaml2json.sh
source $ROOT_DIR/nsx-t-ci-pipeline/functions/check_null_variables.sh

function get_value() {
  rule=$1
  field=$2
  echo $(echo $rule | jq -r ".${field}" )
}

function check_match_in_nat_rules {
  rule1=$1
  rule2=$2

  for key in  'action' 'match_source_network' 'translated_network' 'match_destination_network'
  do
    value1=$(get_value "$rule1" 'action')
    value2=$(get_value "$rule2" 'action')
    if [ "$value1" != "$value2" ]; then
      echo 1
    fi
  done
  echo 0
}


echo "Note - pre-requisite for this task to work:"
echo "- Your PKS API endpoint [${PKS_UAA_DOMAIN_PREFIX}.${PKS_SYSTEM_DOMAIN}] should be resolvable to $PKS_UAA_SYSTEM_DOMAIN_IP, routable and accessible via the NSX-T network."

if [ "$PKS_UAA_SYSTEM_DOMAIN_IP" == "" ]; then
  echo "No IP or value set for PKS_UAA_SYSTEM_DOMAIN_IP, skipping creation of NAT rule on NSX Manager from the PKS API Domain to internal PKS Controller IP!!"
  exit 0
fi

check_dns_lookup=$(nslookup ${PKS_UAA_DOMAIN_PREFIX}.${PKS_SYSTEM_DOMAIN})
if [ "$?" != "0" ]; then
  echo "Warning!! Unable to resolve ${PKS_UAA_DOMAIN_PREFIX}.${PKS_SYSTEM_DOMAIN}"
  echo "Proceeding with the assumption that ${PKS_UAA_DOMAIN_PREFIX}.${PKS_SYSTEM_DOMAIN} would resolve to IP: $PKS_UAA_SYSTEM_DOMAIN_IP ultimately"
  echo ""
else
  resolved_ip=$(echo $check_dns_lookup | grep -A1 api | grep Address | awk '{print $2}' )
  echo "Resolved ${PKS_UAA_DOMAIN_PREFIX}.${PKS_SYSTEM_DOMAIN} to $resolved_ip "
  if [ "$resolved_ip" != "$PKS_UAA_SYSTEM_DOMAIN_IP" ]; then
    echo "Warning!! ${PKS_UAA_DOMAIN_PREFIX}.${PKS_SYSTEM_DOMAIN} not resolving to $PKS_UAA_SYSTEM_DOMAIN_IP but instead to $resolved_ip!!"
    echo "Proceeding with the assumption that ${PKS_UAA_DOMAIN_PREFIX}.${PKS_SYSTEM_DOMAIN} would resolve to IP: $PKS_UAA_SYSTEM_DOMAIN_IP ultimately"
    echo ""
  fi
fi

echo "Retrieving PKS Controller IP from Ops Manager [https://$OPSMAN_DOMAIN_OR_IP_ADDRESS]..."

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

echo "Discovered PKS Controller running at: $PKS_CONTROLLER_IP!!"
echo ""

echo "Going to create NAT entry between External Address: $PKS_UAA_SYSTEM_DOMAIN_IP and PKS Controller Internal IP: $PKS_CONTROLLER_IP"
echo "   on T0Router: $PKS_T0_ROUTER_NAME on NSX Manager: $NSX_API_MANAGER"
echo ""

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

insert_dnat_rule=1
insert_snat_rule=1

existing_nat_rules_json=$(curl -k -u "$NSX_API_USER:$NSX_API_PASSWORD" \
        https://$NSX_API_MANAGER:443/api/v1/logical-routers/${PKS_T0_ROUTER_ID}/nat/rules)
#echo "Full existing rules: $existing_nat_rules_json"

number_of_rules=$( echo $existing_nat_rules_json | jq '.result_count' )
echo number_of_rules rules: $number_of_rules
max_index=$(expr $number_of_rules - 1)
for index in $(seq 0 $max_index )
do
  nat_rule=$( echo $existing_nat_rules_json | jq --argjson index $index '.results[$index]' )
  #echo "Nat rule: $nat_rule"

  translated_ip=$(echo $nat_rule | jq -r .translated_network )

  nat_rule_type=$( echo $nat_rule | jq -r .action )

  if [ "$translated_ip" == "$PKS_CONTROLLER_IP" -o "$translated_ip" == "$PKS_UAA_SYSTEM_DOMAIN_IP" ]; then

    if [ "$nat_rule_type" == "DNAT" ]; then
      match=$(check_match_in_nat_rules "$nat_rule" "$dnat_rule_payload")
      if [ "$match" == "0" ]; then
        #echo "Found Match for dnat rule: $nat_rule"
        insert_dnat_rule=0
      fi
    else
      match=$(check_match_in_nat_rules "$nat_rule" "$snat_rule_payload")
      if [ "$match" == "0" ]; then
        #echo "Found Match for snat rule: $nat_rule"
        insert_snat_rule=0
      fi
    fi
  fi

done

if [ $insert_dnat_rule -ne 0 ]; then
  dnat_output=$(curl -k -u "$NSX_API_USER:$NSX_API_PASSWORD" \
        https://$NSX_API_MANAGER:443/api/v1/logical-routers/${PKS_T0_ROUTER_ID}/nat/rules \
        -X POST \
        -H 'Content-type: application/json' \
        -d "$dnat_rule_payload")
  if [ "$?" != 0 ]; then
    echo "Problem in creating DNAT entry: $dnat_output"
    exit 1
  fi
else
  echo "Found existing dnat rule that matches already, skipping rule creation in NATs on T0Router"
fi

if [ $insert_snat_rule -ne 0 ]; then
  snat_output=$(curl -k -u "$NSX_API_USER:$NSX_API_PASSWORD" \
        https://$NSX_API_MANAGER:443/api/v1/logical-routers/${PKS_T0_ROUTER_ID}/nat/rules \
        -X POST \
        -H 'Content-type: application/json' \
        -d "$snat_rule_payload")
  if [ "$?" != 0 ]; then
    echo "Problem in creating SNAT entry: $snat_output"
    exit 1
  fi
else
  echo "Found existing snat rule that matches already, skipping rule creation in NATs on T0Router"
fi

echo ""
echo "DNS Entry of ${PKS_UAA_DOMAIN_PREFIX}.${PKS_SYSTEM_DOMAIN} expected to resolve External IP: $PKS_UAA_SYSTEM_DOMAIN_IP"
echo "This ip should be routable via the T0 Router $PKS_T0_ROUTER_NAME" on $NSX_API_MANAGER
echo ""
echo "Created NAT rules for PKS Controller API IP $PKS_CONTROLLER_IP to be accessible from external IP: $PKS_UAA_SYSTEM_DOMAIN_IP"
echo "Note: Do a sanity check of the NAT rules in NSX Manager and delete any duplicate or older/wrong entries!!"
echo ""
