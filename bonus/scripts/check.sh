#!/usr/bin/env bash
#
# bonus/scripts/check.sh
# Everything the evaluator will ask to see.
#
set -euo pipefail

GITLAB_HOST="gitlab.gitlab.svc.cluster.local"
hdr() { printf '\n\033[1;36m=== %s ===\033[0m\n' "$*"; }

hdr "nodes (k3d nodes are docker containers)"
kubectl get nodes -o wide

hdr "namespaces"
kubectl get namespaces

hdr "gitlab namespace"
kubectl get all -n gitlab

hdr "gitlab reachable over HTTP"
curl -s -o /dev/null -w 'http://%{url_effective} -> %{http_code}\n' "http://${GITLAB_HOST}/-/health" || echo "unreachable"

hdr "argocd application"
kubectl get application -n argocd -o wide 2>/dev/null || echo "no Application object"

hdr "argocd repository in use"
kubectl get application playground -n argocd \
	-o jsonpath='{.spec.source.repoURL}{"\n"}' 2>/dev/null || true

hdr "dev namespace"
kubectl get all -n dev

hdr "image currently deployed"
kubectl get deployment -n dev playground \
	-o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}' 2>/dev/null \
	|| echo "deployment not found"

hdr "app response"
if kubectl get svc -n dev playground >/dev/null 2>&1; then
	kubectl port-forward -n dev svc/playground 8888:8888 >/dev/null 2>&1 &
	PF=$!
	sleep 3
	curl -s http://localhost:8888/ || echo "no response"
	echo
	kill "$PF" 2>/dev/null || true
else
	echo "service not found in dev"
fi
