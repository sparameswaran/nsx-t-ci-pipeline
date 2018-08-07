#!/bin/bash -eu

STEMCELL_VERSION_FROM_PRODUCT_METADATA=""
if [ -e "./pivnet-product/metadata.json" ]; then
  STEMCELL_VERSION_FROM_PRODUCT_METADATA=$(
    cat ./pivnet-product/metadata.json |
    jq --raw-output \
      '
      [
        .Dependencies[]
        | select(.Release.Product.Name | contains("Stemcells"))
        | .Release.Version
      ]
      | map(split(".") | map(tonumber))
      | transpose | transpose
      | max // empty
      | map(tostring)
      | join(".")
      '
  )
fi

# From Tile metadata.json (from pivnet):
# - id: 69341
#   specifier: "97"
#   product_slug: stemcells

# From Tile metadata.yml:
# stemcell_criteria:
#   os: ubuntu-trusty
#   requires_cpi: false
#   version: '3263'

# For Xenial:
# From Tile metadata.json (from pivnet):
# - id: 69341
#   specifier: "97"
#   product_slug: stemcells-ubuntu-xenial

# From Tile metadata.yml:
# stemcell_criteria:
#   os: ubuntu-xenial
#   version: "97"

tile_metadata=$(unzip -l pivnet-product/*.pivotal | grep "metadata" | grep "ml$" | awk '{print $NF}')
STEMCELL_VERSION_FROM_TILE=$(unzip -p pivnet-product/*.pivotal $tile_metadata | grep -A5 "stemcell_criteria:"  \
                                  | grep "version:" | grep -Ei "[0-9]+{2}" | awk '{print $NF}' | sed "s/'//g;s/\"//g" )
STEMCELL_OS_FROM_TILE=$(unzip -p pivnet-product/*.pivotal $tile_metadata | grep -A5 "stemcell_criteria:"  \
                                  | grep "os:" | awk '{print $NF}' | sed "s/'//g;s/\"//g" )

SC_FILE_PATH=$(find . -name "bosh*.tgz" | sort | head -1 || true)
if [ "$SC_FILE_PATH" != "" ]; then
  echo "Uploading cached stemcell: $SC_FILE_PATH to Ops Mgr"
  om-linux -t https://$OPSMAN_DOMAIN_OR_IP_ADDRESS \
           -u $OPSMAN_USERNAME \
           -p $OPSMAN_PASSWORD \
           -k --request-timeout 3600 \
           upload-stemcell -s $SC_FILE_PATH
else
  source nsx-t-ci-pipeline/functions/upload_stemcell.sh
  echo "No cached stemcell; Will download and then upload stemcell: $SC_FILE_PATH to Ops Mgr"
  upload_stemcells $STEMCELL_OS_FROM_TILE "$STEMCELL_VERSION_FROM_TILE $STEMCELL_VERSION_FROM_PRODUCT_METADATA"
fi

# Should the slug contain more than one product, pick only the first.
FILE_PATH=`find ./pivnet-product -name *.pivotal | sort | head -1`
om-linux -t https://$OPSMAN_DOMAIN_OR_IP_ADDRESS \
         -u $OPSMAN_USERNAME \
         -p $OPSMAN_PASSWORD \
         -k --request-timeout 3600 \
         upload-product -p $FILE_PATH
