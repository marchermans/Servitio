#!/bin/bash

# This script takes in the following parameters:
# - Service type. Supported are the values for which a "-charts" directory exists in this repo
# - Service name. Supported are the values for which a "-extras" directory exists within the service type directory
# - Secret name
# Example: ./update-webdav-secret.sh core prometheus github-client
# The secret value is then read from STDIN and the secret file is output to the target directory for the service.

# Set up variables
SERVICE_TYPE=$1
SERVICE_NAME=$2
SECRET_NAME=$3

# Check if service type and name are provided
if [ -z "${SERVICE_TYPE}" ]; then
    echo "Service type is not provided."
    exit 1
fi

if [ -z "${SERVICE_NAME}" ]; then
    echo "Service name is not provided."
    exit 2
fi

if [ -z "${SECRET_NAME}" ]; then
    echo "Secret name is not provided."
    exit 3
fi

# Find the parent directory of this script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
# Go up to the root project directory
PROJECT_DIR=$(realpath "${SCRIPT_DIR}/../")

# Set up paths
SERVICE_TYPE_DIR="${PROJECT_DIR}/${SERVICE_TYPE}-charts"
APPLICATION_SERVICES_DIR="${PROJECT_DIR}/${SERVICE_TYPE}-services"
SERVICE_NAME_DIR="${SERVICE_TYPE_DIR}/${SERVICE_NAME}-extras"
TEMPLATE_DIR="${SERVICE_NAME_DIR}/templates"
SECRET_FILE="${TEMPLATE_DIR}/${SECRET_NAME}.yaml"

# Check if the application services directory exists
if [ ! -d "${APPLICATION_SERVICES_DIR}" ]; then
    # If it does not exist try the singular form
    APPLICATION_SERVICES_DIR="${PROJECT_DIR}/${SERVICE_TYPE}-service"
    if [ ! -d "${APPLICATION_SERVICES_DIR}" ]; then
        echo "Application services directory ${APPLICATION_SERVICES_DIR} does not exist."
        exit 1
    fi
fi

# We need to extract the used namespace.
# This is done by looking in the "-services" service type directory, for the application template, and looking in the yaml property: spec.destination.namespace
# This is then used to set the namespace in the secret template.
# The namespace is then used to create the secret in the correct namespace.
APPLICATION_FILE="${APPLICATION_SERVICES_DIR}/templates/${SERVICE_NAME}.yaml"

SERVICE_NAMESPACE=$(yq eval '.spec.destination.namespace' "${APPLICATION_FILE}")

# Check if the service namespace is set
if [ -z "${SERVICE_NAMESPACE}" ]; then
    echo "Service namespace is not set in ${APPLICATION_FILE}."
    exit 2
fi

# Ensure the template directory exists
mkdir -p "${TEMPLATE_DIR}"


# Function to decode base64
decode_base64() {
  echo "$1" | base64 --decode
}

# Function to encode base64
encode_base64() {
  echo -n "$1" | base64
}

# Check if the secret exists
if kubectl get secret "$SECRET_NAME" -n "$SERVICE_NAMESPACE" &> /dev/null; then
  # Pull the existing secret
  existing_secret=$(kubectl get secret "$SECRET_NAME" -n "$SERVICE_NAMESPACE" -o jsonpath="{.data.auth}")
  # Decode the existing secret
  decoded_secret=$(decode_base64 "$existing_secret")
else
  # Initialize an empty decoded secret
  decoded_secret=""
fi

# Ask the user for the new username and password
read -p "Enter the new username: " new_username
read -sp "Enter the new password: " new_password
echo

# Add the new username and password to the auth file
new_entry=$(printf "%s:%s" "$new_username" "$(openssl passwd -apr1 "$new_password")")
updated_secret="$decoded_secret"$'\n'"$new_entry"

# Encode the updated secret
encoded_updated_secret=$(encode_base64 "$updated_secret")

# Create a new secret yaml file
cat <<EOF > new-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: $SECRET_NAME
  namespace: $SERVICE_NAMESPACE
data:
  auth: $encoded_updated_secret
EOF

# Create a client-sided dry run kubernetes secret
kubectl create secret generic "$SECRET_NAME" -n "$SERVICE_NAMESPACE" --from-file=auth=<(echo "$updated_secret") --dry-run=client -o yaml > dry-run-secret.yaml

# Pipe the result into kubeseal to create a sealed secret
kubeseal --format yaml < dry-run-secret.yaml > "$SECRET_FILE"

# Append the application marker labels:
echo "      labels:" >> "$SECRET_FILE"
echo "        app.kubernetes.io/part-of: ${SERVICE_NAME}" >> "$SECRET_FILE"

# On the outputted file we need to remove lines containing the following: creationTimestamp, resourceVersion, selfLink, uid
# This is because these values will change on each run, and we want to be able to compare the outputted file with the sealed secret file.
sed -i '/creationTimestamp/d' "$SECRET_FILE"
sed -i '/resourceVersion/d' "$SECRET_FILE"
sed -i '/selfLink/d' "$SECRET_FILE"
sed -i '/uid/d' "$SECRET_FILE"

rm new-secret.yaml dry-run-secret.yaml

echo "Sealed secret created and saved to $SECRET_FILE"
