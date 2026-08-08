#!/usr/bin/env bash
#
# bonus/scripts/hosts.sh [add|remove]
# Maps the in-cluster GitLab hostname to localhost so that your browser and
# your git client use the exact same URL that Argo CD uses inside the cluster.
#
set -euo pipefail

GITLAB_HOST="gitlab.gitlab.svc.cluster.local"
ENTRY="127.0.0.1 ${GITLAB_HOST}"

log() { printf '\033[1;34m[hosts]\033[0m %s\n' "$*"; }

case "${1:-add}" in
	add)
		if grep -qF "${GITLAB_HOST}" /etc/hosts; then
			log "entry already present"
		else
			log "adding '${ENTRY}' to /etc/hosts (sudo required)"
			echo "${ENTRY}" | sudo tee -a /etc/hosts >/dev/null
		fi
		;;
	remove)
		log "removing ${GITLAB_HOST} from /etc/hosts (sudo required)"
		sudo sed -i "/${GITLAB_HOST}/d" /etc/hosts
		;;
	*)
		echo "usage: $0 [add|remove]" >&2
		exit 1
		;;
esac
