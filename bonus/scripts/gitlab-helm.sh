#!/usr/bin/env bash
#
# bonus/scripts/gitlab-helm.sh
# ALTERNATIVE to confs/gitlab.yaml: installs GitLab with the official Helm chart.
# Heavier (~25 pods, 6-8 GB RAM) but closer to a production setup.
#
# If you use this, DO NOT also apply confs/gitlab.yaml, and update the repoURL
# in confs/application.yaml to:
#   http://gitlab-webservice-default.gitlab.svc.cluster.local:8181/root/<project>.git
#
set -euo pipefail

CONF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../confs" && pwd)"

log() { printf '\033[1;34m[helm]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[fail]\033[0m %s\n' "$*" >&2; exit 1; }

command -v helm >/dev/null 2>&1 || die "helm not found — run ./scripts/install.sh"

kubectl create namespace gitlab --dry-run=client -o yaml | kubectl apply -f - >/dev/null

helm repo add gitlab https://charts.gitlab.io/ >/dev/null
helm repo update >/dev/null

log "installing the GitLab chart (expect 10-20 minutes)"
helm upgrade --install gitlab gitlab/gitlab \
	--namespace gitlab \
	-f "${CONF_DIR}/helm-values.yaml" \
	--timeout 1800s \
	--wait

log "root password:"
kubectl get secret gitlab-gitlab-initial-root-password -n gitlab \
	-o jsonpath='{.data.password}' | base64 -d; echo

log "UI: kubectl port-forward -n gitlab svc/gitlab-webservice-default 8081:8181"
