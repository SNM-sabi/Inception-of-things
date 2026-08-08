#!/usr/bin/env bash
# p2 — install K3s in SERVER mode on the single machine smbarkiS.
# Subject p9: "you will need only one virtual machine ... and K3s in server mode installed."
# Runs as root (Vagrant shell provisioner). NODE_IP comes from the Vagrantfile via env:.
set -euo pipefail

NODE_IP="${NODE_IP:?NODE_IP must be passed from the Vagrantfile}"
K3S_VERSION="v1.36.3+k3s1"

# --- 1. Find which interface carries our dedicated IP -----------------------
IFACE=$(ip -o -4 addr show | awk -v ip="$NODE_IP" '$4 ~ "^"ip"/" {print $2; exit}')
echo "==> dedicated IP $NODE_IP is on interface: $IFACE"

# --- 2. Install K3s, pinned, in server mode ---------------------------------
# Differences from p1's server.sh, both deliberate:
#   - NO K3S_TOKEN: there is no worker in p2, so a join token serves nothing.
#   - Traefik and ServiceLB stay ENABLED: p2 is about routing web traffic.
#     Traefik terminates the Ingress rules; ServiceLB gives Traefik's
#     LoadBalancer Service hostPort 80/443 on the node, which is what makes
#     `curl http://192.168.56.110` from the host reach Traefik at all.
#   - metrics-server and local-storage remain disabled: p2 uses neither, and
#     p1 taught us the full bundle does not fit 1024 MB on v1.36.
command -v curl >/dev/null || { apt-get update -qq && apt-get install -y -qq curl; }
curl -sfL https://get.k3s.io | \
  INSTALL_K3S_VERSION="$K3S_VERSION" \
  INSTALL_K3S_EXEC="server --node-ip=$NODE_IP --flannel-iface=$IFACE \
    --write-kubeconfig-mode=0644 \
    --disable metrics-server --disable local-storage" \
  sh -s -

# --- 3. kubectl without sudo or flags for interactive use -------------------
echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' > /etc/profile.d/k3s.sh

# --- 4. Do not declare success until the node is Ready and Traefik serves ---
until [ "$(/usr/local/bin/kubectl get nodes --no-headers 2>/dev/null | wc -l)" -ge 1 ]; do
  sleep 2
done
/usr/local/bin/kubectl wait --for=condition=Ready node --all --timeout=180s

# Traefik arrives as a Helm job a little after the node is Ready. Port 80
# answering (even with 404) is the real "routing layer is up" signal.
echo "==> waiting for Traefik to answer on :80 ..."
until curl -s -o /dev/null "http://$NODE_IP"; do sleep 3; done
echo "==> Traefik is serving on $NODE_IP:80"
/usr/local/bin/kubectl get pods -A
