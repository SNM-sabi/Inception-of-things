# Bonus — GitLab in the cluster

Part 3, but the Git repository is a GitLab instance running **inside your own
cluster**, in a dedicated `gitlab` namespace.

## Layout

```
bonus/
├── README.md
├── confs/
│   ├── gitlab.yaml         # namespace, PVC, Deployment, Service, Ingress
│   ├── application.yaml    # Argo CD Application pointing at the local GitLab
│   ├── helm-values.yaml    # alternative install route (see below)
│   └── app-repo/           # what you push INTO the GitLab project
│       ├── deployment.yaml
│       └── service.yaml
└── scripts/
    ├── install.sh          # docker, kubectl, k3d, argocd, helm
    ├── setup.sh            # cluster + namespaces + Argo CD + GitLab
    ├── hosts.sh            # /etc/hosts entry for the GitLab hostname
    ├── gitlab-info.sh      # root password / url / logs / shell
    ├── deploy-app.sh       # registers the Argo CD Application
    ├── port-forward.sh     # Argo CD UI + app
    ├── check.sh            # full state dump for the defense
    ├── clean.sh            # deletes the cluster
    └── gitlab-helm.sh      # alternative: official Helm chart
```

## Requirements

- **6 GB RAM minimum** on the VM (GitLab alone wants ~4 GB), 4 CPUs, 20 GB free disk.
- Host port **80** free — the cluster publishes it so your browser can reach GitLab.

## Run

```bash
cd bonus
./scripts/install.sh            # then log out / log back in (docker group)
./scripts/setup.sh              # 10-20 minutes, mostly GitLab's first boot
```

Then, in GitLab (<http://gitlab.gitlab.svc.cluster.local/>, user `root`,
password from `./scripts/gitlab-info.sh password`):

1. create a **public** project named `iot-app`;
2. push the app manifests into it:

```bash
git clone http://gitlab.gitlab.svc.cluster.local/root/iot-app.git
cd iot-app && mkdir -p manifests
cp ../confs/app-repo/*.yaml manifests/
git add . && git commit -m "init" && git push
```

3. register the application and check it:

```bash
cd .. && ./scripts/deploy-app.sh
./scripts/port-forward.sh
./scripts/check.sh              # expects {"status":"ok", "message": "v1"}
```

## The v1 → v2 demo, now against local GitLab

```bash
cd iot-app
sed -i 's|playground:v1|playground:v2|' manifests/deployment.yaml
git commit -am "v2" && git push

argocd app sync playground      # or wait ~3 min / press SYNC in the UI
cd .. && ./scripts/port-forward.sh
curl http://localhost:8888/     # {"status":"ok", "message": "v2"}
```

## Why the hostname is `gitlab.gitlab.svc.cluster.local`

Argo CD runs **inside** the cluster, so `localhost` means nothing to it — the
repository URL must be resolvable through Kubernetes DNS. Three things must
therefore agree on one single string:

| Where | Value |
|---|---|
| `external_url` in `confs/gitlab.yaml` | `http://gitlab.gitlab.svc.cluster.local` |
| `repoURL` in `confs/application.yaml` | same host |
| your browser and `git push` | same host, via the `/etc/hosts` entry + ingress |

If they diverge, GitLab issues redirects and clone URLs your tooling cannot
follow. That single detail is where most of the debugging time goes.

## Two installation routes

| | `confs/gitlab.yaml` (default) | `scripts/gitlab-helm.sh` |
|---|---|---|
| Shape | one omnibus pod | ~25 pods |
| RAM | ~4 GB | 6-8 GB |
| Boot | 5-10 min | 10-20 min |
| Debugging | one log | scattered |
| Realism | lower | higher |

The subject only says helm *"could be useful"* — the actual requirements are a
local instance, a `gitlab` namespace, and Part 3 working against it. Both routes
satisfy them; be ready to justify your choice.

## Notes for the defense

- `initial_root_password` only applies on the **first** boot. Afterwards the
  generated password lives in `/etc/gitlab/initial_root_password` inside the pod
  and is deleted after 24 h — `./scripts/gitlab-info.sh password` reads it.
- The image is `gitlab/gitlab-ce:latest`, which is what "latest version from the
  official website" means here. In production you would pin a version — know why.
- `strategy: Recreate` matters: two pods on one `ReadWriteOnce` PVC would corrupt data.
- The startup probe allows 30 minutes before Kubernetes declares failure; without
  it the pod would be killed mid-`reconfigure` and loop forever.
- Bonus is only graded if the mandatory part is flawless — verify p1, p2 and p3
  still run on the same machine before the defense.
