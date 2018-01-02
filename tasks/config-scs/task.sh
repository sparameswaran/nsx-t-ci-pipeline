#!/bin/bash

set -eu

NETWORK=$(
  jq -n \
    --arg network_name "$NETWORK_NAME" \
    --arg other_azs "$DEPLOYMENT_NW_AZS" \
    --arg singleton_az "$SCS_SINGLETON_JOB_AZ" \
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

TILE_RELEASE=`om-linux -t https://$OPSMAN_DOMAIN_OR_IP_ADDRESS -u $OPSMAN_USERNAME -p $OPSMAN_PASSWORD -k available-products | grep p-spring-cloud-services`

PRODUCT_NAME=`echo $TILE_RELEASE | cut -d"|" -f2 | tr -d " "`
PRODUCT_VERSION=`echo $TILE_RELEASE | cut -d"|" -f3 | tr -d " "`

om-linux -t https://$OPSMAN_DOMAIN_OR_IP_ADDRESS -u $OPSMAN_USERNAME -p $OPSMAN_PASSWORD -k stage-product -p $PRODUCT_NAME -v $PRODUCT_VERSION

om-linux -t https://$OPSMAN_DOMAIN_OR_IP_ADDRESS -u $OPSMAN_USERNAME -p $OPSMAN_PASSWORD -k configure-product -n $PRODUCT_NAME -p "$PROPERTIES"  -pn "$NETWORK"

PRODUCT_GUID=$(om-linux -t https://$OPSMAN_DOMAIN_OR_IP_ADDRESS -k -u $OPSMAN_USERNAME -p $OPSMAN_PASSWORD \
                     curl -p "/api/v0/staged/products" -x GET \
                     | jq '.[] | select(.installation_name | contains("p-spring-cloud-services")) | .guid' | tr -d '"')

echo "applying errand configuration"
sleep 6
SCS_ERRANDS=$(cat <<-EOF
{"errands":[
{"name":"deploy-service-broker","post_deploy":"when-changed"},
{"name":"register-service-broker","post_deploy":"when-changed"},
{"name":"run-smoke-tests","post_deploy":"when-changed"}
]
}
EOF
)

om-linux -t https://$OPSMAN_DOMAIN_OR_IP_ADDRESS -k -u $OPSMAN_USERNAME -p $OPSMAN_PASSWORD \
                          curl -p "/api/v0/staged/products/$PRODUCT_GUID/errands" \
                          -x PUT -d "$SCS_ERRANDS"
