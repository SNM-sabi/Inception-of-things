#!/usr/bin/env bash
#
# bonus/scripts/deploy-app.sh
# Run this AFTER you created the GitLab project and pushed manifests/ into it.
#
# Usage:
#   ./scripts/deploy-app.sh
#   REPO_URL=http://gitlab.gitlab.svc.cluster.local/root/<project>.git ./scripts/deploy-app.sh
#
# For a PRIVATE project, register credentials first:
#   GITLAB_USER=root GITLAB_PASSWORD='Passw0rd!42' ./scripts/deploy-app.sh
#
set -euo pipefail

CONF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../confs" && pwd)"
REPO_URL="${REPO_URL:-http://gitlab.gitlab.svc.cluster.local/root/iot-app.git}"

log() { printf '\033[1;34m[deploy]\033[0m %s\n' "$*"; }
ok()  { printf '\033[1;32m[  ok  ]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[ fail ]\033[0m %s\n' "$*" >&2; exit 1; }

kubectl get ns argocd >/dev/null 2>&1 || die "argocd namespace missing — run ./scripts/setup.sh"

# --- optional credentials for a private project -----------------------------
if [ -n "${GITLAB_USER:-}" ] && [ -n "${GITLAB_PASSWORD:-}" ]; then
	log "registering repository credentials in Argo CD"
	kubectl apply -n argocd -f - <<EOF >/dev/null
apiVersion: v1
kind: Secret
metadata:
  name: gitlab-repo
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: ${REPO_URL}
  username: ${GITLAB_USER}
  password: ${GITLAB_PASSWORD}
EOF
	ok "credentials registered"
fi

log "pointing Argo CD at ${REPO_URL}"
sed "s|repoURL:.*|repoURL: ${REPO_URL}|" "${CONF_DIR}/application.yaml" | kubectl apply -f - >/dev/null
ok "Application registered"

log "waiting for the app to appear in the dev namespace"
for _ in $(seq 1 60); do
	kubectl get deployment -n dev playground >/dev/null 2>&1 && break
	sleep 5
done
kubectl wait --for=condition=available --timeout=300s deployment/playground -n dev 2>/dev/null \
	|| log "not ready yet — inspect with: kubectl describe application playground -n argocd"

echo
ok "done. Verify with ./scripts/check.sh"
