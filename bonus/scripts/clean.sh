#!/usr/bin/env bash
#
# bonus/scripts/clean.sh
# Deletes the cluster and (optionally) the /etc/hosts entry.
#
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-iot}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"${SCRIPT_DIR}/port-forward.sh" stop 2>/dev/null || true

if k3d cluster list -o json | grep -q "\"name\":\"${CLUSTER_NAME}\""; then
	k3d cluster delete "${CLUSTER_NAME}"
	printf '\033[1;32m[clean]\033[0m cluster %s deleted\n' "${CLUSTER_NAME}"
else
	printf '\033[1;33m[clean]\033[0m cluster %s does not exist\n' "${CLUSTER_NAME}"
fi

if [ "${1:-}" = "--hosts" ]; then
	"${SCRIPT_DIR}/hosts.sh" remove
fi
