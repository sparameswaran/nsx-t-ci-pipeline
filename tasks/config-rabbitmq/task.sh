#!/bin/bash

set -eu

NETWORK=$(
  jq -n \
    --arg network_name "$NETWORK_NAME" \
    --arg service_network_name "$SERVICE_NETWORK_NAME" \
    --arg other_azs "$DEPLOYMENT_NW_AZS" \
    --arg singleton_az "$RABBITMQ_SINGLETON_JOB_AZ" \
    '
    {
      "service_network": {
        "name": $service_network_name
      },
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

TILE_RELEASE=`om-linux -t https://$OPSMAN_DOMAIN_OR_IP_ADDRESS -u $OPSMAN_USERNAME -p $OPSMAN_PASSWORD -k available-products | grep p-rabbitmq`

PRODUCT_NAME=`echo $TILE_RELEASE | cut -d"|" -f2 | tr -d " "`
PRODUCT_VERSION=`echo $TILE_RELEASE | cut -d"|" -f3 | tr -d " "`

om-linux -t https://$OPSMAN_DOMAIN_OR_IP_ADDRESS -u $OPSMAN_USERNAME -p $OPSMAN_PASSWORD -k stage-product -p $PRODUCT_NAME -v $PRODUCT_VERSION

PROPERTIES=$(cat <<-EOF
{
  ".rabbitmq-haproxy.static_ips": {
    "value": "$RABBITMQ_TILE_STATIC_IPS"
  },
  ".rabbitmq-server.server_admin_credentials": {
    "value": {
      "identity": "$TILE_RABBIT_ADMIN_USER",
      "password": "$TILE_RABBIT_ADMIN_PASSWD"
    }
  },
  ".properties.syslog_selector": {
    "value": "disabled"
  },
  ".properties.on_demand_broker_plan_1_cf_service_access": {
    "value": "enable"
  },
  ".properties.on_demand_broker_plan_1_instance_quota": {
    "value": 10
  },
  ".properties.on_demand_broker_plan_1_rabbitmq_az_placement": {
    "value": ["$RABBITMQ_SINGLETON_JOB_AZ"]
  },
  ".properties.on_demand_broker_plan_1_disk_limit_acknowledgement": {
    "value": ["acknowledge"]
  },
  ".properties.disk_alarm_threshold": {
    "value": "mem_relative_1_0"
  },
  ".rabbitmq-broker.dns_host": {
    "value": "$RABBITMQ_TILE_LBR_IP"
  }
}
EOF
)

RESOURCES=$(cat <<-EOF
{
  "rabbitmq-haproxy": {
    "instance_type": {"id": "automatic"},
    "instances" : $TILE_RABBIT_PROXY_INSTANCES
  },
  "rabbitmq-server": {
    "instance_type": {"id": "automatic"},
    "instances" : $TILE_RABBIT_SERVER_INSTANCES
  }
}
EOF
)

om-linux -t https://$OPSMAN_DOMAIN_OR_IP_ADDRESS \
  -u $OPSMAN_USERNAME \
  -p $OPSMAN_PASSWORD \
  -k configure-product \
  -n $PRODUCT_NAME \
  -pn "$NETWORK" \
  -pr "$RESOURCES"


om-linux -t https://$OPSMAN_DOMAIN_OR_IP_ADDRESS \
  -u $OPSMAN_USERNAME \
  -p $OPSMAN_PASSWORD \
  -k configure-product \
  -n $PRODUCT_NAME \
  -p "$PROPERTIES" \

PRODUCT_GUID=$(om-linux -t https://$OPSMAN_DOMAIN_OR_IP_ADDRESS -k -u $OPSMAN_USERNAME -p $OPSMAN_PASSWORD \
                     curl -p "/api/v0/staged/products" -x GET \
                     | jq '.[] | select(.installation_name | contains("p-rabbitmq")) | .guid' | tr -d '"')

echo "applying errand configuration"
sleep 6
RABBITMQ_ERRANDS=$(cat <<-EOF
{"errands":[
  {"name":"broker-registrar","post_deploy":"when-changed"}
]
}
EOF
)

om-linux -t https://$OPSMAN_DOMAIN_OR_IP_ADDRESS -k -u $OPSMAN_USERNAME -p $OPSMAN_PASSWORD \
                          curl -p "/api/v0/staged/products/$PRODUCT_GUID/errands" \
                          -x PUT -d "$RABBITMQ_ERRANDS"
