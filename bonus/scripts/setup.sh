#!/usr/bin/env bash
#
# bonus/scripts/setup.sh
# Creates the cluster (publishing host port 80), the three namespaces,
# Argo CD, and GitLab running inside the cluster.
#
# GitLab's first boot is slow. Budget 10-20 minutes and 6+ GB of RAM.
#
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-iot}"
GITLAB_HOST="gitlab.gitlab.svc.cluster.local"
CONF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../confs" && pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARGOCD_VERSION="v3.4.6"                       # pinned — the same version p3 installs
ARGOCD_MANIFEST="https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

log()  { printf '\033[1;34m[setup]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[ ok  ]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[fail]\033[0m %s\n' "$*" >&2; exit 1; }

# --- preflight --------------------------------------------------------------
for bin in docker kubectl k3d; do
	command -v "$bin" >/dev/null 2>&1 || die "$bin not found — run ./scripts/install.sh first"
done
docker info >/dev/null 2>&1 || die "cannot reach the docker daemon (newgrp docker, or log out/in)"

TOTAL_MB=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' || echo 0)
if [ "${TOTAL_MB}" -gt 0 ] && [ "${TOTAL_MB}" -lt 5500 ]; then
	warn "this VM has ${TOTAL_MB} MB of RAM — GitLab needs ~4 GB on its own. Expect trouble."
fi

# --- 1. cluster (port 80 published so the browser can reach GitLab) ---------
if k3d cluster list -o json | grep -q "\"name\":\"${CLUSTER_NAME}\""; then
	ok "cluster '${CLUSTER_NAME}' already exists"
	warn "if it was NOT created with both -p 80:80 and -p 8888:80, run ./scripts/clean.sh first"
else
	# Two host ports, both onto the load-balancer's :80, because they serve two
	# different subject requirements and k3d port maps are FIXED AT CREATE TIME:
	#   :80   -> GitLab, which must answer on the same hostname Argo CD clones
	#            from (external_url has no port, so it has to be 80).
	#   :8888 -> the application, so that p3's exact verification command
	#            `curl http://localhost:8888/` still works here. Subject p16:
	#            "Everything you did in Part 3 must work with your local Gitlab."
	log "creating k3d cluster '${CLUSTER_NAME}' with host ports 80 and 8888 published"
	k3d cluster create "${CLUSTER_NAME}" \
		-p "80:80@loadbalancer" \
		-p "8888:80@loadbalancer" \
		--wait
	ok "cluster created"
fi
kubectl config use-context "k3d-${CLUSTER_NAME}" >/dev/null

# --- 2. namespaces ----------------------------------------------------------
for ns in argocd dev gitlab; do
	kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
done
ok "namespaces argocd, dev and gitlab ready"

# --- 3. Argo CD -------------------------------------------------------------
log "installing Argo CD ${ARGOCD_VERSION}"
# --server-side: the install manifest's CRDs exceed the 262144-byte annotation
# limit a client-side apply would try to store in last-applied-configuration.
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

kubectl wait --for=condition=available --timeout=600s deployment --all -n argocd
kubectl -n argocd rollout status statefulset argocd-application-controller --timeout=300s >/dev/null
ok "Argo CD is up"

# --- 4. /etc/hosts ----------------------------------------------------------
"${SCRIPT_DIR}/hosts.sh" add

# --- 5. GitLab --------------------------------------------------------------
log "deploying GitLab (image is ~3 GB, first boot runs gitlab-ctl reconfigure)"
kubectl apply -f "${CONF_DIR}/gitlab.yaml" >/dev/null

log "waiting for GitLab — this legitimately takes 10 to 20 minutes"
log "follow along in another terminal: kubectl logs -n gitlab deploy/gitlab -f"
if ! kubectl wait --for=condition=available --timeout=2400s deployment/gitlab -n gitlab; then
	kubectl get pods -n gitlab
	die "GitLab did not become ready — check: kubectl describe pod -n gitlab -l app=gitlab"
fi
ok "GitLab is ready"

# --- 6. summary -------------------------------------------------------------
echo
ok "infrastructure ready."
echo
echo "  GitLab   : http://${GITLAB_HOST}/   (user: root)"
echo "  password : $("${SCRIPT_DIR}/gitlab-info.sh" password 2>/dev/null || echo 'see ./scripts/gitlab-info.sh')"
echo
echo "  Next steps:"
echo "    1. log into GitLab and create a PUBLIC project named 'iot-app'"
echo "    2. push confs/app-repo/*.yaml into a manifests/ folder of that project"
echo "    3. run ./scripts/deploy-app.sh"
