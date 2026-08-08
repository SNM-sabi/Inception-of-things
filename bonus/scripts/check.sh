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

hdr "ingress in dev"
kubectl get ingress -n dev

hdr "app response (through the ingress — no port-forward)"
# Deliberately NOT `kubectl port-forward`: it dies the moment Argo CD replaces
# the pod, which is precisely the v1 -> v2 moment being demonstrated. Port 8888
# is p3's exact verification command, kept working here because subject p16 says
# "Everything you did in Part 3 must work with your local Gitlab".
#   host :8888 -> k3d LB :80 -> Traefik -> Ingress -> Service :8888
curl -s --max-time 10 http://localhost:8888/ || echo "no response"
echo
