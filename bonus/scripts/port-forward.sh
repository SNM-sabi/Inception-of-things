#!/usr/bin/env bash
#
# bonus/scripts/port-forward.sh [start|stop]
# GitLab is reachable through the ingress on http://gitlab.gitlab.svc.cluster.local/
# so only Argo CD and the app need forwarding.
#
set -euo pipefail

PID_FILE="/tmp/iot-bonus-portforward.pids"
log() { printf '\033[1;34m[pf]\033[0m %s\n' "$*"; }

stop() {
	if [ -f "$PID_FILE" ]; then
		while read -r pid; do kill "$pid" 2>/dev/null || true; done < "$PID_FILE"
		rm -f "$PID_FILE"
		log "port-forwards stopped"
	else
		log "nothing to stop"
	fi
}

[ "${1:-start}" = "stop" ] && { stop; exit 0; }

stop
: > "$PID_FILE"

# Only the Argo CD UI is forwarded. The UI is not graded, so a forward that dies
# with the pod costs nothing here. The APPLICATION is deliberately NOT forwarded:
# it is reached through the Ingress on host port 80, which survives Argo CD
# replacing the pod during the v1 -> v2 demo.
kubectl port-forward -n argocd svc/argocd-server 8080:443 >/dev/null 2>&1 &
echo $! >> "$PID_FILE"

sleep 3
log "Argo CD UI : https://localhost:8080          (user: admin, NOT graded)"
log "GitLab     : http://gitlab.gitlab.svc.cluster.local/   (user: root)"
log "Application: http://localhost/                (via ingress, no forward)"
log "stop with  : ./scripts/port-forward.sh stop"
