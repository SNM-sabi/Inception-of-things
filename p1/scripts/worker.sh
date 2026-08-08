#!/usr/bin/env bash
# p1 — install K3s in AGENT mode on smbarkiSW and join the server's cluster.
# Subject p6: "In the second one (ServerWorker), in agent mode."
# Runs as root (Vagrant shell provisioner). Inputs come from the Vagrantfile via env:.
set -euo pipefail

NODE_IP="${NODE_IP:?NODE_IP must be passed from the Vagrantfile}"
SERVER_IP="${SERVER_IP:?SERVER_IP must be passed from the Vagrantfile}"
K3S_TOKEN="${K3S_TOKEN:?K3S_TOKEN must be passed from the Vagrantfile}"
K3S_VERSION="v1.36.3+k3s1"

command -v curl >/dev/null || { apt-get update -qq && apt-get install -y -qq curl; }

# --- 1. Find which interface carries our dedicated IP -----------------------
IFACE=$(ip -o -4 addr show | awk -v ip="$NODE_IP" '$4 ~ "^"ip"/" {print $2; exit}')
echo "==> dedicated IP $NODE_IP is on interface: $IFACE"

# --- 2. Never race the server -----------------------------------------------
# On a cold `vagrant up` both machines provision in definition order, but the
# agent must not try to join an API server that is still starting.
echo "==> waiting for the K3s API at https://$SERVER_IP:6443 ..."
until curl -sfk "https://$SERVER_IP:6443/cacerts" >/dev/null 2>&1; do sleep 3; done
echo "==> server is answering"

# --- 3. Install K3s, pinned, in agent mode -----------------------------------
# K3S_URL     : join the server over the dedicated network (the path proved by
#               ping in slice 1.3).
# K3S_TOKEN   : the same PRE-SEEDED token the Vagrantfile gave the server —
#               the agent never reads anything off the server's filesystem.
# --node-ip   : register as .111, not eth0's DHCP lease.
curl -sfL https://get.k3s.io | \
  INSTALL_K3S_VERSION="$K3S_VERSION" \
  K3S_URL="https://$SERVER_IP:6443" \
  K3S_TOKEN="$K3S_TOKEN" \
  INSTALL_K3S_EXEC="agent --node-ip=$NODE_IP --flannel-iface=$IFACE" \
  sh -s -

# --- 4. Do not declare success until the agent service is actually up --------
systemctl is-active --quiet k3s-agent || systemctl status k3s-agent --no-pager
echo "==> k3s-agent: $(systemctl is-active k3s-agent)"
