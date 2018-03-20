#!/bin/bash

#!/bin/bash

export NSX_HOST=${NSX_ADDRESS}
export USER_CRED=${NSX_USERNAME}:${NSX_PASSWORD}


function get_response_from_nsx() (
  api_endpoint=$1
  id=$2
  out=$(curl -k -u ${USER_CRED} ${NSX_HOST}${api_endpoint}/${id} 2>/dev/null )
  echo $out | jq .
)

function get_routers_response_from_nsx() (
  out=$(get_response_from_nsx /api/v1/logical-routers)
  echo $out | jq -r '.results[] | select(.failover_mode)' > system_routers.json
  t0Router_ids=$( cat system_routers.json | jq -r '. | select(.router_type | contains("TIER0")) | .id')

  for router_id in $t0Router_ids
  do
	curl -k -u ${USER_CRED} $NSX_HOST/api/v1/logical-routers/${router_id} 2>/dev/null  > t0Router.json
	router_name=$(cat t0Router.json | jq -r '.display_name')
	mv t0Router.json t0Router-${router_name}.json
    curl -k -u ${USER_CRED} $NSX_HOST/api/v1/logical-routers/${router_id}/nat/rules 2>/dev/null  > t0Router-${router_name}-nat-rules.json  
  done

  t1Router_ids=$( cat system_routers.json | jq -r '. | select(.router_type | contains("TIER1")) | .id')

  for router_id in $t1Router_ids
  do
	curl -k -u ${USER_CRED} $NSX_HOST/api/v1/logical-routers/${router_id} 2>/dev/null  > t1Router.json
	router_name=$(cat t1Router.json | jq -r '.display_name')
	mv t1Router.json t1Router-${router_name}.json
    curl -k -u ${USER_CRED} $NSX_HOST/api/v1/logical-routers/${router_id}/nat/rules 2>/dev/null  > t1Router-${router_name}-nat-rules.json  
  	curl -k -u ${USER_CRED} $NSX_HOST/api/v1/logical-routers/${router_id}/routing/advertisement 2>/dev/null  > t1Router-${router_name}-route-adver.json
  done
)

echo "Going against NSX-T Mgr at ${NSX_HOST}"

COMPONENT_PAIRS="ip-blocks:ipam-pool-ip-blocks"
COMPONENT_PAIRS="$COMPONENT_PAIRS|logical-routers:logical-routers"
COMPONENT_PAIRS="$COMPONENT_PAIRS|edge-clusters:edge-clusters"
COMPONENT_PAIRS="$COMPONENT_PAIRS|firewall/sections:firewall-sections"
COMPONENT_PAIRS="$COMPONENT_PAIRS|ip-sets:group-ip-sets"
COMPONENT_PAIRS="$COMPONENT_PAIRS|host-switch-profiles:host-switch-profiles"
COMPONENT_PAIRS="$COMPONENT_PAIRS|ip-pools:ip-pools"
COMPONENT_PAIRS="$COMPONENT_PAIRS|loadbalancer/pools:lbr-pools"
COMPONENT_PAIRS="$COMPONENT_PAIRS|loadbalancer/services:lbr-services"
COMPONENT_PAIRS="$COMPONENT_PAIRS|loadbalancer/virtual-servers:lbr-virtual-servers"
COMPONENT_PAIRS="$COMPONENT_PAIRS|logical-router-ports:logical-router-ports"
COMPONENT_PAIRS="$COMPONENT_PAIRS|logical-ports:logical-ports"
COMPONENT_PAIRS="$COMPONENT_PAIRS|logical-switches:logical-switches"
COMPONENT_PAIRS="$COMPONENT_PAIRS|transport-zones:transport-zones"
COMPONENT_PAIRS="$COMPONENT_PAIRS|transport-nodes:transport-nodes "
COMPONENT_PAIRS="$COMPONENT_PAIRS|logical-router-ports:logical-router-ports"
COMPONENT_PAIRS="$COMPONENT_PAIRS|logical-router-ports:logical-router-ports"

get_routers_response_from_nsx

for component_pair in $(echo $COMPONENT_PAIRS | sed -e 's/|/ /g')
do
	component_path=$(echo $component_pair | awk -F ':' '{print $1}' )
	component_response=$(echo $component_pair | awk -F ':' '{print $2}' )
	get_response_from_nsx /api/v1/${component_path} > ${component_response}.json
done

for edge_transport_node_id in $(cat transport-nodes.json| jq -r '.results[] | select ( .host_switch_spec.host_switches | length == 2 ) | .id') 
do
  get_response_from_nsx /api/v1/transport-nodes/${edge_transport_node_id} > transport-node-edge.json
  edge_node_name=$(cat transport-node-edge.json | jq -r .display_name)
  mv transport-node-edge.json transport-node-edge-${edge_node_name}.json
done

get_response_from_nsx /api/v1/logical-switches > logical-switches.json
cat logical-switches.json | jq '.results[] | select (.tags| length == 0)' > user-created-logical-switches.json
for vlan_id in $(cat logical-switches.json | jq -r '.results[] | select (.vlan == 0) | .id')
do
  get_response_from_nsx /api/v1/logical-switches/${vlan_id} > vlan-uplink-switch.json 
  vlan_switch_name=$(cat vlan-uplink-switch.json | jq -r .display_name)
  mv vlan-uplink-switch.json ${vlan_switch_name}-uplink-switch.json 
done


