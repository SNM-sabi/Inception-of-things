# DEFENSE RUNBOOK — how to present p1 and p2

Fifth page of the series. The others teach concepts; **this one is the script for the
day**: the order, the commands, what to say while things boot, the questions that are
coming, and what to do when something breaks. The evaluation happens on OUR machine
(subject p17), driven by you, with an evaluator watching and asking.

Time budget: p1 builds in ~3 min, p2 in ~10 min (cold image pulls). The build time is
not dead air — it is exactly when you walk the files. That's the whole trick of this
runbook: **something is always building while you are always explaining.**

---

## 0. Pre-flight — before the evaluator sits down

**⚠ EVERYTHING in this runbook runs INSIDE `iot-host` — never on the laptop.** The
laptop has no Vagrant, no virsh, no clusters, by design; it only hosts the outer VM.
The first command below is the one that changes machines. Check your prompt before
typing anything else:
`sabdark@sabdark-NKx0Kx` = laptop (wrong place) · `sabdark@iot-host` = inside (right place).
And the repo path differs: inside it is `~/Inception-of-things`, not `~/Desktop/1337/…`.

Run these yourself, alone, that morning:

```bash
ssh iot-host                                  # the outer VM is up (it autostarts)
cd Inception-of-things && git pull            # repo inside matches main
cd p1 && vagrant destroy -f; cd ../p2 && vagrant destroy -f
virsh list --all                              # MUST be empty — no stale domains
vagrant box list                              # debian/trixie64 cached (no download mid-demo)
free -h                                       # iot-host has its ~5 GB free
```

Also on the laptop: close heavy apps (the desktop eats RAM the VMs need), and have
`docs/` open in a browser tab — showing the evaluator organized docs never hurts.

**Arrive with everything DOWN.** The clean build from zero *is* the demo. A pre-booted
cluster invites "how do I know you didn't hand-fix this?" — a cold `vagrant up` answers
it before it's asked.

## 1. The opening — 60 seconds, before any command

Say this, roughly:

> "The whole project runs inside a virtual machine, as page 4 requires — this laptop
> hosts one big VM, `iot-host`, and everything you'll see runs inside it. Vagrant works
> there with the libvirt provider — page 4's blue box allows any provider. Part 1 is a
> two-node K3s cluster on two Vagrant VMs; Part 2 is one VM serving three apps behind
> one Ingress; Part 3 is K3d and Argo CD, no Vagrant. I'll build each part from zero in
> front of you."

Why this order of ideas: it plants the three subject citations for the outer VM
(p4 ×2, p12) before the evaluator can ask "why nested VMs?", and it sets the
expectation that builds happen live.

## 2. Part 1 — the script

### 2.1 Launch first, talk second

```bash
ssh iot-host
cd Inception-of-things/p1
vagrant destroy -f && vagrant up        # ~3 min — the talking window opens now
```

### 2.2 While it builds — walk the Vagrantfile (have it open in a second terminal)

Points to make, in order, each one sentence:

- **Shape**: "one `config.vm.box` at the top, one `define` block per machine — the
  structure page 7 of the subject itself shows."
- **Names**: "machine name, hostname and libvirt domain are all `smbarkiS` — login
  `smbarki` + S, as page 6 demands. Same with SW for the worker."
- **IPs**: "static `.110` and `.111` on a private network — the dedicated IPs from
  page 6. NIC 1 belongs to Vagrant — that's how `vagrant ssh` works on any provider —
  so the dedicated IP lives on the second interface, which is why page 8's info box
  points you at `enp0s8/enp0s9`, the *second and third* adapters."
- **Resources**: "1 CPU each; worker at the 512 minimum, server at the allowed 1024 —
  the parenthesis in '512 MB (or 1024)' is the permission. The server runs the whole
  control plane; 512 would OOM."
- **The token**: "pre-seeded: I tell both machines which token to use, instead of the
  worker fishing the generated one out of the server's filesystem. Copying it through
  `/vagrant` would drop a live credential into the git repo — `/vagrant` here is a live
  NFS mount of the project — and a stale copy survives destroy and breaks the next join.
  I inverted the dependency."
- **The scripts**: "provisioning lives in `scripts/`, as page 17's yellow box mandates.
  `server.sh`: detect the interface carrying `.110` at runtime — page 8 says never
  hardcode names — then install K3s pinned, server mode, `--node-ip`. `worker.sh`: same
  token, agent mode, and it *waits* for the server's API first, because this provider
  provisions machines in parallel."
- If asked about the `--disable` flags, or unprompted if there's time: "K3s bundles
  Traefik, a load balancer, metrics-server and a storage provisioner. Part 1 needs none
  of them — the subject asks for a bare cluster, and the bare minimum it advises applies
  to software too. Part 2 re-enables exactly what it uses."

### 2.3 The proofs (the build should be done by now)

```bash
vagrant ssh smbarkiS -c "kubectl get nodes -o wide"
```
Narrate the columns: **two Ready** · `smbarkis`/`smbarkisw` — "hostnames are `smbarkiS`,
capital S — node names are RFC-1123 DNS labels, so Kubernetes lowercases them; watch:" —
```bash
vagrant ssh smbarkiS -c "hostname"        # smbarkiS, capital S, on demand
```
· INTERNAL-IPs `.110`/`.111` — "that's `--node-ip`; without it they'd register with
Vagrant's DHCP plumbing" · ROLES `control-plane` and `<none>` — "the legacy `master`
label was removed upstream; current K3s applies only control-plane."

```bash
vagrant ssh smbarkiS -c "ls -l /usr/local/bin/kubectl"   # -> k3s: p6's yellow box, installed by the installer
vagrant ssh smbarkiSW -c "systemctl is-active k3s-agent" # agent mode, alive
ping -c1 192.168.56.110 && ping -c1 192.168.56.111       # reachable from the host
```

Passwordless SSH was proven by every command above; if they want it explicit:
`vagrant ssh smbarkiSW` → shell, no password, exit.

### 2.4 Close p1, open p2 — say the sentence before they find the trap

```bash
vagrant destroy -f          # in p1/
```
> "p1 and p2 both name their domain `smbarkiS` — matching the subject's provider-level
> naming — so they're mutually exclusive by design; I destroy one before booting the
> other."

## 3. Part 2 — the script

### 3.1 Launch, then use the long build

```bash
cd ../p2 && vagrant up      # ~10 min cold — say why up front:
```
> "This takes about ten minutes cold: the K3s binary and the container images are pulled
> fresh — nothing is pre-staged except the Vagrant box. The build is fully self-checking:
> it will refuse to finish unless all four routing cases already work."

### 3.2 While it builds — walk the three files

**`confs/apps.yaml`** — "three Deployments and three ClusterIP Services, in the default
namespace — page 11's `kubectl get all` has no `-n`, so that's where the evaluator's
command will look. One image for all three, `traefik/whoami` pinned: a tiny server that
answers with its own pod name — that's how I *prove* things instead of claiming them.
`replicas: 3` on app-two is the blue box on page 9, one line."

**`confs/ingress.yaml`** — the centerpiece, since p11's red box says the Ingress must be
shown and explained live:
- "Standard `networking.k8s.io/v1`, class `traefik` — the controller K3s ships; no
  second controller installed."
- "Two objects, and the split is Traefik's requirement, which I verified live: Traefik
  v3.7 **ignores** `defaultBackend` when the same Ingress also carries rules — I watched
  the API object show the default while the route 404'd. Rules in `apps`, the default
  alone in `apps-default`."
- "Why `defaultBackend` at all, instead of a rule with no host? A host-less rule only
  loses to `app1.com` by an accident of Traefik's rule-length sorting. `defaultBackend`
  compiles to a priority that cannot be outranked — it *means* 'when nothing else
  matches', which is the subject's own word: *otherwise… by default*."

**`scripts/server.sh`** — "same skeleton as p1's, three deliberate differences: no token
(no worker exists), Traefik and ServiceLB stay on (they *are* the routing), and success
is defined as the router serving — the script curls all four cases itself before it
exits."

If time remains: the request chain — "curl hits `.110:80`; ServiceLB holds that hostPort
for Traefik's LoadBalancer Service; Traefik reads the Host header and consults the
Ingress; the Service load-balances to a pod."

### 3.3 The proofs

All from the iot-host shell — "**the host** in the subject's sense is this VM; the
`192.168.56` network exists only inside it":

```bash
curl -H "Host: app1.com" http://192.168.56.110        # Name: app1
curl -H "Host: app2.com" http://192.168.56.110        # Name: app2
curl http://192.168.56.110                            # Name: app3  ← "otherwise"
curl -H "Host: whatever.xyz" http://192.168.56.110    # Name: app3  ← still "otherwise"

# the replica proof — 9 requests, count the pod names:
for i in $(seq 9); do curl -s -H "Host: app2.com" http://192.168.56.110 | grep "^Hostname:"; done | sort | uniq -c
#   3 Hostname: app-two-...a   ← three names, three hits each:
#   3 Hostname: app-two-...b      round-robin, demonstrated
#   3 Hostname: app-two-...c
```

Then the red-box moment — show and narrate:

```bash
vagrant ssh smbarkiS -c "kubectl get all"              # the exact p11 screenshot shape
vagrant ssh smbarkiS -c "kubectl describe ingress"     # both objects, one screen:
```
> "Two rules — app1.com and app2.com, each to its Service; app2's Service fronts three
> endpoints, which you just saw rotate. And the separate default object sends everything
> else to app-three."

## 3b. Self-test p2 — the drill you run alone, step by step

Everything the evaluator will do, done by yourself first. All inside iot-host.

**Step 0 — position.** `ssh iot-host && cd Inception-of-things/p2`

**Step 1 — alive?** `vagrant status` → `smbarkiS running`. If `not created`:
`vagrant up` (6–10 min, self-checking) is the only repair p2 ever needs.

**Step 2 — look inside.** `vagrant ssh smbarkiS -c "kubectl get all"` →
5 pods Running (1 + **3** + 1), `app-two 3/3`, three ClusterIP services on port 80,
no `-n` typed — this is p11's screenshot, live.

**Step 3 — the four routing cases** (run on iot-host directly — "the host" is where
the client stands):

```bash
curl -H "Host: app1.com" http://192.168.56.110     # → Name: app1
curl -H "Host: app2.com" http://192.168.56.110     # → Name: app2
curl http://192.168.56.110                          # → Name: app3
curl -H "Host: banana.whatever" http://192.168.56.110   # → Name: app3
```

**Step 4 — replicas share the work.**

```bash
for i in $(seq 9); do curl -s -H "Host: app2.com" http://192.168.56.110 | grep "^Hostname:"; done | sort | uniq -c
```
→ three different pod names, **3 each**. One name ×9 = broken.

**Step 5 — show the Ingress** (the p11 red-box screen): `kubectl get ingress` (two
objects, both at `.110`) then `kubectl describe ingress` — practice narrating it once.

**Step 6 — the ultimate test.** `vagrant destroy -f && time vagrant up` → ends with
four `routing OK` lines and zero manual steps. Then repeat steps 2–5 on the fresh
machine.

**Reading failures:**

| You see | It means | First move |
|---|---|---|
| `404 page not found` | Doorman alive, no route for that name | Wait 30 s, retry; then `kubectl get ingress` + Traefik logs |
| Refused / timeout | The door itself is closed | `vagrant status`, then `kubectl get pods -n kube-system` |
| One pod name ×9 in step 4 | Replicas not balancing | `kubectl get endpoints app-two` — three addresses? |
| Unexplainable after 2 min | Don't surgery a sick machine | `vagrant destroy -f && vagrant up` — the self-checking rebuild IS the repair |

The chain, always: **curl → Traefik's logs → kubectl → rebuild if in doubt.**

## 4. The question bank — answers you already own

| Question | The answer (one breath) |
|---|---|
| Why is everything inside a VM? | p4: "the whole project has to be done in a virtual machine" — plus p4's blue box says "host virtual machine", and p12 says install K3d "on your virtual machine" with no Vagrant in sight. Three citations, one outer VM. |
| Why libvirt and not VirtualBox? | The subject allows any provider (p4 blue box). Technically: VirtualBox can't nest reliably inside KVM, and its kernel modules don't build on new kernels. |
| K3s vs K3d? | K3s is a lightweight Kubernetes distribution — one binary, runs on the machine. K3d runs *K3s inside Docker containers* — each "node" is a container. p1/p2 use K3s in VMs; p3 uses K3d, so no Vagrant. |
| How does the worker get the token? | It doesn't "get" it — both machines are *given* the same pre-seeded token by the Vagrantfile. No credential copied, nothing in the repo, nothing stale after destroy. |
| Why does `get nodes` show lowercase? | Node names are RFC-1123 DNS labels; uppercase is forbidden, so K3s lowercases the hostname. The hostname itself is `smbarkiS` — `hostname` proves it. |
| Why no `master` in ROLES? | Removed upstream; modern K3s applies only `control-plane`. Same node, the alias is gone. |
| "Dedicated IP on the *primary* interface"? | Vagrant owns NIC 1 on every provider — the subject's own p8 info box points at enp0s8/enp0s9, the *second and third* adapters. Primary = the interface the cluster uses, and `--node-ip` makes that explicit. |
| Where's Traefik in p1? / Why so few pods? | Disabled deliberately: p1 needs no ingress, LB, metrics or storage; "bare minimum" applied to software. p2 re-enables what it uses. |
| Why two Ingress objects? | Traefik v3.7 ignores `defaultBackend` when rules coexist in the object — verified live. Rules in one, default in the other; only one may declare a default. |
| Prove the replicas load-balance. | The 9-curl loop: three pod names, three hits each. |
| What listens on port 80? | K3s's ServiceLB, holding the hostPort for Traefik's LoadBalancer Service. Nothing else may claim 80/443. |
| Why 1024 MB and is it enough? | The subject's "(or 1024)". p2 idles at ~86 MB free with the full stack — thin but stable: nothing further ever loads this machine. |
| Why does memory show 990/475 MB, not 1024/512? | The kernel reserves a slice for itself; MemTotal is what remains. Correct values. |

## 5. If something breaks — the emergency card

Rule one: **narrate, don't panic.** You have diagnosed worse than anything likely to
happen (ask them to read `docs/p1.html` §6 later). Rule two: never hand-fix state and
pretend — rebuild instead; three to ten minutes is affordable, a caught lie is not.

| Symptom | Move |
|---|---|
| `vagrant up` says domain already exists | `virsh list --all`; `vagrant destroy -f` in the *other* part's folder (or `virsh destroy <name> && virsh undefine <name>`) |
| Vagrant complains another process holds the lock | `pgrep -af ruby` → kill the stale PID → retry |
| A curl times out | Check the server first, not the network: `vagrant ssh smbarkiS -c "uptime; free -m"` — you know what thrash looks like |
| Agent loops "waiting to retrieve agent configuration" | Same move: server health first. That exact symptom was our p1 crisis. |
| Traefik 404 on a host that should route | `kubectl get ingress` — if the objects are there, give Traefik ~5 s; if still wrong, `kubectl describe ingress` and read it aloud — the diagnosis *is* a demonstration of competence |
| Something unrecoverable mid-demo | Say so, `vagrant destroy -f && vagrant up`, and keep talking through the files while it rebuilds — the build time is presentation time by design |

## 6. What NOT to do

- Don't type commands you haven't rehearsed. The whole checklist above is in
  `iot-verify`; nothing outside it is needed.
- Don't `kubectl edit`/`set image`/hand-patch anything live. Git is the truth; rebuilds
  are cheap.
- Don't guess at a question. "Let me show you" + a command beats an improvised theory —
  and every answer in §4 has a command behind it.
- Don't start the bonus conversation. The bonus is evaluated only if the mandatory part
  is flawless (p16 red box) — let the mandatory part finish flawlessly first.

## 7. Rehearsal checklist (do this at least once before the real thing)

- [ ] Full run of §2 + §3 solo, out loud, with a timer — target under 25 min including talk
- [ ] `/iot-defense p1` and `/iot-defense p2` — the mock evaluator drill
- [ ] Every §4 answer spoken from memory, not read
- [ ] Once with sabotage: have someone pre-create a stale domain, then start — the §5 card should feel boring
- [ ] The day before: re-check version pins (K3s stable channel, Argo CD) — the pins move
