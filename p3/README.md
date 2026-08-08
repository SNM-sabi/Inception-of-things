# p3 — K3d and Argo CD

No Vagrant here (subject p12: *"without Vagrant this time"*), so this part has
`scripts/` and `confs/` only.

```
p3/
├── confs/
│   └── application.yaml     # the Argo CD Application CR — the ONLY manifest here
└── scripts/
    ├── install.sh           # docker, kubectl, k3d, argocd CLI, from nothing
    ├── create_cluster.sh    # cluster + namespaces + Argo CD + Application
    └── reset.sh             # deletes the cluster
```

## Part 3 uses two repositories

| Repo | Holds | Who reads it |
|---|---|---|
| **this one** (graded) | `p3/confs/application.yaml` | the evaluator |
| **a separate public repo** | `manifests/{deployment,service,ingress}.yaml` | Argo CD |

The app manifests are **deliberately absent from this repository.** If a copy of
`deployment.yaml` also sat in `p3/confs/`, there would be no way for an evaluator
to tell which one is live, and it would look hand-applied. The one in Git is the
only one — that is the entire point of GitOps.

The second repo must be **public** and its name must contain a group member's
login (subject p12 blue box).

## Run

```bash
bash p3/scripts/install.sh                                                    # then nothing else to do
REPO_URL=https://github.com/<login>/<repo>.git bash p3/scripts/create_cluster.sh
curl http://localhost:8888/                                                   # {"status":"ok", "message": "v1"}
```

`install.sh` adds you to the `docker` group, which only applies to new login
sessions — `create_cluster.sh` re-execs itself under `sg docker` so you do not
have to log out in the middle of a defense.

Argo CD UI: `kubectl port-forward -n argocd svc/argocd-server 8080:443`, then
<https://localhost:8080> as `admin`. The password is printed by
`create_cluster.sh`, or:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

## The v1 → v2 demo

```bash
# in the GitOps repo clone — this is the ONLY thing you touch
sed -i 's|playground:v1|playground:v2|' manifests/deployment.yaml
git commit -am "v2" && git push

# back on the VM: wait ~20s, change nothing
curl http://localhost:8888/       # {"status":"ok", "message": "v2"}
```

The port map means this connection is **not** a `kubectl port-forward`, so it
survives Argo CD replacing the pod — which is exactly the moment a port-forward
would die, with `curl: (52) Empty reply` at the climax of the demo.

## Why the port map matters

`create_cluster.sh` creates the cluster with `-p "8888:80@loadbalancer"`:

```
host :8888 -> k3d load-balancer :80 -> Traefik -> Ingress -> Service :8888 -> pod
```

k3d port maps are **fixed at create time**. `--port-add` exists but is flagged
EXPERIMENTAL and recreates the load-balancer container, so forgetting the map
means deleting and recreating the cluster in front of the evaluator.

## Notes for the defense

- **K3s vs K3d** (p12 says you must know this): K3s is the Kubernetes
  distribution; K3d runs that distribution inside Docker containers. That is why
  K3d needs Docker and K3s does not — and why `docker ps` lists the same nodes
  `kubectl get nodes` does.
- The `Application` lives in `argocd` and targets `dev`. Do not mix them up.
- Argo CD's default reconciliation is 120s + up to 60s jitter ≈ 3 minutes of
  silence. `create_cluster.sh` patches `argocd-cm` to `timeout.reconciliation: 20s`
  and restarts the controller, which reads it only at startup. Production would
  use a Git webhook instead of polling.
- `selfHeal: true` means a manual `kubectl edit` gets reverted within seconds —
  worth demonstrating deliberately, because it *proves* Git is the source of truth.
- `allowEmpty: false` stops a mis-pushed commit from pruning the app away.
- Never use `kubectl set image` or `argocd app set` for the demo: p13 requires the
  change to come from the GitHub repository.
- Only `v1` and `v2` tags exist for `wil42/playground` — `:latest` gives
  `ErrImagePull: manifest not found`.
