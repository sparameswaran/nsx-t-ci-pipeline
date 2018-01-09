#!/bin/bash -eu

if [[ -n "$NO_PROXY" ]]; then
  echo "$OM_IP $OPSMAN_DOMAIN_OR_IP_ADDRESS" >> /etc/hosts
fi

# Should the slug contain more than one product, pick only the first.
FILE_PATH=`find ./s3-tile -name *.pivotal | sort | head -1`

tile_metadata=$(unzip -l $FILE_PATH | grep "metadata" | grep "ml$" | awk '{print $NF}')
STEMCELL_VERSION_FROM_TILE=$(unzip -p $FILE_PATH $tile_metadata | grep -A4 stemcell | grep version: \
                                               | grep -Ei "[0-9]+" | awk '{print $NF}' | sed "s/'//g" )


source nsx-t-ci-pipeline/functions/upload_stemcell.sh
upload_stemcells "$STEMCELL_VERSION_FROM_TILE"

om-linux -t https://$OPSMAN_DOMAIN_OR_IP_ADDRESS \
         -u $OPSMAN_USERNAME \
         -p $OPSMAN_PASSWORD \
         -k --request-timeout 3600 \
         upload-product -p $FILE_PATH
