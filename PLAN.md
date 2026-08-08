# Inception-of-Things — build plan, work split, and working method

## Context

`/home/sabdark/Desktop/1337/Inception-of-things` currently holds two files: `en.subject.pdf` (subject v4.0) and the `CLAUDE.md` written earlier this session. **It is not a git repository yet.** Nothing has been implemented and no tooling is installed on the host except `git`.

The goal is to deliver the *entire* subject — p1, p2, p3 **and** the bonus — split into three independent work-units so three people can work in parallel and merge without conflicts. You are acting as two of those people and take **p1 + p2**; Person 3 takes **p3**; the bonus is gated behind "mandatory is flawless".

The subject is graded by live defense on our own machine (p17). So the deliverable is not "files that look right" — it is **a stack that boots from zero, in front of an evaluator, while we explain every line**. That is what this plan optimises for.

Every technical claim below was verified on 2026-08-02 against live sources (Vagrant registry API, `update.k3s.io` channels, Docker Hub API, Argo CD / GitLab docs) and against this machine. Version pins must be re-checked the day before defense.

---

## 1. Decisions locked

| Decision | Choice | Why |
|---|---|---|
| Team login | `smbarki` | From git config; drives hostnames `smbarkiS` / `smbarkiSW` and the public repo name (p6, p12) |
| Guest distro | **Debian 13 (trixie)**, latest stable | Subject demands "latest stable version of the distribution of your choice" (p6, p9, bold). Debian 13.6 is current stable; boots a K3s server in ~90 MB RSS, no snapd/SELinux/firewalld |
| Where we run | **Inside an outer VM** | Subject p4 bullet 1, bold: "The whole project has to be done in a **virtual machine**." This host is bare metal (`systemd-detect-virt` → `none`) |
| Vagrant provider | **libvirt/KVM** (primary), VirtualBox fallback | p4 blue box explicitly permits it: *"You can use any tools you want to set up your host virtual machine as well as the provider used in Vagrant."* Nested KVM-in-KVM is reliable; nested VirtualBox-in-KVM is not |
| p3 app | **`wil42/playground:v1` / `:v2`** | Offered by the subject (p13). Only two tags exist, both amd64, port 8888, exact response bodies match the subject transcript. Zero build risk |
| p2 apps | **`traefik/whoami:v1.12.0`** ×3 | One 5 MB image, `WHOAMI_NAME` env gives each app an identity, and every response starts with `Hostname: <pod>` — which is how we *prove* app2's 3 replicas load-balance |
| Bonus GitLab | **`gitlab/gitlab-ce:19.2.1-ce.0`** as a pod in ns `gitlab` | Same official 19.2.1 artifact the chart deploys, but self-contained. Chart 10.x **removed bundled PostgreSQL/Redis/MinIO** — see §11 |

### Version pins (verified 2026-08-02)

```
Debian box (libvirt)   debian/trixie64        13.20260519.1   ← official Debian
Debian box (vbox)      bento/debian-13        202510.26.0     ← fallback only
Vagrant                2.4.9
K3s                    v1.36.2+k3s1           (Traefik v3.7.4 bundled)
k3d                    v5.9.0
Argo CD                v3.4.6
GitLab CE              19.2.1-ce.0            ← GitLab 19.3 lands ~2026-08-20, re-check
```

---

## 2. How we work — the ground rules

These are the rules you asked for, made concrete. They go into `CLAUDE.md` so every future session obeys them.

### 2.1 Scope guard — do exactly what the subject asks

- **Nothing that is not demanded or explicitly permitted goes in.** No monitoring stack, no cert-manager, no second ingress controller, no Helm where plain YAML does, no extra namespaces beyond `default` / `argocd` / `dev` / `gitlab`.
- **Where the subject says "of your choice", we choose the smallest thing that works** and can justify it in one sentence.
- **Where the subject prints a literal, we match it byte-for-byte.** `192.168.56.110`, `smbarkiS`, `dev`, `8888`, `{"status":"ok", "message": "v1"}` — including that file's odd spacing.
- Rationale: this is a graded exercise with a checklist, not a product. Every extra moving part is a new way to fail a live demo and a new question we have to answer.

### 2.2 Micro-step protocol

Work advances in the smallest slice that can be *observed working*. For each slice:

1. **Explain first.** Before writing anything, state what the slice does, which subject requirement it satisfies (with page number), and what we expect to see when it works.
2. **Implement the slice only.**
3. **Observe it.** Run the specific command that proves it. Not "it should work" — paste the output.
4. **Explain what we just saw**, including anything surprising.
5. Only then move on.

A slice is things like "the two VMs boot with the right hostnames" — *not* "part 1 works".

### 2.3 The gate before every commit / push / part transition

Nothing is pushed and no part is declared done until **all four** hold:

- **Clean-run reproducibility**: `vagrant destroy -f && vagrant up` (or `k3d cluster delete && bash install.sh`) from zero, no manual steps, no interactive prompts.
- **Every checklist item for that part is green**, verified by running the evaluator's own commands.
- **Both of us can explain every line** of every file in the part, without notes. If you cannot explain a flag, delete it — that is also how we avoid cargo-cult.
- **Nothing outside that part's folder changed.**

### 2.4 Merge discipline

- One branch per work-unit: `p1p2`, `p3`, `bonus`. Merge to `main` only after the gate passes.
- **Work-units never touch each other's folders.** The only shared files are `README.md`, `CLAUDE.md` and `.gitignore`, and those are edited on `main` by agreement.
- `.gitignore` from commit #1 must contain `.vagrant/` — it holds the per-machine SSH **private keys** and stale VM UUIDs. Committing it leaks a key and breaks `vagrant up` on a fresh clone.

---

## 3. The three work-units

The whole project (bonus included) is cut into three units that share **zero files**. That is what makes the merge trivial.

| Unit | Owner | Folders it owns | Roughly |
|---|---|---|---|
| **W1 — VMs & K3s** | **You (person 1+2)** | `p1/`, `p2/` | 40 % |
| **W2 — K3d & GitOps** | Person 3 | `p3/` | 35 % |
| **W3 — GitLab** | gated; see below | `bonus/` | 25 % |

**Why p1+p2 are the pair you take:** they are the most related units in the subject. p2 is p1 with one VM instead of two, plus workloads. The Vagrantfile skeleton, the Debian box, the K3s server install, the interface-detection logic, the passwordless-SSH story and the provisioning-script layout are **identical**. Doing them together costs about 1.4× one part, not 2×. Splitting them across two people would mean two people solving the same K3s networking problem twice.

**Why p3 is one person's unit:** it shares nothing with p1/p2 — no Vagrant, different tooling (Docker/k3d/Argo CD), and it owns a *second, separate* GitHub repository. It is cleanly isolable.

**The bonus:** it extends p3 and must not perturb it, so Person 3 leads it, with you assisting on the container/storage side. It only starts when §12's entry condition is met.

**Ordering constraint (subject p5):** "It is divided into three parts you have to do in the following order." Your p1 → p2 sequence is mandatory. p3 can run in parallel with p1/p2 in wall-clock terms because it is a different person and a different folder — but Person 3 should not *defend* p3 before p1/p2 exist.

---

## 4. Repository layout

Exactly the subject's p17 tree, nothing more:

```
Inception-of-things/
├── .gitignore              # .vagrant/, *.log, kubeconfig
├── README.md
├── CLAUDE.md
├── p1/
│   ├── Vagrantfile
│   ├── scripts/            server.sh, worker.sh
│   └── confs/              (kept, may stay near-empty for p1)
├── p2/
│   ├── Vagrantfile
│   ├── scripts/            server.sh, deploy.sh
│   └── confs/              apps.yaml, ingress.yaml
├── p3/
│   ├── scripts/            install.sh, create_cluster.sh, reset.sh
│   └── confs/              application.yaml
└── bonus/
    ├── scripts/            install.sh, seed_gitlab.sh
    └── confs/              gitlab.yaml, application.yaml
```

Two notes grounded in the subject:

- **`p3/` has no Vagrantfile.** The p17 tree lists `./p3/scripts` and `./p3/confs` and no Vagrantfile, matching p12: *"without Vagrant this time"*.
- **The p17 tree does show `./bonus/Vagrantfile`.** It is an *example* tree, and the bonus text (p16) mandates only the folder name. Our bonus runs inside the k3d cluster, so we will not ship a Vagrantfile there — and we will be able to say why.
- **`scripts/` and `confs/` are mandated** by the p17 yellow box: *"Any scripts you need will be added in a scripts folder. The configuration files will be in a confs folder."*

**Second repository (p3 only):** a *separate*, **public** GitHub repo whose name contains `smbarki` — e.g. `smbarki-iot-gitops`. p12 blue box: *"The only mandatory requirement is to put the login of a member of the group in the name of your repository."* It holds `manifests/{deployment,service,ingress}.yaml` and nothing else. Argo CD watches it. The graded repo must **not** contain a copy of those manifests, or the evaluator cannot tell which one is live.

---

## 5. Phase 0 — the foundation (do this before any part)

Owned jointly; it is the only work that happens before the split.

1. **`git init`**, first commit with `.gitignore`, `README.md`, the folder skeleton, and `CLAUDE.md`. Push to the graded remote.
   *Why:* p17 — "Only the work inside your repository will be evaluated."

2. **Build the outer VM.** Subject p4 requires the whole project to run in a VM; this host is bare metal.
   - QEMU/KVM via virt-manager, Debian 13, **8 GB RAM / 6 vCPU / 80 GB disk**, `cpu mode=host-passthrough` so `/dev/kvm` exists inside (nested virt is already enabled on this box: `kvm_intel nested=Y`).
   - Everything else — Vagrant, libvirt, Docker, k3d — is installed *inside* it.
   - **Decision gate:** if `/dev/kvm` is absent inside the outer VM, or `vagrant up` takes >10 min, fall back to developing on bare metal and revisit. Record which we chose; the evaluator may ask.
   - **RAM reality:** the desktop currently eats ~6.5 GB of 15 GB. For the bonus the outer VM wants 10 GB — close Firefox/VS Code/Discord/Steam first, or shrink the desktop session.

3. **Install the toolchain inside the outer VM** (also the seed of `p3/scripts/install.sh`):
   - Vagrant 2.4.9 from the HashiCorp apt repo — **Ubuntu/Debian have no `vagrant` package**, so `apt install vagrant` fails. This bites on the evaluator's machine too.
   - `vagrant plugin install vagrant-libvirt` + `qemu-system-x86` (note: `qemu-kvm` does not exist on noble).
   - Docker Engine from the official repo, plus k3d and kubectl (p3 needs these; see §10).

4. **Agree the ground rules in §2** and write them into `CLAUDE.md`.

**Gate:** `vagrant --version` ≥ 2.4.9, `virsh list` works, `docker run hello-world` works, all inside the outer VM.

---

## 6. Part 1 — two VMs, K3s server + agent  *(yours)*

### Goal
`cd p1 && vagrant up` produces two Debian 13 VMs, `smbarkiS` (192.168.56.110, K3s controller) and `smbarkiSW` (192.168.56.111, K3s agent), joined into one cluster, both SSH-able without a password.

### What the subject actually demands (p6–p8)
- 2 machines, run **using Vagrant**, latest stable distro, **1 CPU / 512 MB (or 1024)**.
- Machine names = a team login; hostnames `<login>S` and `<login>SW`.
- **"A dedicated IP on the primary network interface"** — 192.168.56.110 / .111.
- SSH on both with **no password**.
- Red box: *"You will set up your Vagrantfile according to modern practices."*
- K3s **controller mode** on machine 1, **agent mode** on machine 2.
- Yellow box: *"You will have to use kubectl (and therefore install it as well)."*
- p8's two screenshots define pass/fail: the broken one has a **wrong node IP**; the correct one shows **both nodes Ready with 192.168.56.110/.111**.

### Micro-steps

| # | Slice | Proof it works |
|---|---|---|
| 1.1 | Vagrantfile: one machine, box + hostname only | `vagrant up`, `vagrant ssh smbarkiS -c hostname` → `smbarkiS` |
| 1.2 | Add `private_network` static IP + provider block (name, 1024 MB, 1 cpu) | `ip -4 a` shows 192.168.56.110 on the 2nd NIC; `virsh list` shows the domain name |
| 1.3 | Add the second machine (512 MB) | `vagrant status` → both running; `ping 192.168.56.111` from the host |
| 1.4 | `scripts/server.sh` installs K3s in **server** mode with `--node-ip` | `kubectl get nodes -o wide` → 1 node Ready, INTERNAL-IP **192.168.56.110** |
| 1.5 | `scripts/worker.sh` installs K3s in **agent** mode and joins | `kubectl get nodes -o wide` → 2 nodes Ready, correct IPs, ROLES `control-plane` / `<none>` (K3s v1.36 no longer applies the legacy master label) |
| 1.6 | kubeconfig readable by `vagrant`; `/etc/profile.d/k3s.sh` | `vagrant ssh smbarkiS -c "kubectl get nodes"` — no sudo, no flags |
| 1.7 | Full destroy/up clean run | Zero manual steps, 2 nodes Ready at the end |

### Key decisions and why

**Token handoff — pre-seed a fixed token instead of copying the generated one.**
The server writes its token to `/var/lib/rancher/k3s/server/node-token`, and every tutorial tells you to copy it through the `/vagrant` synced folder. We will not, for three reasons: `/vagrant` *is* the git repo, so we would be committing a live cluster credential; a `vagrant destroy && vagrant up` leaves a **stale** token behind and the agent then fails with `token CA hash does not match` and never joins; and under libvirt the synced folder is one-way rsync, so a guest-written file never reaches the host anyway. Instead we define the token once in the Vagrantfile and pass it to *both* provisioners via `env:`. The defense answer is strong: *"I inverted the dependency — instead of the agent reading a token the server generated, I told the server which token to use."*

**`--node-ip` is the flag that matters; most of the others are cargo-cult.**
Vagrant forces NIC 1 to be NAT (that is how `vagrant ssh` port-forwards), and every VM gets the identical `10.0.2.15`. K3s, like kubelet, picks the source address of the default route → both nodes register as `10.0.2.15`. The agent still *joins*, so `get nodes` says Ready and the failure stays hidden until p2's traffic test. `--node-ip` fixes it. `--flannel-iface` is cheap belt-and-braces. **`--advertise-address` already defaults to `--node-ip`** — pure noise. **`--bind-address=192.168.56.110` is actively harmful**: the apiserver stops listening on loopback while the generated kubeconfig still points at `127.0.0.1:6443`, so your own `kubectl` breaks.

**Detect the interface at runtime, never hardcode it.** `IFACE=$(ip -o -4 addr show | awk -v ip="$NODE_IP" '$4 ~ "^"ip"/" {print $2; exit}')`. It is `eth1` on bento boxes (they force `net.ifnames=0`) but `enp1s0`/`enp2s0` under libvirt virtio. The subject's own p8 info box warns about exactly this.

**kubectl needs no separate install.** The K3s installer symlinks `/usr/local/bin/kubectl → k3s`. That *is* the yellow box satisfied, and `ls -l /usr/local/bin/kubectl` is the one-command proof. Installing kubectl from the Kubernetes apt repo adds an external repo and invites version skew.

**RAM: server 1024 MB, worker 512 MB.** K3s's own stated server minimum is 2 GB; the subject explicitly allows 1024. A 512 MB server running apiserver + sqlite + coredns + Traefik + metrics-server OOM-loops the moment p2 puts load on it.

**Provisioning lives in `scripts/*.sh`, not inline heredocs.** The subject's own p7 skeleton shows `vm.provision "shell", path: REDACTED`, and p17 mandates a `scripts/` folder.

### Do NOT

| Don't | Why | What you'd see at defense |
|---|---|---|
| Use `debian/trixie64` with the **VirtualBox** provider | That box publishes libvirt artifacts only | `vagrant up` → *"the box doesn't support the provider you requested"* |
| Commit `.vagrant/` | Contains per-machine SSH **private keys** | Leaked key; fresh clones can't `vagrant up` |
| Copy the node-token into `/vagrant` and commit it | Stale token survives destroy; CA hash mismatch | Worker never joins; only fixable by hand-deleting the file |
| Set `--node-name=smbarkiS` | Kubernetes lowercases node names and rejects uppercase RFC-1123 | k3s refuses to start outright |
| Panic that `kubectl get nodes` shows `smbarkis` | Same lowercasing — the **hostname stays `smbarkiS`**, the node object is lowercase | Rehearse this explanation; it is not a bug |
| `update-alternatives --set iptables iptables-legacy` | Debian-10-era advice; Debian 13 ships iptables 1.8.11, outside K3s's broken 1.8.0–1.8.4 band | Evaluator asks "why?" and you have no answer |
| `swapoff -a` | K3s hardcodes `FailSwapOn: false` | Pointless line you must defend |
| Set `config.ssh.insert_key = false` or add your own keys | Vagrant already generates a per-machine keypair on first boot — that **is** the passwordless-SSH requirement | A security regression that reimplements what already worked |

### Gate for p1
`vagrant destroy -f && vagrant up` from clean → `kubectl get nodes -o wide` shows two `Ready` nodes at 192.168.56.110 and .111, same version, roles `control-plane` and `<none>`. Both `vagrant ssh` targets work with no password. Then commit.

---

## 7. Part 2 — one VM, three apps, host-based Ingress  *(yours)*

### Goal
From the **host** browser: `192.168.56.110` with `Host: app1.com` → app1, `app2.com` → app2, anything else → app3. app2 runs 3 replicas.

### What the subject demands (p9–p11)
- **One** VM, latest stable distro, K3s **server mode**, named `smbarkiS`, at 192.168.56.110.
- 3 web applications **of your choice**.
- *"When a client inputs the IP address 192.168.56.110 in their web browser with the HOST app1.com, the server must display app1… Otherwise, app3 will be selected by default."*
- Blue box: *"application number 2 has 3 replicas."*
- Red box: *"The Ingress is not displayed here on purpose. You will have to show it to your evaluators during your defense."*
- p11's screenshot is load-bearing: `kubectl get all` with **no `-n` flag** → the apps live in the **`default` namespace**; Services are **ClusterIP on port 80**; deployments are named `app-one`, `app-two` (3/3), `app-three`.

### Micro-steps

| # | Slice | Proof |
|---|---|---|
| 2.1 | Copy p1's Vagrantfile down to one machine | `vagrant up`; `kubectl get nodes` → 1 node Ready at .110 |
| 2.2 | Deploy app1 only (Deployment + ClusterIP Service) | `kubectl get pods` → 1/1; `curl` from inside the VM to the ClusterIP |
| 2.3 | Add the Ingress with the `app1.com` rule | `curl -H "Host: app1.com" http://192.168.56.110` **from the host** → app1 |
| 2.4 | Add app2 with `replicas: 3` + rule | `kubectl get deploy` → `app-two 3/3`; curl loop shows 3 distinct pod names |
| 2.5 | Add app3 as `spec.defaultBackend` | `curl http://192.168.56.110` (no Host) → app3 |
| 2.6 | Move all manifests to `confs/`, apply from the provisioning script | Clean `destroy && up` reproduces all of it |

### Key decisions and why

**Use `spec.defaultBackend` for app3, not a host-less rule.** Both appear to work. A rule with no `host:` becomes a Traefik router with rule `PathPrefix(/)`, and Traefik v3 orders routers **by rule-string length** — `Host(\`app1.com\`) && PathPrefix(/)` is longer, so it wins. That is a string-length *accident*, not a guarantee. `spec.defaultBackend` is compiled to priority `math.MinInt32` in Traefik's source and **cannot** be outranked by anything. The subject's word is "default"; use the mechanism that actually means default.

**One Ingress object, not three.** Traefik's `default-router`/`default-backend` are global singleton keys — a second Ingress declaring `defaultBackend` is silently dropped with *"The default backend already exists."* One object also means `kubectl describe ingress` renders the whole routing table on one screen for the evaluator, which is exactly what the red box asks us to show.

**Never add `traefik.ingress.kubernetes.io/router.priority` to that object.** It applies to *every* router the Ingress produces, including `default-router`, destroying the MinInt32 guarantee — app3 would then swallow app1.com and app2.com. (Traefik's own docs still carry an obsolete note suggesting this; the source disagrees.)

**`traefik/whoami:v1.12.0` for all three apps.** One 5 MB pull on a small VM; `WHOAMI_NAME=app1` gives identity; and crucially **every response carries `Hostname: app-two-xxxxx-yyyyy`** (line 2 when WHOAMI_NAME is set), so `for i in $(seq 9); do curl -s -H "Host: app2.com" 192.168.56.110 | grep "^Hostname:"; done | sort | uniq -c` *proves* the 3 replicas are load-balancing. `paulbouwer/hello-kubernetes` is what the p11 screenshot uses, but it is amd64-only and untouched since 2021 — keep it as the second choice if an evaluator insists on matching the screenshot exactly.

**Set `ingressClassName: traefik`.** K3s's bundled Traefik registers itself as the default IngressClass, so a class-less Ingress still works — but naming it costs nothing, survives a missing default annotation, and is a talking point. Never use the deprecated `kubernetes.io/ingress.class` annotation.

**Nothing extra is needed to reach port 80 from the host.** Traefik's Service is `LoadBalancer`; K3s's ServiceLB (klipper) runs a DaemonSet that takes **hostPort 80/443** on the node, binding `0.0.0.0:80`. With the host-only NIC at .110, `curl http://192.168.56.110` from the host lands in Traefik. Corollary: nothing else may claim 80/443.

**Apply manifests with `kubectl apply -f /vagrant/confs/` from the provisioning script**, not by dropping them into K3s's auto-deploy directory. Auto-deploy works, but it makes the objects addon-owned so `kubectl delete` silently reverts them — confusing to demo and to explain. The explicit apply is visible, matches the `confs/` requirement, and re-runs cleanly on `vagrant provision`.

### Do NOT

| Don't | Why |
|---|---|
| Install nginx-ingress or any second controller | K3s already ships Traefik; two controllers fight over :80 |
| Answer with NodePort | The subject describes an **Ingress**, and the red box demands you show it |
| Use `IngressRoute` (Traefik CRD) | Vendor lock-in for zero gain; plain `networking.k8s.io/v1` is sufficient and portable |
| Edit `/etc/hosts` inside the VM | The test is from the **host**; the Host header is set by curl/browser, not by DNS |
| Put the apps in a custom namespace | p11's `kubectl get all` has no `-n` → `default` is what the evaluator will type |
| Try a wildcard `host: "*"` | The Ingress API only allows a single-label prefix wildcard (`*.foo.com`); "any host" is not expressible |
| Hardcode pod IPs anywhere | They change on every restart, including during your own demo |

### Gate for p2
Clean `destroy && up`, then from the **host**: three curls returning three different apps, `kubectl get deploy` showing `app-two 3/3`, the replica-proof loop showing 3 distinct pod names, and `kubectl describe ingress` displayed and explained.

---

## 8. Part 3 — K3d + Argo CD  *(Person 3)*

### Goal
A script installs everything from nothing; a k3d cluster runs Argo CD in ns `argocd` and Wil's app in ns `dev`; `curl http://localhost:8888/` returns `v1`; changing the tag in a public GitHub repo and pushing makes Argo CD roll it to `v2` on its own.

### What the subject demands (p12–p15)
- **No Vagrant.** K3d installed on the VM.
- Yellow box: *"you must write a script to install all the necessary packages and tools **during your defense**"* — so it runs live, on a clean machine.
- *"First of all, you must understand the difference between K3s and K3d"* — an oral question, guaranteed.
- **Two namespaces**: one for Argo CD (`argocd` in p13's screenshot), one named **`dev`** holding the app.
- The app is *"automatically deployed by Argo CD using your online GitHub repository"*, which must be **public** and contain `smbarki` in its name.
- Two tagged versions; *"You must be able to change the version from your public GitHub repository, then check that the application has been correctly updated."*
- p14/p15: `curl http://localhost:8888/` → `{"status":"ok", "message": "v1"}` then `"v2"`.

### Micro-steps

| # | Slice | Proof |
|---|---|---|
| 3.1 | `install.sh`: Docker, k3d, kubectl, argocd CLI | Each binary reports its version; `docker run hello-world` |
| 3.2 | `k3d cluster create` **with the port map** | `kubectl get nodes` Ready; `curl localhost:8888` → 404 from Traefik (proves the path is wired) |
| 3.3 | Namespaces `argocd` + `dev` | `kubectl get ns` matches p13's screenshot |
| 3.4 | Argo CD installed, UI reachable | 7 pods Running; login with the initial admin password |
| 3.5 | Public repo `smbarki-iot-gitops` with `manifests/` | Loads in a private browser window (proves public) |
| 3.6 | Apply the `Application` CR | `argocd app get` → Synced + Healthy; `curl localhost:8888` → `v1` |
| 3.7 | Push v2, watch Argo CD do it | `curl localhost:8888` → `v2`, with nobody touching the cluster |

### Key decisions and why

**Put `-p "8888:80@loadbalancer"` in the create command and route through an Ingress.** Port maps **cannot be added to an existing k3d cluster** — `--port-add` exists but is flagged EXPERIMENTAL and recreates the load-balancer container. Forgetting it means `k3d cluster delete && create` and a full re-sync in front of the evaluator.

**Do not use `kubectl port-forward` as the graded path.** It dies exactly when the pod is replaced — which is precisely the v1→v2 moment. `curl: (52) Empty reply` at the climax of the demo. Port-forward is fine for the Argo CD UI, which is not graded.

**Shorten Argo CD's reconciliation interval in the install script.** The default is 120 s + up to 60 s jitter ≈ 3 minutes of standing in silence. Patch `argocd-cm` to `timeout.reconciliation: 20s`. It is a legitimate configuration choice and it makes the demo land.

**`syncPolicy.automated` with `prune` and `selfHeal`.** `selfHeal` is worth demonstrating deliberately: if the evaluator runs `kubectl set image ... :v2`, Argo CD snaps it back to `v1` within seconds — which *proves* Git is the source of truth. `allowEmpty: false` guards against a mis-pushed commit that empties the manifest set.

**Pre-create `dev` **and** set `CreateNamespace=true`.** p13's screenshot shows both namespaces `Active`; that must be true even if the first sync is still in flight. But **never put a `Namespace` object in the watched repo** with `prune: true` — a bad commit would delete the namespace and everything in it.

**Two repos, and the manifests live only in the public one.** If a copy of `deployment.yaml` also sits in `p3/confs/`, the evaluator will ask which one is live and it will look like it was applied by hand. `p3/confs/` holds the `Application` CR and nothing else.

### Do NOT

| Don't | Why |
|---|---|
| `kubectl set image` / `argocd app set` for the demo | p13 says the change must come **from the GitHub repository**; that is the whole point of the exercise |
| Use a private repo, or a name without `smbarki` | Both are explicit, checkable requirements (p12) |
| Create the cluster without the `-p` map | Unfixable without deleting the cluster mid-defense |
| Delete `argocd-initial-admin-secret` before defense | It's the only copy of the password; recovery means patching a bcrypt hash |
| Reference `wil42/playground:latest` | Only `v1` and `v2` exist — `ErrImagePull: manifest ... not found` |
| Point `path:` at a single file or the repo root | Argo CD globs `*.yaml`; a root `README.md` gives noisy or empty manifest sets |
| Leave NordVPN connected | Its kill-switch iptables rules pre-empt Docker's chains; image pulls hang |
| Assume anything is preinstalled | The script runs live on a clean machine — that is the graded artifact |

### Gate for p3
On a machine with nothing installed: `bash p3/scripts/install.sh && bash p3/scripts/create_cluster.sh`, then the full v1→v2 loop, twice.

---

## 9. Bonus — local GitLab  *(gated)*

### Entry condition
**Do not start until p1, p2 and p3 are each green on a clean run and rehearsed end-to-end, with ≥3 days of margin.** p16's red box: *"The bonus part will only be assessed if the mandatory part is flawless… If you have not passed ALL the mandatory requirements, your bonus part will not be evaluated at all."* Time spent here before that point has an expected value of zero.

### The 2026 landmine
Every tutorial and every previous 42 repo about this bonus is now **wrong**. GitLab chart **10.0 removed the bundled PostgreSQL, Redis and MinIO**, requires PostgreSQL **17**, and replaced nginx-ingress with Gateway API + Envoy Gateway (whose CRDs you must install yourself). "Use the latest chart" therefore means also standing up an external database, cache, object store and ingress stack — 14–20 hours of yak-shaving on a machine that does not have the RAM for it (the chart's own docs say **8 vCPU / 30 GB**).

### The approach
Deploy **`gitlab/gitlab-ce:19.2.1-ce.0`** — the *same* official 19.2.1 artifact — as a single pod + PVC + Service + Ingress in namespace `gitlab`, inside the existing k3d cluster. It self-contains PostgreSQL, Redis, Gitaly and Workhorse, so chart 10's external-dependency wall disappears. ~2.5–3.5 GB instead of 6–8 GB, ~6–8 hours instead of two to three days. It satisfies every literal word of p16: latest version, from GitLab, running locally, in namespace `gitlab`. Ship it as a tiny local Helm chart so `helm` still features in the story ("helm could be useful here" — p16, not a requirement).

### The one trap that actually matters
Argo CD's `repo-server` resolves `repoURL` through **CoreDNS**, which knows nothing about your `/etc/hosts`, `nip.io` or `192.168.56.x`. Meanwhile GitLab's `external_url` decides every redirect it emits. If the inside and outside URLs differ, either Argo CD cannot clone or your browser gets redirected to an unresolvable host. **Fix: one canonical URL valid on both sides** — use the in-cluster Service DNS name `gitlab.gitlab.svc.cluster.local` on port 80 as `external_url`, add `127.0.0.1 gitlab.gitlab.svc.cluster.local` to the host's `/etc/hosts`, and map `-p "80:80@loadbalancer"` at cluster-create time.

Also: bind the storage out of the node container (`-v "$HOME/.iot-storage:/var/lib/rancher/k3s/storage@all"`), or `k3d cluster delete` destroys the GitLab project and you redo the whole seeding step live.

### Abort criteria
Drop the bonus if any of these is true: mandatory isn't 100 % green with margin; the VM can't get **≥8 GB RAM / 4 vCPU**; GitLab hasn't reached Ready within 15 minutes on two clean attempts; you're >4 h into the DNS/`external_url` problem; **anything under `p3/` had to change**; or <48 h remain and the loop hasn't been rehearsed twice against local GitLab.

### Do NOT
Touch `p1/`, `p2/` or `p3/` — the bonus must be purely additive, and p3 alone must still pass. Do not fall back to chart 9.11.x to get the bundled dependencies back (it is not the latest, and p16 asks for the latest in a red box — the evaluator can check `helm list` against the version-mapping page in ten seconds). Do not install a second ingress controller. Do not commit real tokens.

---

## 10. CLAUDE.md changes

The existing `CLAUDE.md` is structurally right but several facts need correcting, and the working method needs adding.

**Corrections:**
- Token handoff → pre-seeded fixed token, not `/vagrant` copy (§6).
- VM RAM → server 1024 MB, worker 512 MB, with the reason.
- kubectl → already symlinked by the K3s installer; drop the "install it separately" implication.
- Add the **node-name lowercasing** fact (`smbarkiS` hostname → `smbarkis` node) — it looks like a bug mid-defense and isn't.
- p2 default backend → `spec.defaultBackend`, single Ingress, and the priority-annotation warning.
- p2 namespace → `default` (from p11's screenshot).
- Provider → libvirt primary, with p4's blue box quoted as the authority.
- Add the pinned version table from §1.
- Bonus → `gitlab/gitlab-ce` container, not the Helm chart, with the chart-10 reason.

**Additions:**
- The §2 ground rules: scope guard, micro-step protocol, the four-point gate, merge discipline.
- The work-split table so any session knows which folders it may touch.
- A "questions the evaluator will ask" list (K3s vs K3d, why this default-backend, how does the worker get the token, why 3 replicas are provably load-balancing).

---

## 11. Skills to create

Project skills live at `.claude/skills/<name>/SKILL.md` (verified for Claude Code v2.1.220; the directory name *is* the command name). **`.claude/skills/` does not exist yet, so Claude Code must be restarted after the first one is created.**

| Skill | What it does | Why we need it |
|---|---|---|
| **`iot-verify`** | Takes `p1`\|`p2`\|`p3`\|`bonus`, runs that part's evaluator commands, prints PASS/FAIL per requirement | Turns "I think it works" into evidence. Used at every gate |
| **`iot-clean-run`** | Destroys everything for a part and rebuilds from zero, then calls `iot-verify` | The reproducibility gate from §2.3. This is the single check that catches most defense failures |
| **`iot-explain`** | Given a file or a flag, explains what it does, which subject requirement it serves, and what breaks without it | Your rule 3 and 4 — understanding before moving on. Also the anti-cargo-cult tool |
| **`iot-defense`** | Mock defense: picks requirements at random, demands live proof, asks the oral questions | The subject is graded by humans asking questions. Rehearse it |

Optionally a read-only `iot-verifier` subagent (`tools: Read, Glob, Grep, Bash`) so verification can run without any risk of the agent "fixing" things.

---

## 12. Verification — the end-to-end rehearsal

Before defense, on a machine reset to nothing, in one sitting:

```bash
# p1
cd p1 && vagrant destroy -f && vagrant up
vagrant ssh smbarkiS -c "kubectl get nodes -o wide"     # 2 Ready, .110 / .111
vagrant destroy -f

# p2
cd ../p2 && vagrant up
curl -H "Host: app1.com" http://192.168.56.110          # app1
curl -H "Host: app2.com" http://192.168.56.110          # app2
curl http://192.168.56.110                              # app3
for i in $(seq 9); do curl -s -H "Host: app2.com" http://192.168.56.110 | grep "^Hostname:"; done | sort | uniq -c
vagrant ssh smbarkiS -c "kubectl describe ingress"      # show it — p11 red box
vagrant destroy -f

# p3
cd ../p3 && bash scripts/install.sh && bash scripts/create_cluster.sh
kubectl get ns                                          # argocd + dev
curl -s http://localhost:8888/                          # {"status":"ok", "message": "v1"}
# edit the tag in the public repo, commit, push, touch nothing else
curl -s http://localhost:8888/                          # {"status":"ok", "message": "v2"}
argocd app get wil-playground                           # Synced, Healthy, automated
```

Every one of those commands is one an evaluator will type. If any needs a manual fix-up, that part is not done.

---

## 13. Open risks

| Risk | Mitigation |
|---|---|
| **Nested virtualisation** — VirtualBox-in-KVM is unreliable on this CPU | Use libvirt inside the outer VM (nested KVM is solid); p4's blue box permits any provider. Phase-0 gate decides |
| **RAM** — desktop uses 6.5 of 15 GB; the bonus wants 8–10 GB for the outer VM | Never run p1/p2 VMs and the p3 stack at once. Close snaps before the bonus |
| **Version drift** — GitLab 19.3 lands ~2026-08-20; K3s/Argo CD move monthly | Pin everything (§1). Re-verify pins the day before defense |
| **NordVPN** blackholing `192.168.56.x` and Docker networking | Disconnect, or `nordvpn set lan-discovery enable`, before any demo |
| **`wil42/playground` is amd64-only** | Fine on this x86_64 machine; would `CrashLoopBackOff` on an Apple-Silicon evaluator machine. Evaluation is on our machine (p17), so this is contained |

---

## 14. Immediate next actions

1. `git init` + skeleton + `.gitignore` + first push (§5.1).
2. Rewrite `CLAUDE.md` with the §10 corrections and ground rules.
3. Create the four skills in §11, then restart Claude Code.
4. Build and gate the outer VM (§5.2–5.3).
5. Start p1 slice 1.1 — one machine, box and hostname only.
