#!/bin/bash

set -eu

#Global variables
export ROOT_DIR=`pwd`

# Snip off long name - openssl would break
export PKS_GUID=$(echo $PRODUCT_GUID | sed -e 's/pivotal-container-service-//')
export PKS_SUPERUSER_NAME="pks-nsx-t-superuser-${PKS_GUID}"
export NSX_SUPERUSER_CERT_FILE="$ROOT_DIR/pks-nsx-t-superuser.crt"
export NSX_SUPERUSER_KEY_FILE="$ROOT_DIR/pks-nsx-t-superuser.key"
export NODE_ID=$(cat /proc/sys/kernel/random/uuid)
touch $NSX_SUPERUSER_CERT_FILE $NSX_SUPERUSER_KEY_FILE

# Check if pks super user already exists on the NSX Mgr and avoid duplication
function check_existing_pks_superuser {
  check_existing_pks_user=$(curl -k \
              -X GET \
              "https://${NSX_API_MANAGER}/api/v1/trust-management/principal-identities" \
              -u "$NSX_API_USER:$NSX_API_PASSWORD" \
              2>/dev/null \
              | jq -r --arg pks_superuser_name $PKS_SUPERUSER_NAME '.results[] | select (.display_name | contains($pks_superuser_name)) |.id ' )

  if [ "$check_existing_pks_user" == "" -o "$check_existing_pks_user" == null ]; then
    (>&2 echo "Creating PKS Superuser on NSX Manager : $PKS_SUPERUSER_NAME ")
    echo 0
  else
    (>&2 echo "PKS Superuser : $PKS_SUPERUSER_NAME already exists on NSX Manager!!")
    (>&2 echo "Not creating PKS Superuser")
    echo 1
  fi
}

function create_pks_superuser {

  status=$(check_existing_pks_superuser)
  if [ "$status" != "0" ]; then
    return
  fi

  cat /etc/ssl/openssl.cnf <(printf '[client_server_ssl]\nextendedKeyUsage = clientAuth\n') > /tmp/extended_openssl.cnf
  # Create Cert
  openssl req \
    -newkey rsa:2048 \
    -x509 \
    -nodes \
    -keyout "$NSX_SUPERUSER_KEY_FILE" \
    -new \
    -out "$NSX_SUPERUSER_CERT_FILE" \
    -subj /CN=$PKS_SUPERUSER_NAME \
    -extensions client_server_ssl \
    -sha256 \
    -days 730 \
    -config /tmp/extended_openssl.cnf \
    2>/dev/null

  # Register Cert
  cert_request=$(cat <<END
{
  "display_name": "$PKS_SUPERUSER_NAME",
  "pem_encoded": "$(awk '{printf "%s\\n", $0}' $NSX_SUPERUSER_CERT_FILE)"
}
END
  )

  cert_response=$(curl -k -X POST \
    "https://${NSX_API_MANAGER}/api/v1/trust-management/certificates?action=import" \
    -u "$NSX_API_USER:$NSX_API_PASSWORD" \
    -H 'content-type: application/json' \
    2>/dev/null \
    -d "$cert_request")

  CERTIFICATE_ID=$(echo $cert_response | jq -r .results[0].id)
  # Register PI
  pi_request=$(cat <<END
{
  "display_name": "$PKS_SUPERUSER_NAME",
  "name": "$PKS_SUPERUSER_NAME",
  "permission_group": "superusers",
  "certificate_id": "$CERTIFICATE_ID",
  "node_id": "$NODE_ID"
}
END
  )

  add_principal_ids_response=$(curl -k -X POST \
    "https://${NSX_API_MANAGER}/api/v1/trust-management/principal-identities" \
    -u "$NSX_API_USER:$NSX_API_PASSWORD" \
    2>/dev/null \
    -H 'content-type: application/json' \
    -d "$pi_request")

  echo "Response from adding principal identity: "
  echo "$add_principal_ids_response"
  echo ""

  echo "Sleeping few seconds before testing the newly created superuser"
  sleep 10
  check_created_super_user
}

function check_created_super_user {
  # Test if certificate and key can be used to communicate with NSX-T
  test_response=$(curl -k -X GET \
    "https://${NSX_API_MANAGER}/api/v1/trust-management/principal-identities" \
    --cert "$NSX_SUPERUSER_CERT_FILE" \
    --key "$NSX_SUPERUSER_KEY_FILE" \
    | jq -r .results[].display_name )

  echo "Found principal identities using cert!!"
  echo "$test_response "
  echo ""
}

create_pks_superuser
export NSX_SUPERUSER_CERT=$(cat $NSX_SUPERUSER_CERT_FILE | tr '\n' '#'| sed -e 's/#/\r\n/g')
export NSX_SUPERUSER_KEY=$(cat $NSX_SUPERUSER_KEY_FILE | tr '\n' '#'| sed -e 's/#/\r\n/g')
