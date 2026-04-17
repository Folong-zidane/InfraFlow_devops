#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────
# InfraFlow – Deployment Script
# ─────────────────────────────────────────────

NAMESPACE="infraflow"
K8S_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/k8s"
MONITORING_NAMESPACE="monitoring"
HELM_RELEASE="monitoring"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ─────────────────────────────────────────────
check_prerequisites() {
    log_info "Checking prerequisites..."
    local missing=0

    for cmd in kubectl helm docker; do
        if ! command -v "$cmd" &>/dev/null; then
            log_error "Required tool not found in PATH: $cmd"
            missing=1
        else
            log_info "  ✓ $cmd found: $(command -v "$cmd")"
        fi
    done

    if [[ "$missing" -eq 1 ]]; then
        log_error "Please install missing tools before running this script."
        exit 1
    fi

    if ! kubectl cluster-info &>/dev/null; then
        log_error "Cannot connect to Kubernetes cluster. Is minikube/kind running?"
        exit 1
    fi

    log_info "All prerequisites satisfied."
}

# ─────────────────────────────────────────────
create_namespace() {
    log_info "Ensuring namespace '$NAMESPACE' exists..."
    if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
        kubectl create namespace "$NAMESPACE"
        log_info "Namespace '$NAMESPACE' created."
    else
        log_info "Namespace '$NAMESPACE' already exists."
    fi
}

# ─────────────────────────────────────────────
deploy_services() {
    log_info "Applying Kubernetes manifests from $K8S_DIR ..."

    kubectl apply -f "$K8S_DIR/namespace.yml"
    kubectl apply -f "$K8S_DIR/web-service/configmap.yml"
    kubectl apply -f "$K8S_DIR/api-service/deployment.yml"
    kubectl apply -f "$K8S_DIR/api-service/service.yml"
    kubectl apply -f "$K8S_DIR/api-service/hpa.yml"
    kubectl apply -f "$K8S_DIR/web-service/deployment.yml"
    kubectl apply -f "$K8S_DIR/web-service/service.yml"

    if [[ -f "$K8S_DIR/prometheus-rules.yml" ]]; then
        kubectl apply -f "$K8S_DIR/prometheus-rules.yml" || \
            log_warn "PrometheusRule CRD not available yet – skipping alerts."
    fi

    log_info "Manifests applied successfully."
}

# ─────────────────────────────────────────────
wait_for_pods() {
    log_info "Waiting for deployments to be ready..."

    kubectl rollout status deployment/api-service -n "$NAMESPACE" --timeout=120s
    kubectl rollout status deployment/web-service -n "$NAMESPACE" --timeout=120s

    log_info "All deployments are ready."
}

# ─────────────────────────────────────────────
deploy_monitoring() {
    log_info "Deploying Prometheus + Grafana via Helm..."

    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
    helm repo update

    if helm status "$HELM_RELEASE" -n "$MONITORING_NAMESPACE" &>/dev/null; then
        log_info "Helm release '$HELM_RELEASE' already installed – upgrading..."
        helm upgrade "$HELM_RELEASE" prometheus-community/kube-prometheus-stack \
            --namespace "$MONITORING_NAMESPACE" \
            --create-namespace \
            --wait \
            --timeout 5m
    else
        helm install "$HELM_RELEASE" prometheus-community/kube-prometheus-stack \
            --namespace "$MONITORING_NAMESPACE" \
            --create-namespace \
            --wait \
            --timeout 5m
    fi

    log_info "Monitoring stack deployed."
}

# ─────────────────────────────────────────────
print_access_urls() {
    log_info "─────────────────────────────────────────────"
    log_info "Deployment complete! Access URLs:"
    echo ""

    local node_ip
    node_ip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "localhost")

    echo -e "  ${GREEN}Web Service (Nginx proxy):${NC}"
    echo -e "    NodePort  → http://${node_ip}:30080"
    echo -e "    Port-fwd  → kubectl port-forward svc/web-service 8080:80 -n ${NAMESPACE}"
    echo ""
    echo -e "  ${GREEN}Grafana:${NC}"
    echo -e "    Port-fwd  → kubectl port-forward svc/${HELM_RELEASE}-grafana 3000:80 -n ${MONITORING_NAMESPACE}"
    echo -e "    Default credentials: admin / prom-operator"
    echo ""
    echo -e "  ${GREEN}Prometheus:${NC}"
    echo -e "    Port-fwd  → kubectl port-forward svc/${HELM_RELEASE}-kube-prometheus-prometheus 9090:9090 -n ${MONITORING_NAMESPACE}"
    echo ""

    log_info "Pods status:"
    kubectl get pods -n "$NAMESPACE"
    echo ""
    log_info "Services:"
    kubectl get svc -n "$NAMESPACE"
}

# ─────────────────────────────────────────────
main() {
    log_info "═══════════════════════════════════════════"
    log_info "  InfraFlow – Automated Deployment Script  "
    log_info "═══════════════════════════════════════════"

    check_prerequisites
    create_namespace
    deploy_services
    wait_for_pods
    deploy_monitoring
    print_access_urls
}

main "$@"
