#!/bin/bash

set -eu

# Use om-linux cli to pull down creds to cf 
# or other products that is being requested


# om returned creds looks like following
# +----------+----------------------------------+
# | identity |             password             |
# +----------+----------------------------------+
# | admin    | asfasfasf-asdfafaf               |
# +----------+----------------------------------+
#

# We are mainly looking for these two:
# .uaa.admin_credentials and .uaa.admin_client_credentials

function get_cred {
    local prod_cred_type=$1

    local identity=$(echo $prod_cred_type | sed -e 's/.uaa.//;s/_credentials//')
    prod_creds=$(om-linux \
              --target https://$OPSMAN_DOMAIN_OR_IP_ADDRESS \
              --skip-ssl-validation \
              --username $OPSMAN_USERNAME \
              --password $OPSMAN_PASSWORD \
                credentials \
              --product-name $PRODUCT_NAME \
              --credential-reference $prod_cred_type \
                  | grep -v -- "---" \
                  | grep -v identity \
                  | sed -e 's/|//g' \
                  | awk '{ print $2  }' )
    echo "\"$identity\" : \"$prod_creds\" "
}

rm -rf /tmp/creds_payload.json
for cred_type in $(echo $PRODUCT_CREDENTIAL_REFERENCES | sed -e 's/,/ /g')
do
  if [ -e /tmp/creds_payload.json ]; then
    echo "," >> /tmp/creds_payload.json
  fi
  get_cred $cred_type >> /tmp/creds_payload.json
done
PROD_CREDS=$(cat /tmp/creds_payload.json)

product_creds_configuration=$(cat <<-EOF
{
    $PROD_CREDS
}
EOF
)

echo $product_creds_configuration > ./prod_creds_config.json

# We can expect admin and admin_client in the product-creds-config json payload
# Sample: 
# { "admin" : "value1" , "admin_client" : "value2" }

# CF_ADMIN should be set to admin, stripping off the quotes using -r raw option
CF_ADMIN=admin
CF_ADMIN_CRED=$(cat ./prod_creds_config.json | jq -r '.admin' )
CF_ADMIN_SECRET=$(cat ./prod_creds_config.json | jq -r '.admin_client' )
UAA_TCP_CLIENT_NAME="tcp_emitter"
UAA_TCP_PASSWORD=$(cat ./prod_creds_config.json | jq -r '.tcp_emitter' )

jq -n --arg cf_admin "$CF_ADMIN" \
      --arg cf_admin_cred "$CF_ADMIN_CRED" \
      --arg cf_admin_secret "$CF_ADMIN_SECRET" \
      --arg sys_domain "api.$SYSTEM_DOMAIN" \
      --arg apps_domain "$APPS_DOMAIN" \
      --arg uaa_domain "https://uaa.$SYSTEM_DOMAIN" \
      --arg uaa_tcp_client_name $UAA_TCP_CLIENT_NAME \
      --arg uaa_tcp_client_password $UAA_TCP_PASSWORD \
      '{ 
      	 "admin_user": $cf_admin, 
         "admin_password": $cf_admin_cred, 
         "admin_secret": $cf_admin_secret,
         "api": $sys_domain, 
         "apps_domain": $apps_domain,
         "oauth": {
          "token_endpoint": $uaa_domain,
          "client_name": $uaa_tcp_client_name,
          "client_secret": $uaa_tcp_client_password,
          "port": 443,
          "skip_ssl_validation": true
          }
      }'                               \
       > /tmp/cf_creds_config.json

echo $CONFIG > /tmp/base_cats_config.json

cat /tmp/cf_creds_config.json /tmp/base_cats_config.json \
    | jq -s add > integration-config/integration_config.json

