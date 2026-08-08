#!/usr/bin/env bash
#
# p3/scripts/reset.sh
#
# Deletes the k3d cluster, and with it Argo CD, both namespaces and the app.
# This is the teardown half of the clean-run gate: the evaluator's machine
# starts from nothing, so "it works right now" only counts if it still works
# after this script has run.
#
# Docker images are deliberately NOT pruned — that would wipe unrelated images
# on the machine, and re-pulling Argo CD is several minutes of the defense.
#
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-iot}"

if k3d cluster list -o json 2>/dev/null | grep -q "\"name\":\"${CLUSTER_NAME}\""; then
	k3d cluster delete "${CLUSTER_NAME}"
	printf '\033[1;32m[reset]\033[0m cluster %s deleted\n' "${CLUSTER_NAME}"
else
	printf '\033[1;33m[reset]\033[0m cluster %s does not exist\n' "${CLUSTER_NAME}"
fi
