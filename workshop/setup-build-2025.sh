#!/bin/bash -e

########################################
# Functions
########################################

# Function to get the users public IP
getUserPublicIP(){
export USER_PUBLIC_IP=$(curl -s icanhazip.com)

printf "\n###############################################################################"
printf "\nThis workshop needs to know your public IP address to secure the AKS cluster."
printf "\nIf you are using a cloud shell or code spaces that will have a different public IP than your local public IP."
printf "\nYou can check your local public IP by visiting https://icanhazip.com/ from your local machine."
printf "\n###############################################################################\n\n"


while true; do
  read -p "Is your local public IP ${USER_PUBLIC_IP}? (y/n)" -n 1 -r yn
  case $yn in
    [Yy] ) 
        break;;
    [nN] ) read -p $'\nPlease enter your public IP: ' USER_PUBLIC_IP;;
    *) printf "\nInvalid Response...exiting"; exit 1 ;;
  esac
done

printf "\nProceeding with user public IP: $USER_PUBLIC_IP \n"
}

# Function to generate or load the values for environment variables
# and store them in a .env file
generateVars(){
  # Get the users public IP
  getUserPublicIP

  K8SUSER=$RANDOM
  K8SPASSWORD=$RANDOM
  echo "This is your user/password for the webshell. Please keep it safe."
  echo "K8SUSER: $K8SUSER"
  echo "K8SPASSWORD: $K8SPASSWORD"
  K8SUSER_BASE64=$(echo -n $K8SUSER | base64)
  K8SPASSWORD_BASE64=$(echo -n $K8SPASSWORD | base64)

  # Check if the user provided values for the environment variables
  # If not, use the defaults
  export RESOURCE_GROUP="${RESOURCE_GROUP:-ctf-rg}"
  export LOCATION="${LOCATION:-westus}"
  export AKS_NAME="${AKS_NAME:-ctf-aks}"
  export VNET_NAME="${VNET_NAME:-ctf-vnet}"
  export AKS_SUBNET_NAME="${AKS_NAME:-aks-subnet}"
  export ACR_NAME=acr${RANDOM}

  # Generate an SSH key for the AKS cluster
  # TODO: We'll remove this once the disableSSH feature is GA in AKS
  echo "Generating Cluster SSH key..."
  ssh-keygen -N '' -f ./aks-ssh -t rsa

  # Create a .env file with the generated values
  # This can be used to reload the values if the script is run again
  cat <<EOF >.env
  USER_PUBLIC_IP=$USER_PUBLIC_IP
  K8SUSER=$K8SUSER
  K8SPASSWORD=$K8SPASSWORD
  K8SUSER_BASE64=$K8SUSER_BASE64
  K8SPASSWORD_BASE64=$K8SPASSWORD_BASE64
  RESOURCE_GROUP=$RESOURCE_GROUP
  LOCATION=$LOCATION
  AKS_NAME=$AKS_NAME
  VNET_NAME=$VNET_NAME
  AKS_SUBNET_NAME=$AKS_SUBNET_NAME
  ACR_NAME=$ACR_NAME 
EOF
}

# Function to load the values from the .env file
loadExistingVars(){
  source ./.env
  echo "USER_PUBLIC_IP: $USER_PUBLIC_IP"
  echo "K8SUSER: $K8SUSER"
  echo "K8SPASSWORD: $K8SPASSWORD"
  echo "K8SUSER_BASE64: $K8SUSER_BASE64"
  echo "K8SPASSWORD_BASE64: $K8SPASSWORD_BASE64"
  echo "RESOURCE_GROUP: $RESOURCE_GROUP"
  echo "LOCATION: $LOCATION"
  echo "AKS_NAME: $AKS_NAME"
  echo "VNET_NAME: $VNET_NAME"
  echo "AKS_SUBNET_NAME: $AKS_SUBNET_NAME"
  echo "ACR_NAME: $ACR_NAME"
}

# Function to deploy the Kubernetes resources
deployKubernetesResources(){
kubectl create namespace dev --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace prod --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: app-secret
  namespace: dev
type: Opaque
data:
  username: $K8SUSER_BASE64
  password: $K8SPASSWORD_BASE64
---
apiVersion: v1
kind: Secret
metadata:
  name: app-secret
  namespace: prod
type: Opaque
data:
  username: $K8SUSER_BASE64
  password: $K8SPASSWORD_BASE64
EOF

# Create the registry credentials
kubectl create secret docker-registry acr-secret \
  --namespace dev \
  --docker-server $ACR_NAME.azurecr.io \
  --docker-username $ACR_USERNAME \
  --docker-password $ACR_PASSWORD \
  --dry-run=client -o yaml | kubectl apply -f -

# build the app image
az acr build -r $ACR_NAME --image insecure-app ./insecure-app/

cat <<EOF >>./manifests/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- omnibus.yml
images:
- name: aks-ctf/insecure-app
  newName: ${ACR_NAME}.azurecr.io/insecure-app
EOF

kubectl apply -k ./manifests
}

getClusterAndACRCreds(){
# Get the ACR Credentials
ACR_USERNAME=$(az acr credential show -n $ACR_NAME --query username -o tsv)
ACR_PASSWORD=$(az acr credential show -n $ACR_NAME --query 'passwords[0].value' -o tsv)

# Fetch a valid kubeconfig
az aks get-credentials --resource-group $RESOURCE_GROUP --name $AKS_NAME --admin --overwrite-existing 
# Grab a copy for scenario 1
az aks get-credentials --resource-group $RESOURCE_GROUP --name $AKS_NAME --admin --overwrite-existing --file ./scenario_1/kubeconfig

}
########################################
# End of Functions
########################################

########################################
# Main Script
########################################

# Generate or load existing values for the environment variables
if ! [ -f ./.env ]; then
echo "Loading and generating values for the environment variables..."
generateVars
else
# Load the values from the existing .env file
echo "File .env exists. Loading values from .env file..."
loadExistingVars
fi

# Get the cluster and ACR credentials
echo "Getting the cluster and ACR credentials..."
getClusterAndACRCreds

# Deploy the Kubernetes resources
echo "Deploying Kubernetes resources..."
deployKubernetesResources


########################################
# End Main Script
########################################
