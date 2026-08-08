# Inception-of-Things

42 School system-administration project (subject v4.0). Three progressively larger Kubernetes labs, plus a bonus.

| Folder | What it is | How to run it |
|---|---|---|
| `p1/` | Two Vagrant VMs: K3s server + K3s agent | `cd p1 && vagrant up` |
| `p2/` | One Vagrant VM: K3s + 3 apps behind one host-routing Ingress | `cd p2 && vagrant up` |
| `p3/` | K3d + Argo CD GitOps, no Vagrant | `bash p3/scripts/install.sh && bash p3/scripts/create_cluster.sh` |
| `bonus/` | Self-hosted GitLab wired into the p3 cluster | `bash bonus/scripts/install.sh` |

- **[docs/](docs/)** — the learning series, one friendly page per step (each has a Markdown source and an HTML version to open in a browser):
  - **`docs/index.html`** ([EXPLANATION.md](docs/EXPLANATION.md)) — step one from zero: VMs, Vagrant, boxes, SSH, p1 slice 1.1.
  - **`docs/phase0.html`** ([PHASE0.md](docs/PHASE0.md)) — Phase 0 in practice: cloud images, cloud-init, the virt-install command flag by flag, the three network layers, and the traps research caught.
  - **`docs/p1.html`** ([P1.md](docs/P1.md)) — Part 1 as built: the two-machine Vagrantfile explained, the command cheat sheet, the observed network map, and the eth0 lesson that justifies `--node-ip`.
  - **`docs/p2.html`** ([P2.md](docs/P2.md)) — Part 2 concepts before code: Deployments, Services, Ingress, the Host header, and how a curl reaches a pod.
- **[PLAN.md](PLAN.md)** — the build plan: work split, per-part method, every decision and its justification from the subject.
- **[CLAUDE.md](CLAUDE.md)** — working rules, graded literals, commands, and the traps.
- `en.subject.pdf` — the subject. It is the source of truth for grading.

## Quick verification

```bash
# p1 — two nodes Ready on the host-only network
vagrant ssh smbarkiS -c "kubectl get nodes -o wide"

# p2 — host-based routing, from the host
curl -H "Host: app1.com" http://192.168.56.110
curl -H "Host: app2.com" http://192.168.56.110
curl http://192.168.56.110                          # default -> app3

# p3 — the GitOps loop
curl -s http://localhost:8888/                      # {"status":"ok", "message": "v1"}
```
