#!/bin/bash -eu

export ROOT_DIR=`pwd`
source $ROOT_DIR/nsx-t-ci-pipeline/functions/copy_binaries.sh
source $ROOT_DIR/nsx-t-ci-pipeline/functions/check_versions.sh
source $ROOT_DIR/nsx-t-ci-pipeline/functions/generate_cert.sh
source $ROOT_DIR/nsx-t-ci-pipeline/functions/yaml2json.sh
source $ROOT_DIR/nsx-t-ci-pipeline/functions/check_null_variables.sh


# Should the slug contain more than one product, pick only the first.
TILE_FILE_PATH=`find ./s3-tile -name *.pivotal | sort | head -1`

tile_metadata=$(unzip -l $TILE_FILE_PATH | grep "metadata" | grep "ml$" | awk '{print $NF}')
stemcell_version_reqd=$(unzip -p $TILE_FILE_PATH $tile_metadata | grep -A4 stemcell | grep version: \
                                               | grep -Ei "[0-9]{4,}" | awk '{print $NF}' | sed "s/'//g" )


if [ -n "$stemcell_version_reqd" ]; then
 diagnostic_report=$(
   om-linux \
     --target https://$OPSMAN_DOMAIN_OR_IP_ADDRESS \
     --username $OPSMAN_USERNAME \
     --password $OPSMAN_PASSWORD \
     --skip-ssl-validation \
     curl --silent --path "/api/v0/diagnostic_report"
 )

 stemcell=$(
   echo $diagnostic_report |
   jq \
     --arg version "$stemcell_version_reqd" \
     --arg glob "$IAAS" \
   '.stemcells[] | select(contains($version) and contains($glob))'
 )
 if [[ -z "$stemcell" ]]; then
   echo "Downloading stemcell $stemcell_version_reqd"

   pivnet-cli login --api-token="$PIVNET_API_TOKEN"
set +e
   pivnet-cli download-product-files -p "stemcells" -r $stemcell_version_reqd -g "*${IAAS}*" --accept-eula
   if [ $? != 0 ]; then
     min_version=$(echo $stemcell_version_reqd | awk -F '.' '{print $2}')
     if [ "$min_version" == "" ]; then
       for min_version in $(seq 0  100)
       do
          pivnet-cli download-product-files -p "stemcells" -r $stemcell_version_reqd.$min_version -g "*${IAAS}*" --accept-eula && break
       done
     else
       echo "Stemcell version $stemcell_version_reqd not found !!, giving up"
       exit 1
     fi
   fi
set -e

   SC_FILE_PATH=`find ./ -name *.tgz`

   if [ ! -f "$SC_FILE_PATH" ]; then
     echo "Stemcell file not found!"
     exit 1
   fi

   om-linux -t https://$OPSMAN_DOMAIN_OR_IP_ADDRESS \
            -u $OPSMAN_USERNAME \
            -p $OPSMAN_PASSWORD \
            -k --request-timeout 3600 \
            upload-stemcell -s $SC_FILE_PATH

 fi
fi



om-linux -t https://$OPSMAN_DOMAIN_OR_IP_ADDRESS \
         -u $OPSMAN_USERNAME \
         -p $OPSMAN_PASSWORD \
         -k --request-timeout 3600 \
         upload-product -p $TILE_FILE_PATH
