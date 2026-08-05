# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

42 School **Inception-of-things (IoT)**, subject version 4.0. `en.subject.pdf` at the repo root is the single source of truth for grading; **[PLAN.md](PLAN.md)** is the agreed build plan and work split. Three progressively larger Kubernetes labs — K3s on Vagrant VMs, K3s Ingress host routing, K3d + Argo CD GitOps — plus a GitLab bonus.

Graded by **live defense on our own machine** (p17). The deliverable is not files that look right; it is a stack that boots from zero in front of an evaluator while we explain every line.

## How we work — read this before touching anything

### Scope guard
Do exactly what the subject asks, nothing more. No monitoring stack, no cert-manager, no second ingress controller, no Helm where plain YAML does, no namespaces beyond `default` / `argocd` / `dev` / `gitlab`. Where the subject says "of your choice", pick the smallest thing that works and can be justified in one sentence. Where the subject prints a literal, match it byte-for-byte — including the odd spacing in `{"status":"ok", "message": "v1"}`.

Every extra moving part is a new way to fail a live demo and a new question to answer.

### Micro-step protocol
Advance in the smallest slice that can be *observed working*:
1. **Explain first** — what the slice does, which subject requirement it satisfies (with page number), what we expect to see.
2. Implement that slice only.
3. **Observe it** — run the command that proves it and show real output. Never "it should work".
4. Explain what we saw, including anything surprising.
5. Only then move on.

A slice is "the two VMs boot with the right hostnames", not "part 1 works".

### The gate before every commit, push, or part transition
All four must hold:
- **Clean run**: `vagrant destroy -f && vagrant up` (or `k3d cluster delete && bash install.sh`) from zero, no manual steps, no prompts.
- **Every checklist item green**, verified with the evaluator's own commands.
- **Every line explainable without notes.** If a flag cannot be explained, delete it — that is how cargo-cult gets out.
- **Nothing outside that part's folder changed.**

### Work split — which folders a session may touch
| Unit | Owner | Owns |
|---|---|---|
| W1 — VMs & K3s | smbarki (acting as 2) | `p1/`, `p2/` |
| W2 — K3d & GitOps | Person 3 | `p3/` |
| W3 — GitLab | gated on mandatory being flawless | `bonus/` |

Branch per unit (`p1p2`, `p3`, `bonus`), merge to `main` only after the gate. Units never edit each other's folders; `README.md`, `CLAUDE.md`, `.gitignore` are shared and changed on `main` by agreement. Subject p5 mandates the p1 → p2 → p3 order.

## Non-negotiable values (graded literally)

| Thing | Value |
|---|---|
| Team login | `smbarki` |
| Server VM / hostname | `smbarkiS` — **but `kubectl get nodes` shows `smbarkis`** (see traps) |
| Worker VM / hostname | `smbarkiSW` |
| Server IP | `192.168.56.110` |
| Worker IP | `192.168.56.111` |
| VM resources | 1 CPU; server 1024 MB, worker 512 MB (subject allows either) |
| Vagrant provider | libvirt/KVM primary, VirtualBox fallback — p4 permits any provider |
| Guest distro | Debian 13 (trixie), latest stable |
| p2 namespace | `default` (p11's `kubectl get all` has no `-n`) |
| p2 routing | `Host: app1.com` → app1, `app2.com` → app2, anything else → app3 via `spec.defaultBackend` |
| p2 replicas | app2 = **3**; app1 and app3 = 1 |
| p3 namespaces | `argocd` and `dev` |
| p3 app | `wil42/playground:v1` / `:v2`, container port **8888**, reachable at `http://localhost:8888/` |
| p3 public repo | name must contain `smbarki`, must be **public** |
| Bonus namespace | `gitlab` |

Also mandatory: latest stable distro, passwordless SSH to both VMs, and the whole project run inside a virtual machine (p4).

## Pinned versions (verified 2026-08-02 — re-check the day before defense)

```
debian/trixie64   13.20260519.1   (libvirt; official Debian)
bento/debian-13   202510.26.0     (virtualbox fallback)
Vagrant           2.4.9           (no vagrant package exists in Debian/Ubuntu repos)
K3s               v1.36.2+k3s1    (bundles Traefik v3.7.4)
k3d               v5.9.0
Argo CD           v3.4.6
GitLab CE         19.2.1-ce.0     (19.3 lands ~2026-08-20)
```

## Required directory layout

```
p1/     Vagrantfile  scripts/  confs/     K3s server + agent, two VMs
p2/     Vagrantfile  scripts/  confs/     One VM, 3 apps, one Ingress
p3/                  scripts/  confs/     K3d + Argo CD — NO Vagrantfile (p12: "without Vagrant")
bonus/               scripts/  confs/     GitLab in the p3 cluster
```

Scripts in `scripts/`, manifests in `confs/` — mandated by p17's yellow box. The p17 example tree also shows `./bonus/Vagrantfile`; our bonus runs inside k3d, so we omit it deliberately and can say why.

## Part 3 uses two repositories

`p3/confs/` holds **only** the Argo CD `Application` CR. The Kubernetes manifests it points at live in a **separate public GitHub repo** named with `smbarki` (e.g. `smbarki-iot-gitops`), under `manifests/`. Argo CD polls that repo; the v1 → v2 demo is done by editing the image tag *there* and pushing — never with `kubectl set image`.

Do not keep a copy of `deployment.yaml` in `p3/confs/`: the evaluator will ask which one is live and it will look hand-applied.

## Commands

### p1 / p2 — Vagrant (from inside `p1/` or `p2/`)
```bash
vagrant up                      # boot + provision, in definition order
vagrant status
vagrant ssh smbarkiS            # passwordless: Vagrant generates a per-machine keypair
vagrant provision               # re-run provisioning without rebooting
vagrant destroy -f              # always destroy before re-testing from scratch
```

### K3s inside the VMs
```bash
# server — the token is PRE-SEEDED, not copied from the server (see traps)
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.36.2+k3s1" K3S_TOKEN="$K3S_TOKEN" \
  INSTALL_K3S_EXEC="server --node-ip=${NODE_IP} --flannel-iface=${IFACE} \
  --write-kubeconfig-mode=0644 --tls-san=${NODE_IP}" sh -s -

# agent — gate on the server being reachable first
until curl -sfk "https://192.168.56.110:6443/cacerts" >/dev/null 2>&1; do sleep 3; done
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.36.2+k3s1" \
  K3S_URL="https://192.168.56.110:6443" K3S_TOKEN="$K3S_TOKEN" \
  INSTALL_K3S_EXEC="agent --node-ip=${NODE_IP} --flannel-iface=${IFACE}" sh -s -
```
Detect the interface at runtime, never hardcode it:
`IFACE=$(ip -o -4 addr show | awk -v ip="$NODE_IP" '$4 ~ "^"ip"/" {print $2; exit}')`

Kubeconfig lands at `/etc/rancher/k3s/k3s.yaml`. Drop `/etc/profile.d/k3s.sh` exporting `KUBECONFIG` so `vagrant ssh smbarkiS -c "kubectl get nodes"` works with no sudo and no flags (`vagrant ssh -c` runs a login shell, so `/etc/profile.d` is sourced but `~/.bashrc` is not).

### p3 — K3d + Argo CD (on the host)
```bash
bash p3/scripts/install.sh                       # docker, k3d, kubectl, argocd CLI — from nothing
k3d cluster create iot -p "8888:80@loadbalancer" --wait
kubectl create namespace argocd && kubectl create namespace dev
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.4.6/manifests/install.yaml
kubectl apply -f p3/confs/application.yaml

kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
kubectl port-forward -n argocd svc/argocd-server 8080:443      # UI only; NOT the graded path
```
p12's yellow box requires `p3/scripts/` to install **everything** from scratch, live, on a clean machine.

### Bonus — GitLab
```bash
kubectl create namespace gitlab
helm upgrade --install gitlab ./bonus/confs/chart -n gitlab    # gitlab/gitlab-ce:19.2.1-ce.0
```

## Verification — this project's "tests"

```bash
# p1 — both Ready, host-only IPs, one control-plane + one agent
vagrant ssh smbarkiS -c "kubectl get nodes -o wide"

# p2 — from the HOST, not from inside the VM
curl -H "Host: app1.com" http://192.168.56.110
curl -H "Host: app2.com" http://192.168.56.110
curl http://192.168.56.110                                       # app3
for i in $(seq 9); do curl -s -H "Host: app2.com" http://192.168.56.110 | head -1; done | sort | uniq -c
vagrant ssh smbarkiS -c "kubectl describe ingress"               # p11 red box: must be shown live

# p3 — the GitOps loop
kubectl get ns                                                   # argocd + dev
curl -s http://localhost:8888/                                   # {"status":"ok", "message": "v1"}
# edit the tag in the public repo, commit, push, touch nothing else
curl -s http://localhost:8888/                                   # {"status":"ok", "message": "v2"}
argocd app get wil-playground                                    # Synced, Healthy, self-initiated
```

## Architecture notes and traps

- **`--node-ip` is the one flag that matters.** Vagrant forces NIC 1 to be NAT (that is how `vagrant ssh` port-forwards) and every VM gets the identical `10.0.2.15`. Without `--node-ip`, both nodes register with it; the agent still joins so `get nodes` reads Ready, and the breakage stays hidden until p2's traffic test. `--flannel-iface` is cheap insurance. **`--advertise-address` already defaults to `--node-ip`** (noise). **`--bind-address=192.168.56.110` is harmful** — the apiserver stops listening on loopback while the generated kubeconfig still targets `127.0.0.1:6443`, breaking your own kubectl.
- **Node names are lowercased.** The VM hostname stays `smbarkiS`, but Kubernetes canonicalises node names, so `kubectl get nodes` shows `smbarkis`. This is not a bug — rehearse the explanation. Never set `--node-name=smbarkiS`; k3s refuses to start on an uppercase RFC-1123 name.
- **Pre-seed the join token; do not copy the generated one.** Define it once in the Vagrantfile and pass it to *both* provisioners via `env:`. Copying `/var/lib/rancher/k3s/server/node-token` through `/vagrant` commits a live credential into the repo, leaves a stale token that survives `vagrant destroy` (agent then fails with `token CA hash does not match`), and does not work at all under libvirt where the synced folder is one-way rsync. Defense answer: *"I inverted the dependency — instead of the agent reading a token the server generated, I told the server which token to use."*
- **kubectl needs no separate install.** The K3s installer symlinks `/usr/local/bin/kubectl → k3s`. That satisfies p6's yellow box, and `ls -l /usr/local/bin/kubectl` is the proof. Installing it from the Kubernetes apt repo adds an external repo and invites version skew.
- **Traefik ships with K3s** (v3.7.4). p2 needs only Deployment + Service + Ingress. A plain `networking.k8s.io/v1` Ingress is sufficient — do not use `IngressRoute`. Set `ingressClassName: traefik`; never the deprecated `kubernetes.io/ingress.class` annotation.
- **app3 must be `spec.defaultBackend`, in a single Ingress object.** A host-less rule *appears* to work, but Traefik v3 orders routers by rule-string length, so it only loses to `app1.com` by accident. `defaultBackend` compiles to priority `math.MinInt32` and cannot be outranked. `default-router`/`default-backend` are global singletons, so a second Ingress declaring one is silently dropped. **Never add `traefik.ingress.kubernetes.io/router.priority`** to that object — it applies to every router the Ingress produces, including the default one, and app3 would then swallow app1.com and app2.com.
- **Port 80 reaches the host for free.** Traefik's Service is `LoadBalancer`; K3s's ServiceLB runs a DaemonSet taking hostPort 80/443 on the node. Nothing else may claim those ports.
- **K3d port maps are fixed at create time.** `--port-add` exists but is EXPERIMENTAL and recreates the load-balancer container. Forgetting `-p "8888:80@loadbalancer"` means deleting and recreating the cluster mid-defense.
- **Never use `kubectl port-forward` as p3's graded path.** It dies exactly when the pod is replaced — the v1 → v2 moment. Fine for the Argo CD UI, which is not graded.
- **Shorten Argo CD's reconciliation interval.** Default is 120 s + up to 60 s jitter ≈ 3 minutes of silence. Patch `argocd-cm` to `timeout.reconciliation: 20s` in the install script.
- **Pre-create `dev` *and* set `CreateNamespace=true`**, so p13's `kubectl get ns` is true even mid-sync. But never put a `Namespace` object in the watched repo alongside `prune: true` — a bad commit would delete the namespace and everything in it.
- **GitLab chart 10.x removed the bundled PostgreSQL, Redis and MinIO** and needs PostgreSQL 17 plus Gateway API. Every older tutorial is now wrong. Use the `gitlab/gitlab-ce` Omnibus container instead — same official artifact, self-contained, ~3 GB instead of 6–8 GB.
- **Argo CD resolves `repoURL` through CoreDNS**, which knows nothing about `/etc/hosts`, `nip.io` or `192.168.56.x`. For the bonus, use one canonical URL valid inside and outside the cluster: `gitlab.gitlab.svc.cluster.local` on port 80.
- **NordVPN is installed on this host.** Its kill-switch iptables rules pre-empt Docker's chains and blackhole `192.168.56.x`. Disconnect before any demo.

## Questions the evaluator will ask

- What is the difference between K3s and K3d? (p12 states you must know this.)
- How does the worker get the join token, and why that way?
- Why does `kubectl get nodes` show a lowercase name?
- Show me the Ingress and explain how app3 gets selected by default. (p11 red box.)
- Prove app2's three replicas are actually load-balancing.
- Prove Argo CD, not you, performed the v1 → v2 update.

## Defense constraints

- Evaluation runs on the evaluated group's own computer, so the install scripts must work there end to end.
- Only what is committed to the git repository is evaluated.
- The Ingress is deliberately absent from the subject's screenshots — it must be shown and explained live.
- The bonus is scored **only if the mandatory part is flawless**. Do not start GitLab before p1–p3 are fully working and rehearsed.
