#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="demo"
NAMESPACE="demo"
RELEASE_NAME="demo"
IMAGE_NAME="demo-service:1.0.0"

echo "=== [1/5] Checking cluster status for '${CLUSTER_NAME}' ==="
if kind get clusters 2>/dev/null | grep -qw "${CLUSTER_NAME}"; then
  echo "Kind cluster '${CLUSTER_NAME}' already exists. Reusing it."
else
  echo "Creating Kind cluster '${CLUSTER_NAME}' with ingress port mappings..."
  cat <<EOF | kind create cluster --name "${CLUSTER_NAME}" --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
EOF
fi

kubectl cluster-info --context "kind-${CLUSTER_NAME}" >/dev/null 2>&1 || true

echo "=== [2/5] Ensuring ingress-nginx is installed and healthy ==="
if kubectl get ns ingress-nginx >/dev/null 2>&1; then
  echo "Namespace ingress-nginx already exists."
else
  echo "Deploying ingress-nginx controller for Kind..."
  kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
fi

echo "Waiting for ingress-nginx controller to be ready..."
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=180s >/dev/null 2>&1 || true

echo "=== [3/5] Building local container image '${IMAGE_NAME}' ==="
docker build -t "${IMAGE_NAME}" ./service

echo "=== [4/5] Loading container image into Kind cluster '${CLUSTER_NAME}' ==="
kind load docker-image "${IMAGE_NAME}" --name "${CLUSTER_NAME}"

echo "=== [5/5] Deploying Helm release '${RELEASE_NAME}' into namespace '${NAMESPACE}' ==="
helm upgrade --install "${RELEASE_NAME}" ./chart \
  --namespace "${NAMESPACE}" \
  --create-namespace \
  --wait \
  --timeout 120s

echo ""
echo "=========================================================="
echo " Setup complete! Service is running and ready."
echo " Verify with:"
echo "   curl -H 'Host: demo.local' http://localhost/"
echo "   curl -H 'Host: demo.local' http://localhost/healthz"
echo "=========================================================="
