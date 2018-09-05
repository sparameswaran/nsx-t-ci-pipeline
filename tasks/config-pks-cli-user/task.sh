#!/bin/bash
# Source: https://github.com/pivotalservices/concourse-pipeline-samples/blob/master/tasks/pcf/pks/configure-pks-cli-user/task.sh
set -eu

export ROOT_DIR=`pwd`
source $ROOT_DIR/nsx-t-ci-pipeline/functions/copy_binaries.sh
source $ROOT_DIR/nsx-t-ci-pipeline/functions/check_versions.sh
source $ROOT_DIR/nsx-t-ci-pipeline/functions/generate_cert.sh
source $ROOT_DIR/nsx-t-ci-pipeline/functions/yaml2json.sh
source $ROOT_DIR/nsx-t-ci-pipeline/functions/check_null_variables.sh

echo "Note - pre-requisite for this task to work:"
echo "- Your PKS API endpoint [${PKS_UAA_DOMAIN_PREFIX}.${PKS_SYSTEM_DOMAIN}] should be routable and accessible from the Concourse worker(s) network."
echo "- See PKS tile documentation for configuration details for vSphere [https://docs.pivotal.io/runtimes/pks/1-0/installing-pks-vsphere.html#loadbalancer-pks-api] and GCP [https://docs.pivotal.io/runtimes/pks/1-0/installing-pks-gcp.html#loadbalancer-pks-api]"

echo "Retrieving PKS tile properties from Ops Manager [https://$OPSMAN_DOMAIN_OR_IP_ADDRESS]..."

# get PKS UAA admin credentials from OpsMgr
PRODUCTS=$(om-linux \
            -t https://$OPSMAN_DOMAIN_OR_IP_ADDRESS \
            -u $OPSMAN_USERNAME \
            -p $OPSMAN_PASSWORD \
            --connect-timeout 3200 \
            --request-timeout 3200 \
            --skip-ssl-validation \
            curl -p /api/v0/staged/products \
            2>/dev/null)

PKS_GUID=$(echo "$PRODUCTS" | jq -r '.[] | .guid' | grep pivotal-container-service)

UAA_ADMIN_SECRET=$(om-linux \
                    -t https://$OPSMAN_DOMAIN_OR_IP_ADDRESS \
                    -u $OPSMAN_USERNAME \
                    -p $OPSMAN_PASSWORD \
                    --skip-ssl-validation \
                    --connect-timeout 3200 \
                    --request-timeout 3200 \
                    curl -p /api/v0/deployed/products/$PKS_GUID/credentials/.properties.uaa_admin_secret \
                    2>/dev/null \
                    | jq -rc '.credential.value.secret')

# For PKS v1.1 it changed to .properties.pks_uaa_management_admin_client
if [ "$UAA_ADMIN_SECRET" == "" -o "$UAA_ADMIN_SECRET" == "null" ]; then
  UAA_ADMIN_SECRET=$(om-linux \
                      -t https://$OPSMAN_DOMAIN_OR_IP_ADDRESS \
                      -u $OPSMAN_USERNAME \
                      -p $OPSMAN_PASSWORD \
                      --skip-ssl-validation \
                      --connect-timeout 3200 \
                      --request-timeout 3200 \
                      curl -p /api/v0/deployed/products/$PKS_GUID/credentials/.properties.pks_uaa_management_admin_client \
                      2>/dev/null \
                      | jq -rc '.credential.value.secret')
fi

if [ "$UAA_ADMIN_SECRET" == "" -o "$UAA_ADMIN_SECRET" == "null" ]; then
  echo "Unable to retreive PKS Api UAA Client credentials from either .properties.uaa_admin_secret and .properties.pks_uaa_management_admin_client!!"
  exit -1
fi

echo "Connecting to PKS UAA server [${PKS_UAA_DOMAIN_PREFIX}.${PKS_SYSTEM_DOMAIN}]..."

set +e
check_dns_lookup=$(nslookup ${PKS_UAA_DOMAIN_PREFIX}.${PKS_SYSTEM_DOMAIN})
if [ "$?" != "0" ]; then
  echo "Warning!! Unable to resolve ${PKS_UAA_DOMAIN_PREFIX}.${PKS_SYSTEM_DOMAIN}"
  echo "Error!! Cannot proceed with client creation without being able to resolve ${PKS_UAA_DOMAIN_PREFIX}.${PKS_SYSTEM_DOMAIN} to external IP: $PKS_UAA_SYSTEM_DOMAIN_IP"
  echo ""
  exit -1
fi
set -e

# login to PKS UAA
uaac target https://${PKS_UAA_DOMAIN_PREFIX}.${PKS_SYSTEM_DOMAIN}:8443 --skip-ssl-validation
uaac_output=$(uaac token client get admin --secret $UAA_ADMIN_SECRET)
uaac_status=$(echo $?)
if [ "$uaac_status" != "0" ]; then
  echo "Problem in getting uaa token : $uaac_output"
fi

echo "Checking for existing user ${PKS_CLI_USERNAME}"
user_exist=$(uaac users | grep username | grep -e " ${PKS_CLI_USERNAME}$" || true )
if [ "$user_exist" == "" ]; then
  echo "Creating PKS CLI administrator user per PK tile documentation https://docs.pivotal.io/runtimes/pks/1-0/manage-users.html#uaa-scopes"

  # create pks admin user
  uaac user add "$PKS_CLI_USERNAME" --emails "$PKS_CLI_USEREMAIL" -p "$PKS_CLI_PASSWORD"
  echo "PKS CLI administrator user [$PKS_CLI_USERNAME] successfully created."
else
  echo "PKS CLI administrator user [$PKS_CLI_USERNAME] already exists!!."
fi

pks_admin_scope=$(uaac user get "$PKS_CLI_USERNAME" | grep "pks.clusters.admin" ||true )
if [ "$pks_admin_scope" == "" ]; then
  uaac member add pks.clusters.admin "$PKS_CLI_USERNAME"
  uaac member add pks.clusters.manage "$PKS_CLI_USERNAME" || true
  echo "PKS CLI administrator user [$PKS_CLI_USERNAME] given scope: pks.clusters.admin, pks.clusters.manage"
fi

echo ""
echo "Next, download the PKS CLI from Pivotal Network and login to the PKS API to create a new K8s cluster [https://docs.pivotal.io/runtimes/pks/1-0/create-cluster.html]"
echo "Example: "
echo "   pks login -a https://${PKS_UAA_DOMAIN_PREFIX}.${PKS_SYSTEM_DOMAIN}:<pks-controller-port> -k -u $PKS_CLI_USERNAME -p <pks-cli-password-provided>"
echo "Note: PKS Controller Port can be 8443 or 9021 based on version of PKS Tile"
