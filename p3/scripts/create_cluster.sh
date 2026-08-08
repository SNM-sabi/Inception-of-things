#!/usr/bin/env bash
#
# p3/scripts/create_cluster.sh
#
# Creates the k3d cluster, both namespaces, installs Argo CD and registers the
# Application that syncs the app from the public GitOps repo into "dev".
#
# Usage:
#   bash p3/scripts/create_cluster.sh
#   REPO_URL=https://github.com/<login>/<repo>.git bash p3/scripts/create_cluster.sh
#
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-iot}"
ARGOCD_VERSION="v3.4.6"                       # pinned — CLAUDE.md "Pinned versions"
ARGOCD_MANIFEST="https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/$(basename "${BASH_SOURCE[0]}")"
CONF_DIR="$(cd "${SCRIPT_DIR}/../confs" && pwd)"

log()  { printf '\033[1;34m[cluster]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[  ok   ]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[ fail  ]\033[0m %s\n' "$*" >&2; exit 1; }

# --- preflight --------------------------------------------------------------
for bin in docker kubectl k3d; do
	command -v "$bin" >/dev/null 2>&1 || die "$bin not found — run: bash p3/scripts/install.sh"
done

# `usermod -aG docker` only affects NEW login sessions, so right after a fresh
# install.sh the current shell still cannot reach the daemon. Re-exec once under
# `sg docker` rather than telling the evaluator to log out mid-defense.
if ! docker info >/dev/null 2>&1; then
	if [ -z "${IOT_SG_RETRY:-}" ] && id -nG "$USER" | tr ' ' '\n' | grep -qx docker; then
		log "docker group not active in this shell — re-running under 'sg docker'"
		export IOT_SG_RETRY=1
		exec sg docker -c "$(printf '%q ' bash "$SCRIPT_PATH" "$@")"
	fi
	die "cannot talk to the docker daemon (is it running? is ${USER} in the docker group?)"
fi

# --- 1. cluster -------------------------------------------------------------
# The port map is the whole reason this is a separate script from install.sh:
# k3d port maps are FIXED AT CREATE TIME. Forgetting -p means deleting and
# recreating the cluster mid-defense. 8888 on the host -> 80 on the k3d
# load-balancer -> Traefik -> our Ingress. No kubectl port-forward involved,
# so the app survives the v1 -> v2 pod replacement.
if k3d cluster list -o json | grep -q "\"name\":\"${CLUSTER_NAME}\""; then
	ok "cluster '${CLUSTER_NAME}' already exists"
else
	log "creating k3d cluster '${CLUSTER_NAME}' with 8888:80@loadbalancer"
	k3d cluster create "${CLUSTER_NAME}" -p "8888:80@loadbalancer" --wait
	ok "cluster created"
fi

kubectl config use-context "k3d-${CLUSTER_NAME}" >/dev/null
kubectl cluster-info >/dev/null || die "cluster is not reachable"

# --- 2. namespaces ----------------------------------------------------------
# Pre-created so `kubectl get ns` shows both as Active even while the first
# sync is still in flight (subject p13's screenshot). CreateNamespace=true in
# the Application covers the case where this script is not the one that ran.
for ns in argocd dev; do
	kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
done
ok "namespaces argocd and dev ready"

# --- 3. Argo CD -------------------------------------------------------------
log "installing Argo CD ${ARGOCD_VERSION} (this pulls several images, be patient)"
# --server-side: the install manifest's CRDs exceed the 262144-byte annotation
# limit that a client-side apply would try to store in last-applied-configuration.
kubectl apply -n argocd --server-side --force-conflicts -f "${ARGOCD_MANIFEST}" >/dev/null

log "waiting for the Application CRD to be established"
kubectl wait --for=condition=established --timeout=120s crd/applications.argoproj.io >/dev/null

# Default reconciliation is 120s + up to 60s jitter — about three minutes of
# standing in silence during the v1 -> v2 demo. The controller reads this at
# startup, so it must be restarted for the change to take effect.
log "shortening the reconciliation interval to 20s"
kubectl -n argocd patch configmap argocd-cm --type merge \
	-p '{"data":{"timeout.reconciliation":"20s"}}' >/dev/null
kubectl -n argocd rollout restart statefulset argocd-application-controller >/dev/null

log "waiting for Argo CD to become available"
kubectl wait --for=condition=available --timeout=600s deployment --all -n argocd
kubectl -n argocd rollout status statefulset argocd-application-controller --timeout=300s >/dev/null
ok "Argo CD is up"

# --- 4. Application ---------------------------------------------------------
APP_FILE="${CONF_DIR}/application.yaml"
[ -f "$APP_FILE" ] || die "missing ${APP_FILE}"

TMP_APP="$(mktemp)"
trap 'rm -f "$TMP_APP"' EXIT
if [ -n "${REPO_URL:-}" ]; then
	log "using repository ${REPO_URL}"
	sed "s|repoURL:.*|repoURL: ${REPO_URL}|" "$APP_FILE" > "$TMP_APP"
else
	cp "$APP_FILE" "$TMP_APP"
fi

if grep -q "CHANGE_ME" "$TMP_APP"; then
	die "set the GitOps repo first: edit p3/confs/application.yaml (repoURL), or run
        REPO_URL=https://github.com/<login>/<repo>.git bash p3/scripts/create_cluster.sh"
fi

kubectl apply -f "$TMP_APP" >/dev/null
ok "Argo CD Application 'wil-playground' registered"

log "waiting for Argo CD to sync the app into the dev namespace"
for _ in $(seq 1 60); do
	kubectl get deployment -n dev playground >/dev/null 2>&1 && break
	sleep 5
done
kubectl wait --for=condition=available --timeout=300s deployment/playground -n dev 2>/dev/null \
	|| log "not ready yet — inspect with: kubectl get pods,ingress -n dev"

# --- 5. credentials and next steps ------------------------------------------
echo
ok "cluster ready."
echo
echo "  Argo CD admin password:"
echo "    $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"
echo
echo "  Application (the graded path, survives pod replacement):"
echo "    curl http://localhost:8888/"
echo
echo "  Argo CD UI (NOT graded — port-forward is fine here):"
echo "    kubectl port-forward -n argocd svc/argocd-server 8080:443"
