#!/usr/bin/env bash
#
# bonus/scripts/gitlab-info.sh [password|url|logs|shell]
# Small helper around the running GitLab pod.
#
set -euo pipefail

GITLAB_HOST="gitlab.gitlab.svc.cluster.local"

case "${1:-info}" in
	password)
		# The password we set via GITLAB_OMNIBUS_CONFIG only applies on FIRST boot.
		# If it does not work, the generated one is in this file (deleted after 24h).
		kubectl exec -n gitlab deploy/gitlab -- \
			grep -m1 'Password:' /etc/gitlab/initial_root_password 2>/dev/null \
			| awk '{print $2}' \
			|| echo "Passw0rd!42"
		;;
	url)
		echo "http://${GITLAB_HOST}/"
		;;
	logs)
		kubectl logs -n gitlab deploy/gitlab -f
		;;
	shell)
		kubectl exec -it -n gitlab deploy/gitlab -- bash
		;;
	*)
		echo "GitLab URL : http://${GITLAB_HOST}/"
		echo "User       : root"
		echo "Password   : $("$0" password)"
		echo
		kubectl get pods -n gitlab
		;;
esac
