#!/usr/bin/env bash
# p1 — install K3s in SERVER (controller) mode on smbarkiS.
# Subject p6: "In the first one (Server), it will be installed in controller mode."
# Runs as root (Vagrant shell provisioner). Inputs come from the Vagrantfile via env:.
set -euo pipefail

NODE_IP="${NODE_IP:?NODE_IP must be passed from the Vagrantfile}"
K3S_TOKEN="${K3S_TOKEN:?K3S_TOKEN must be passed from the Vagrantfile}"
K3S_VERSION="v1.36.3+k3s1"

# --- 1. Find which interface carries our dedicated IP -----------------------
# Never hardcoded: p8's info box says interface names vary by system.
IFACE=$(ip -o -4 addr show | awk -v ip="$NODE_IP" '$4 ~ "^"ip"/" {print $2; exit}')
echo "==> dedicated IP $NODE_IP is on interface: $IFACE"

# --- 2. Install K3s, pinned, in server mode ---------------------------------
# --node-ip        : advertise the dedicated IP, not eth0's DHCP lease (which
#                    changes on every rebuild — observed .46 -> .233).
# --flannel-iface  : pin the pod network to the same interface.
# --write-kubeconfig-mode : kubeconfig readable by the vagrant user, so kubectl
#                    needs no sudo. Acceptable in this closed lab VM.
# The token is PRE-SEEDED: we tell the server which token to accept instead of
# copying the one it would generate (no credential in /vagrant, nothing stale
# after destroy).
command -v curl >/dev/null || { apt-get update -qq && apt-get install -y -qq curl; }
curl -sfL https://get.k3s.io | \
  INSTALL_K3S_VERSION="$K3S_VERSION" \
  K3S_TOKEN="$K3S_TOKEN" \
  INSTALL_K3S_EXEC="server --node-ip=$NODE_IP --flannel-iface=$IFACE --write-kubeconfig-mode=0644" \
  sh -s -

# --- 3. kubectl without sudo or flags for interactive use -------------------
# The installer already symlinked /usr/local/bin/kubectl -> k3s (that satisfies
# p6's yellow box). This makes login shells point it at the right kubeconfig.
echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' > /etc/profile.d/k3s.sh

# --- 4. Do not declare success until the node is actually Ready -------------
until /usr/local/bin/kubectl get node >/dev/null 2>&1; do sleep 2; done
/usr/local/bin/kubectl wait --for=condition=Ready node --all --timeout=180s
/usr/local/bin/kubectl get node -o wide
