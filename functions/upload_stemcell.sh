#!/bin/bash

function upload_stemcells() (

  set -eu
  local stemcell_os=$1
  local stemcell_versions="$2"
  local downloaded="no"

  for stemcell_version_reqd in $stemcell_versions
  do
    echo "Minimum stemcell version: $stemcell_version_reqd"

    minor_version=$(echo $stemcell_version_reqd | awk -F '.' '{print $2}')
    major_version=$(echo $stemcell_version_reqd | awk -F '.' '{print $1}')

    if [ -n "$stemcell_version_reqd" ]; then
      #diagnostic_report=$(
      #  om-linux \
      #    --target https://$OPSMAN_DOMAIN_OR_IP_ADDRESS \
      #    --username $OPSMAN_USERNAME \
      #    --password $OPSMAN_PASSWORD \
      #    --skip-ssl-validation \
      #    curl --silent --path "/api/v0/diagnostic_report"
      #)
      
      #if [[ -n "$stemcell" ]]; then
      #  echo "Downloading stemcell $stemcell_version_reqd"

        product_slug=$(
          jq --raw-output \
            '
            if any(.Dependencies[]; select(.Release.Product.Name | contains("Stemcells for PCF (Windows)"))) then
              "stemcells-windows-server"
            else
              "stemcells"
            end
            ' < pivnet-product/metadata.json
        )

        pivnet-cli login --api-token="$PIVNET_API_TOKEN"
        set +e

        # Override the product_slug for xenial
        if [[ "$stemcell_os" =~ "trusty" ]]; then
          product_slug="stemcells"
        elif [[ "$stemcell_os" =~ "xenial" ]]; then
          product_slug="stemcells-ubuntu-xenial"
        fi

        # Find and download correct stemcell
        if [[ "$minor_version" != "" && "$major_version" != "" ]]; then
          echo "Looking for newer stemcells versions"
          for min_version in $(seq 100 -1 $minor_version)
            do
               echo "Trying to dowlowding $major_version.$min_version"
               pivnet-cli download-product-files -p "$product_slug" -r $major_version.$min_version -g "*${IAAS}*" --accept-eula
               if [[ $? == 0 ]]; then
                echo "Successfully downloaded stemcell: $stemcell_version_reqd"
                downloaded="yes"
                break
               else 
                echo "$stemcell_version_reqd not found"
               fi
            done
        fi

        if [[ $downloaded == "no" ]]; then
          echo "Unable to download stemcell: $stemcell_version_reqd"
          exit 1
        fi

        # Upload file to opsman
        set -e
        SC_FILE_PATH=`find ./ -name "bosh*.tgz" | sort | tail -1 || true`
        if [ ! -f "$SC_FILE_PATH" ]; then
          echo "Stemcell file not found!"
          exit 1
        fi

        for stemcell in $SC_FILE_PATH
        do
          om-linux -t https://$OPSMAN_DOMAIN_OR_IP_ADDRESS -u $OPSMAN_USERNAME -p $OPSMAN_PASSWORD -k upload-stemcell -s $stemcell
        done 
    fi
  done
)
