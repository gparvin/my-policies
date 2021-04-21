#!/bin/bash

set -e
set -o pipefail


CMDNAME=`basename $0`

# Display help information
help () {
  echo "Deploy image access secret to hub and target clusters by RHACM Subscription"
  echo ""
  echo "Prerequisites:"
  echo " - kubectl CLI must be pointing to the cluster to which to deploy verification key"
  echo " - roxctl and yq commands must be installed"
  echo ""
  echo "Usage:"
  echo "  $CMDNAME [-l <key=value>] [-p <path/to/file>] [-n <namespace>] [-s <name>]"
  echo ""
  echo "  -h|--help                   Display this menu"
  echo "  -a|--acs <hostname>         The ACS Central Server hostname to connect to."
  echo "  -i|--init <bundle-file>     The central init-bundles file name to save certs to."
  echo "                                (Default name is cluster-init-bundle.yaml"
  echo "  -u|--user <username>        The username used to access ACS images"
  echo ""
}

# The namespace is required to be stackrox
NAMESPACE=stackrox

# Parse arguments
while [[ $# -gt 0 ]]; do
        key="$1"
        case $key in
            -h|--help)
            help
            exit 0
            ;;
            -u|--username)
            shift
            USERNAME=${1}
            shift
            ;;
            -a|--acs)
            shift
            ACS_HOST=${1}
            shift
            ;;
            -i|--init)
            shift
            BUNDLE_FILE=${1}
            shift
            ;;
            *)    # default
            echo "Invalid input: ${1}"
            exit 1
            shift
            ;;
        esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters

if [[ -z $USERNAME ]]; then
	echo "The '-u|--user <username>' parameter is required."
	exit 1
fi

if [[ -z $ACS_HOST ]]; then
	echo "The '-a|--acs <hostname>' parameter is required."
	exit 1
fi

if [[ -z $BUNDLE_FILE ]]; then
	echo "The '-i|--init <init-bundle>' parameter is required."
	exit 1
fi

if [[ -z $NAMESPACE ]]; then
  NAMESPACE=stackrox
fi


if ! [ -x "$(command -v kubectl)" ]; then
    echo 'Error: kubectl is not installed.' >&2
    exit 1
fi

if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    BASE='base64 -w 0'
elif [[ "$OSTYPE" == "darwin"* ]]; then
    BASE='base64'
fi

echo -n Password: 
read -s PASSWORD

AUTH=`echo -n "$USERNAME:$PASSWORD" | ${BASE}`

if [ -f "${BUNDLE_FILE}" ]; then
	echo "Using existing bundle file."
else
	echo "Creating new bundle file."
	roxctl -e "$ACS_HOST" central init-bundles generate cluster-init-bundle --output ${BUNDLE_FILE}
	if [ $? -ne 0 ]; then
		echo "Failed to create the init-bundles required with 'roxctl'."
		exit 1
	fi
fi

cat <<EOF > acs-secrets-deployer.yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: stackrox
---
apiVersion: v1
kind: Namespace
metadata:
  name: stackrox-staging
---
apiVersion: v1
kind: Namespace
metadata:
  name: stackrox-cluster-channel
---
apiVersion: v1
data:
  .dockerconfigjson: `echo "{\"auths\":{\"https://stackrox.io\":{\"auth\":\"${AUTH}\"}}}" | ${BASE}`
kind: Secret
metadata:
  annotations:
    apps.open-cluster-management.io/deployables: "true"
  name: stackrox
  namespace: ${NAMESPACE}-staging
type: kubernetes.io/dockerconfigjson
---
apiVersion: v1
data:
  .dockerconfigjson: `echo "{\"auths\":{\"https://collector.stackrox.io\":{\"auth\":\"${AUTH}\"}}}" | ${BASE}`
kind: Secret
metadata:
  annotations:
    apps.open-cluster-management.io/deployables: "true"
  name: collector-stackrox
  namespace: ${NAMESPACE}-staging
type: kubernetes.io/dockerconfigjson
---
apiVersion: v1
data:
  admission-control-cert.pem: `yq eval '.admissionControl.serviceTLS.cert' ${BUNDLE_FILE} | ${BASE}`
  admission-control-key.pem: `yq eval '.admissionControl.serviceTLS.key' ${BUNDLE_FILE} | ${BASE}`
  ca.pem: `yq eval '.ca.cert' ${BUNDLE_FILE} | ${BASE}`
kind: Secret
metadata:
  annotations:
    apps.open-cluster-management.io/deployables: "true"
  name: admission-control-tls
  namespace: ${NAMESPACE}-staging
type: Opaque
---
apiVersion: v1
data:
  collector-cert.pem: `yq eval '.collector.serviceTLS.cert' ${BUNDLE_FILE} | ${BASE}`
  collector-key.pem: `yq eval '.collector.serviceTLS.key' ${BUNDLE_FILE} | ${BASE}`
  ca.pem: `yq eval '.ca.cert' ${BUNDLE_FILE} | ${BASE}`
kind: Secret
metadata:
  annotations:
    apps.open-cluster-management.io/deployables: "true"
  name: collector-tls
  namespace: ${NAMESPACE}-staging
type: Opaque
---
apiVersion: v1
data:
  sensor-cert.pem: `yq eval '.sensor.serviceTLS.cert' ${BUNDLE_FILE} | ${BASE}`
  sensor-key.pem: `yq eval '.sensor.serviceTLS.key' ${BUNDLE_FILE} | ${BASE}`
  ca.pem: `yq eval '.ca.cert' ${BUNDLE_FILE} | ${BASE}`
kind: Secret
metadata:
  annotations:
    apps.open-cluster-management.io/deployables: "true"
  name: sensor-tls
  namespace: ${NAMESPACE}-staging
type: Opaque
---
apiVersion: apps.open-cluster-management.io/v1
kind: Channel
metadata:
  name: secured-cluster-resources
  namespace: ${NAMESPACE}-staging
spec:
  pathname: ${NAMESPACE}-staging
  type: Namespace
---
apiVersion: app.k8s.io/v1beta1
kind: Application
metadata:
  name: secured-cluster-services
  namespace: ${NAMESPACE}
spec:
  selector:
    matchLabels:
      acm-app: acs-secured-cluster-services
---
apiVersion: apps.open-cluster-management.io/v1
kind: Channel
metadata:
  name: acs-secured-cluster-services-ch
  namespace: ${NAMESPACE}-cluster-channel
  labels:
    acm-app: acs-secured-cluster-services
spec:
  type: HelmRepo
  pathname: https://charts.stackrox.io
---
apiVersion: apps.open-cluster-management.io/v1
kind: Subscription
metadata:
  name: secured-cluster-sub
  namespace: ${NAMESPACE}
spec:
  channel: ${NAMESPACE}-staging/secured-cluster-resources
  placement:
    placementRef:
      kind: PlacementRule
      name: secured-cluster-placement
EOF

cat <<EOF >> acs-secrets-deployer.yaml
---
apiVersion: apps.open-cluster-management.io/v1
kind: Subscription
metadata:
  namespace: stackrox
  name: stackrox-secured-cluster-services
  labels:
    acm-app: acs-secured-cluster-services
spec:
  name: stackrox-secured-cluster-services
  channel: stackrox-cluster-channel/acs-secured-cluster-services-ch
  packageFilter:
    version: 58.0.0
  overrides:
EOF

CACERT=`yq eval '.ca.cert' ${BUNDLE_FILE} | sed 's/^/                    /'`
CLUSTERS=`oc get managedcluster.cluster.open-cluster-management.io --no-headers=true -o 'custom-columns=Name:.metadata.name,Available:.status.conditions[?(@.type=="ManagedClusterConditionAvailable")].status' | grep 'True$' | awk '{print $1}'`
for mc in $CLUSTERS; do
	echo "  - clusterName: $mc" >> acs-secrets-deployer.yaml
	echo "    clusterOverrides:" >> acs-secrets-deployer.yaml
	echo "    - path: spec.packageOverrides" >> acs-secrets-deployer.yaml
	echo "      value:" >> acs-secrets-deployer.yaml
	echo "      - packageName: stackrox-secured-cluster-services" >> acs-secrets-deployer.yaml
        echo "        packageAlias: secure-cluster-services" >> acs-secrets-deployer.yaml
	echo "        packageOverrides:" >> acs-secrets-deployer.yaml
	echo "        - path: spec" >> acs-secrets-deployer.yaml
	echo "          value:" >> acs-secrets-deployer.yaml
	echo "            clusterName: $mc" >> acs-secrets-deployer.yaml
	echo "            allowNonstandardReleaseName: true" >> acs-secrets-deployer.yaml
	echo "            centralEndpoint: $ACS_HOST" >> acs-secrets-deployer.yaml
	echo "            createSecrets: false" >> acs-secrets-deployer.yaml
	echo "            ca:" >> acs-secrets-deployer.yaml
	echo "                cert:" >> acs-secrets-deployer.yaml
	echo "$CACERT" >> acs-secrets-deployer.yaml
done

cat <<EOF >> acs-secrets-deployer.yaml
  placement:
    placementRef:
      name: secured-cluster-placement
      kind: PlacementRule
---
apiVersion: apps.open-cluster-management.io/v1
kind: PlacementRule
metadata:
  name: secured-cluster-placement
  namespace: ${NAMESPACE}
spec:
  clusterConditions:
  - status: "True"
    type: ManagedClusterConditionAvailable
  clusterSelector:
    matchExpressions:
    - key: name
      operator: In
      values:
EOF

for mc in $CLUSTERS; do
	echo "      - ${mc}" >> acs-secrets-deployer.yaml
done
