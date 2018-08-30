#!/bin/bash

function check_bosh_version {

  export BOSH_PRODUCT_VERSION=$(om-linux \
                                  -t https://$OPSMAN_DOMAIN_OR_IP_ADDRESS \
                                  -u $OPSMAN_USERNAME \
                                  -p $OPSMAN_PASSWORD \
                                  -k curl -p "/api/v0/deployed/products" \
                                  2>/dev/null \
                                  | jq '.[] | select(.installation_name=="p-bosh") | .product_version' \
                                  | tr -d '"')
  export BOSH_MAJOR_VERSION=$(echo $BOSH_PRODUCT_VERSION | awk -F '.' '{print $1}' )
  export BOSH_MINOR_VERSION=$(echo $BOSH_PRODUCT_VERSION | awk -F '.' '{print $2}' | sed -e 's/-.*//g' )

  echo "Bosh Product version: $BOSH_PRODUCT_VERSION"
}

function check_available_product_version {

  local product_code="$1"
  TILE_RELEASE=$(om-linux \
                    -t https://$OPSMAN_DOMAIN_OR_IP_ADDRESS \
                    -u $OPSMAN_USERNAME \
                    -p $OPSMAN_PASSWORD \
                    -k available-products 2>/dev/null \
                    | grep $product_code)

  export PRODUCT_NAME=$(echo $TILE_RELEASE | cut -d"|" -f2 | tr -d " ")
  # Take the last version (most recent one instead of first occuring version if there are multiple versions)
  export PRODUCT_VERSION=$(echo $TILE_RELEASE |  tr '\n' ' ' | awk -F '|' '{print $(NF-1) }' | tr -d ' ' )
  export PRODUCT_MAJOR_VERSION=$(echo $PRODUCT_VERSION | awk -F '.' '{print $1}' )
  export PRODUCT_MINOR_VERSION=$(echo $PRODUCT_VERSION | awk -F '.' '{print $2}' | sed -e 's/-.*//g' )

  echo "Available Product name: $PRODUCT_NAME and version: $PRODUCT_VERSION"
}

function check_staged_product_guid {

  local product_code="$1"
  # jq contains does not appear to be able to use env variable
  # export PRODUCT_GUID=$(om-linux \
  #                 -t https://$OPSMAN_DOMAIN_OR_IP_ADDRESS \
  #                 -u $OPSMAN_USERNAME \
  #                 -p $OPSMAN_PASSWORD \
  #                 -k curl -p "/api/v0/staged/products" \
  #                 -x GET \
  #                 | jq --arg product_code $product_code '.[] | select(.installation_name | contains("$product_code")) | .guid' \
  #                 | tr -d '"')

  export PRODUCT_GUID=$(om-linux \
                  -t https://$OPSMAN_DOMAIN_OR_IP_ADDRESS \
                  -u $OPSMAN_USERNAME \
                  -p $OPSMAN_PASSWORD \
                  -k curl -p "/api/v0/staged/products" \
                  -x GET 2>/dev/null \
                  | grep "guid" | grep "\"$product_code" \
                  | awk -F '"' '{print $4}' )

   om-linux \
        -t https://$OPSMAN_DOMAIN_OR_IP_ADDRESS \
        -u $OPSMAN_USERNAME \
        -p $OPSMAN_PASSWORD -k \
        curl -p "/api/v0/staged/products/${PRODUCT_GUID}/properties" \
        2>/dev/null > /tmp/staged_product_${PRODUCT_GUID}.json

  echo "Staged Product: $product_code with guid: $PRODUCT_GUID"
}

function check_installed_cf_version {

  export CF_PRODUCT_VERSION=$(om-linux \
                            -t https://$OPSMAN_DOMAIN_OR_IP_ADDRESS \
                            -u $OPSMAN_USERNAME \
                            -p $OPSMAN_PASSWORD -k \
                            curl -p "/api/v0/staged/products" \
                            -x GET  2>/dev/null \
                            | jq '.[] | select(.installation_name | contains("cf-")) | .product_version' \
                            | tr -d '"')

  export CF_MAJOR_VERSION=$(echo $cf_product_version | awk -F '.' '{print $1}' )
  export CF_MINOR_VERSION=$(echo $cf_product_version | awk -F '.' '{print $2}' | sed -e 's/-.*//g')

  echo "Installed CF (Full) version: $CF_PRODUCT_VERSION"

}

function check_installed_srt_version {

  export SRT_PRODUCT_VERSION=$(om-linux \
                            -t https://$OPSMAN_DOMAIN_OR_IP_ADDRESS \
                            -u $OPSMAN_USERNAME \
                            -p $OPSMAN_PASSWORD -k \
                            curl -p "/api/v0/staged/products" \
                            -x GET  2>/dev/null \
                            | jq '.[] | select(.installation_name | contains("srt-")) | .product_version' \
                            | tr -d '"')

  export SRT_MAJOR_VERSION=$(echo $cf_product_version | awk -F '.' '{print $1}' )
  export SRT_MINOR_VERSION=$(echo $cf_product_version | awk -F '.' '{print $2}' | sed -e 's/-.*//g')
  echo "Installed CF (SRT) version: $SRT_PRODUCT_VERSION"
}
