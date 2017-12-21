#!/bin/bash

set -eu

NETWORK=$(
  jq -n \
    --arg network_name "$NETWORK_NAME" \
    --arg other_azs "$DEPLOYMENT_NW_AZS" \
    --arg singleton_az "$MYSQL_SINGLETON_JOB_AZ" \
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


PROPERTIES=$(cat <<-EOF
{
  ".deploy-service-broker.broker_max_instances": {
    "value": 100
  },
  ".deploy-service-broker.disable_cert_check": {
    "value": true
  }
}
EOF
)

TILE_RELEASE=`om-linux -t https://$OPSMAN_DOMAIN_OR_IP_ADDRESS -u $OPS_MGR_USR -p $OPS_MGR_PWD -k available-products | grep p-mysql`

PRODUCT_NAME=`echo $TILE_RELEASE | cut -d"|" -f2 | tr -d " "`
PRODUCT_VERSION=`echo $TILE_RELEASE | cut -d"|" -f3 | tr -d " "`

om-linux -t https://$OPSMAN_DOMAIN_OR_IP_ADDRESS -u $OPS_MGR_USR -p $OPS_MGR_PWD -k stage-product -p $PRODUCT_NAME -v $PRODUCT_VERSION

PROPERTIES=$(cat <<-EOF
{
  ".proxy.static_ips": {
    "value": "$TILE_MYSQL_PROXY_IPS"
  },
  ".properties.syslog": {
    "value": "disabled"
  },
  ".cf-mysql-broker.bind_hostname": {
    "value": "$TILE_MYSQL_PROXY_VIP"
  },
  ".properties.optional_protections.enable.recipient_email": {
    "value": "$TILE_MYSQL_MONITOR_EMAIL"
  }
}
EOF
)

RESOURCES=$(cat <<-EOF
{
  "proxy": {
    "instance_type": {"id": "automatic"},
    "instances" : $TILE_MYSQL_PROXY_INSTANCES
  },
  "backup-prepare": {
    "instance_type": {"id": "automatic"},
    "instances" : $TILE_MYSQL_BACKUP_PREPARE_INSTANCES
  },
  "monitoring": {
    "instance_type": {"id": "automatic"},
    "instances" : $TILE_MYSQL_MONITORING_INSTANCES
  },
  "cf-mysql-broker": {
    "instance_type": {"id": "automatic"},
    "instances" : $TILE_MYSQL_BROKER_INSTANCES
  }
}
EOF
)

om-linux -t https://$OPSMAN_DOMAIN_OR_IP_ADDRESS \
  -u $OPS_MGR_USR \
  -p $OPS_MGR_PWD \
  -k configure-product \
  -n $PRODUCT_NAME \
  -p "$PROPERTIES" \
  -pn "$NETWORK" \
  -pr "$RESOURCES"

PRODUCT_GUID=$(om-linux -t https://$OPSMAN_DOMAIN_OR_IP_ADDRESS -k -u $OPS_MGR_USR -p $OPS_MGR_PWD \
                     curl -p "/api/v0/staged/products" -x GET \
                     | jq '.[] | select(.installation_name | contains("p-mysql")) | .guid' | tr -d '"')

echo "applying errand configuration"
sleep 6
MYSQL_ERRANDS=$(cat <<-EOF
{"errands":[
  {"name":"broker-registrar","post_deploy":"when-changed"},
  {"name":"smoke-tests","post_deploy":"when-changed"}
]
}
EOF
)

om-linux -t https://$OPSMAN_DOMAIN_OR_IP_ADDRESS -k -u $OPS_MGR_USR -p $OPS_MGR_PWD \
                          curl -p "/api/v0/staged/products/$PRODUCT_GUID/errands" \
                          -x PUT -d "$MYSQL_ERRANDS"
