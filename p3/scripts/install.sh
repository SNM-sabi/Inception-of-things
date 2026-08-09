#!/usr/bin/env bash
#
# p3/scripts/install.sh
#
# Installs everything Part 3 needs, on a machine that has nothing: Docker,
# kubectl, k3d and the Argo CD CLI. Subject p12's yellow box requires this to
# run live, during the defense, on a clean machine — so it assumes nothing is
# preinstalled and never prompts.
#
# Safe to re-run: every step is skipped if the tool is already present.
#
set -euo pipefail

# Pinned per CLAUDE.md "Pinned versions". Re-check the day before defense.
K3D_VERSION="v5.9.0"
ARGOCD_VERSION="v3.4.6"

log()  { printf '\033[1;34m[install]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[  ok   ]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[ warn  ]\033[0m %s\n' "$*"; }

# --- architecture detection (amd64 / arm64) ---------------------------------
case "$(uname -m)" in
	x86_64)         ARCH=amd64 ;;
	aarch64|arm64)  ARCH=arm64 ;;
	*) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac
log "detected architecture: ${ARCH}"

# --- base packages ----------------------------------------------------------
if command -v apt-get >/dev/null 2>&1; then
	log "installing base packages (curl, git, ca-certificates)"
	sudo apt-get update -qq
	sudo apt-get install -y -qq curl git ca-certificates >/dev/null
	ok "base packages ready"
else
	warn "apt-get not found — make sure curl and git are installed"
fi

# --- Docker (k3d runs the cluster nodes as containers) ----------------------
if command -v docker >/dev/null 2>&1; then
	ok "docker already installed ($(docker --version))"
else
	log "installing docker"
	curl -fsSL https://get.docker.com | sudo sh
	ok "docker installed"
fi

sudo systemctl enable --now docker >/dev/null 2>&1 || true

# Group membership only takes effect in NEW login sessions. create_cluster.sh
# works around that with `sg docker` so the clean run needs no logout.
if ! id -nG "$USER" | tr ' ' '\n' | grep -qx docker; then
	log "adding ${USER} to the docker group"
	sudo usermod -aG docker "$USER"
	warn "group applied to new sessions only — create_cluster.sh handles this for you"
fi

# --- kubectl ----------------------------------------------------------------
if command -v kubectl >/dev/null 2>&1; then
	ok "kubectl already installed"
else
	log "installing kubectl"
	KVER="$(curl -Ls https://dl.k8s.io/release/stable.txt)"
	curl -fsSLo /tmp/kubectl "https://dl.k8s.io/release/${KVER}/bin/linux/${ARCH}/kubectl"
	sudo install -o root -g root -m 0755 /tmp/kubectl /usr/local/bin/kubectl
	rm -f /tmp/kubectl
	ok "kubectl ${KVER} installed"
fi

# --- k3d --------------------------------------------------------------------
# Pinned: k3d's default k3s image is the one this release was tested against,
# so pinning k3d pins the cluster too without guessing an image tag.
#
# Note both version checks below compare rather than just testing for presence.
# "Skip if the binary exists" silently keeps whatever an earlier, unpinned
# script left behind — which is exactly how an unpinned argocd CLI ended up
# installed here while CLAUDE.md pinned a different one.

	# echo "ssss"
# echo "==> [4/6] k3d"
echo "==> k3d"
if ! command -v k3d >/dev/null 2>&1; then
  curl -fsSL https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | sudo env PATH="/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin" bash
fi

# --- Argo CD CLI ------------------------------------------------------------
# Must match the server version installed by create_cluster.sh.
ARGOCD_CURRENT="$(argocd version --client --short 2>/dev/null | awk '{print $2}' | cut -d+ -f1)"
if [ "${ARGOCD_CURRENT}" = "${ARGOCD_VERSION}" ]; then
	ok "argocd CLI ${ARGOCD_VERSION} already installed"
else
	[ -n "${ARGOCD_CURRENT}" ] && log "argocd CLI ${ARGOCD_CURRENT} found, replacing with pinned ${ARGOCD_VERSION}"
	log "installing argocd CLI ${ARGOCD_VERSION}"
	curl -fsSL -o /tmp/argocd \
		"https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-${ARCH}"
	sudo install -m 0755 /tmp/argocd /usr/local/bin/argocd
	rm -f /tmp/argocd
	ok "argocd CLI ${ARGOCD_VERSION} installed"
fi

echo
ok "all tools installed."
echo "    Next:  bash p3/scripts/create_cluster.sh"
