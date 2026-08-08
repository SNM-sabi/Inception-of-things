#!/usr/bin/env bash
#
# bonus/scripts/install.sh
# Same toolchain as p3 (docker, kubectl, k3d, argocd) plus helm,
# which is only needed if you take the Helm route for GitLab.
#
set -euo pipefail

log()  { printf '\033[1;34m[install]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[  ok   ]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[ warn  ]\033[0m %s\n' "$*"; }

case "$(uname -m)" in
	x86_64)        ARCH=amd64 ;;
	aarch64|arm64) ARCH=arm64 ;;
	*) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

if command -v apt-get >/dev/null 2>&1; then
	sudo apt-get update -qq
	sudo apt-get install -y -qq curl git ca-certificates >/dev/null
	ok "base packages ready"
fi

if command -v docker >/dev/null 2>&1; then
	ok "docker already installed"
else
	log "installing docker"
	curl -fsSL https://get.docker.com | sudo sh
fi
if ! id -nG "$USER" | tr ' ' '\n' | grep -qx docker; then
	sudo usermod -aG docker "$USER"
	warn "log out and back in (or: newgrp docker) before continuing"
fi
sudo systemctl enable --now docker >/dev/null 2>&1 || true

if command -v kubectl >/dev/null 2>&1; then
	ok "kubectl already installed"
else
	log "installing kubectl"
	KVER="$(curl -Ls https://dl.k8s.io/release/stable.txt)"
	curl -fsSLo /tmp/kubectl "https://dl.k8s.io/release/${KVER}/bin/linux/${ARCH}/kubectl"
	sudo install -m 0755 /tmp/kubectl /usr/local/bin/kubectl && rm -f /tmp/kubectl
fi

if command -v k3d >/dev/null 2>&1; then
	ok "k3d already installed"
else
	log "installing k3d"
	curl -fsSL https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | sudo bash
fi

if command -v argocd >/dev/null 2>&1; then
	ok "argocd CLI already installed"
else
	log "installing argocd CLI"
	curl -fsSL -o /tmp/argocd \
		"https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-${ARCH}"
	sudo install -m 0755 /tmp/argocd /usr/local/bin/argocd && rm -f /tmp/argocd
fi

if command -v helm >/dev/null 2>&1; then
	ok "helm already installed"
else
	log "installing helm"
	curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | sudo bash
fi

echo
ok "all tools installed. Next: ./scripts/setup.sh"
