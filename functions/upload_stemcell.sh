#!/bin/bash

function upload_stemcells() (

  set -eu
  local stemcell_os=$1
  local stemcell_versions="$2"
  staged=""
  failed=0

  # Loop through all passed in versions
  for stemcell_version_reqd in $stemcell_versions
  do
    echo "Minimum stemcell version: $stemcell_version_reqd"
    minor_version=$(echo $stemcell_version_reqd | awk -F '.' '{print $2}')
    major_version=$(echo $stemcell_version_reqd | awk -F '.' '{print $1}')

    if [ -n "$stemcell_version_reqd" ]; then
      # Run diag to see which versions are already staged
      diagnostic_report=$(
        om-linux \
          --target https://$OPSMAN_DOMAIN_OR_IP_ADDRESS \
          --username $OPSMAN_USERNAME \
          --password $OPSMAN_PASSWORD \
          --skip-ssl-validation \
          curl --silent --path "/api/v0/diagnostic_report"
      )

      echo "Diag report:"
      echo " $diagnostic_report"

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

        # Find and download latest stemcell
        if [[ "$minor_version" != "" && "$major_version" != "" ]]; then
          echo "Looking for newer stemcells versions"
          for newer_version in $(seq 100 -1 $minor_version)
            do
              stagged=""
              # Search to see if newer stemcell already staged
              already_staged=$(
                echo $diagnostic_report |
                jq \
                --arg version "$major_version.$newer_version" \
                --arg glob "$IAAS" \
                '.available_stemcells[] | .filename | select(contains($version) and contains($glob))'
              )
              if [[ -n $already_staged ]]; then
                echo "$major_version.$newer_version already downloaded ... "
                staged="$major_version.$newer_version"
                break
              else 
                echo "Trying to download $major_version.$newer_version"
                pivnet-cli download-product-files -p "$product_slug" -r $major_version.$newer_version -g "*${IAAS}*" --accept-eula
                # If no errors, go ahead and upload it to opsman
                if [[ $? == 0 ]]; then
                  echo "Successfully downloaded stemcell: $major_version.$newer_version"
                  staged="$major_version.$newer_version"
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
                  break
                else 
                  echo "$major_version.$newer_version not found"
               fi
              fi
            done
        fi

        # Check if failed
        if [[ $staged == "" ]]; then
          echo "Unable to download stemcell ... mimimum: $stemcell_version_reqd"
          failed=$((failed+1))      
        fi
        
    fi
  done
  if [[ $failed > 0 ]]; then
    exit 1
  fi
)
