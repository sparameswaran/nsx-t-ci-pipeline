#!/bin/bash

function upload_stemcells() (

  set -eu
  local stemcell_versions="$1"

  for stemcell_version_reqd in $stemcell_versions
  do

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
        pivnet-cli download-product-files -p "$product_slug" -r $stemcell_version_reqd -g "*${IAAS}*" --accept-eula
        if [ $? != 0 ]; then
          min_version=$(echo $stemcell_version_reqd | awk -F '.' '{print $2}')
          major_version=$(echo $stemcell_version_reqd | awk -F '.' '{print $1}')
          if [ "$min_version" == "" ]; then
            for min_version in $(seq 100 -1 0)
            do
               pivnet-cli download-product-files -p "$product_slug" -r $major_version.$min_version -g "*${IAAS}*" --accept-eula && break
            done
          else
            echo "No Stemcell version $major_version for "${IAAS}" found !!, giving up"
            exit 1
          fi
        fi
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
    fi

  done

)
