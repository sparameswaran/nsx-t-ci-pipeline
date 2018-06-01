#!/bin/bash

set -eu

export ROOT_DIR=`pwd`
source $ROOT_DIR/nsx-t-ci-pipeline/functions/copy_binaries.sh
source $ROOT_DIR/nsx-t-ci-pipeline/functions/check_versions.sh

check_available_product_version "cf"

enabled_errands=$(
  om-linux \
    --target "https://${OPSMAN_DOMAIN_OR_IP_ADDRESS}" \
    --skip-ssl-validation \
    --username $OPSMAN_USERNAME \
    --password $OPSMAN_PASSWORD \
    errands \
    --product-name "$PRODUCT_NAME" |
  tail -n+4 | head -n-1 | grep -v false | cut -d'|' -f2 | tr -d ' '
)

if [[ "$ERRANDS_TO_RUN_ON_CHANGE" == "all" ]]; then
  errands_to_run_on_change="${enabled_errands[@]}"
else
  errands_to_run_on_change=$(echo "$ERRANDS_TO_RUN_ON_CHANGE" | tr ',' '\n')
fi

will_run_on_change=$(
  echo $enabled_errands |
  jq \
    --arg run_on_change "${errands_to_run_on_change[@]}" \
    --raw-input \
    --raw-output \
    'split(" ")
    | reduce .[] as $errand ([];
       if $run_on_change | contains($errand) then
         . + [$errand]
       else
         .
       end)
    | join("\n")'
)

if [ -z "$will_run_on_change" ]; then
  echo Nothing to do.
  exit 0
fi

while read errand; do
  echo -n Set $errand to run on change...
  om-linux \
    --target "https://${OPSMAN_DOMAIN_OR_IP_ADDRESS}" \
    --skip-ssl-validation \
    --username "$OPSMAN_USERNAME" \
    --password "$OPSMAN_PASSWORD" \
    set-errand-state \
    --product-name "$PRODUCT_NAME" \
    --errand-name $errand \
    --post-deploy-state "when-changed"
  echo done
done < <(echo "$will_run_on_change")
