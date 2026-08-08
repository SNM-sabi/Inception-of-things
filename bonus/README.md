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
│   └── app-repo/           # what you push INTO the GitLab project
│       ├── deployment.yaml
│       ├── service.yaml
│       └── ingress.yaml    # reaches the app on :8888 without a port-forward
└── scripts/
    ├── install.sh          # docker, kubectl, k3d, argocd
    ├── setup.sh            # cluster + namespaces + Argo CD + GitLab
    ├── hosts.sh            # /etc/hosts entry for the GitLab hostname
    ├── gitlab-info.sh      # root password / url / logs / shell
    ├── deploy-app.sh       # registers the Argo CD Application
    ├── port-forward.sh     # Argo CD UI only (the app uses the ingress)
    ├── check.sh            # full state dump for the defense
    └── clean.sh            # deletes the cluster
```

## Requirements

- **6 GB RAM minimum** on the VM (GitLab alone wants ~4 GB), 4 CPUs, 20 GB free disk.
- Host ports **80** and **8888** free — the cluster publishes both onto the
  load-balancer: 80 so your browser and `git` reach GitLab on the same hostname
  Argo CD clones from, 8888 so Part 3's `curl http://localhost:8888/` still works.
  Note this means the **p3 cluster must be deleted first** — it is also named
  `iot` and already holds 8888 (`cd ../p3 && bash scripts/reset.sh`).

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
./scripts/check.sh              # expects {"status":"ok", "message": "v1"}
```

## The v1 → v2 demo, now against local GitLab

```bash
cd iot-app
sed -i 's|playground:v1|playground:v2|' manifests/deployment.yaml
git commit -am "v2" && git push

# Then touch nothing. Argo CD reconciles every 20s (setup.sh patches argocd-cm),
# so the flip happens on its own — that is the point being graded.
curl http://localhost:8888/     # {"status":"ok", "message": "v2"}
```

Same URL as Part 3, on purpose — subject p16 requires that everything from Part 3
still works against the local GitLab. `curl` goes through the Ingress, not a
port-forward: a forward dies exactly when Argo CD replaces the pod, which is the
moment the evaluator is watching.

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

## Why plain YAML and not the Helm chart

The subject only says helm *"could be useful"* — the actual requirements are a
local instance, a `gitlab` namespace, and Part 3 working against it. `confs/gitlab.yaml`
meets all three with one omnibus pod (~4 GB RAM, one log to read), so that is what
this bonus uses.

The official `gitlab/gitlab` chart is deliberately **not** offered as a second
route. Since chart 10.x it no longer bundles PostgreSQL, Redis or MinIO and
expects PostgreSQL 17 plus Gateway API, which turns one moving part into ~25 and
makes most published tutorials wrong. A second install path is also a second way
to fail a live demo and a second thing to justify.

## Notes for the defense

- `initial_root_password` only applies on the **first** boot. Afterwards the
  generated password lives in `/etc/gitlab/initial_root_password` inside the pod
  and is deleted after 24 h — `./scripts/gitlab-info.sh password` reads it.
- **The subject (p16) expects "the latest version available of Gitlab from the
  official website".** We satisfy that with an explicit pin, not `:latest`:
  `gitlab/gitlab-ce:19.2.1-ce.0` **is** the newest stable release. Pinning keeps
  the defense reproducible — with `:latest`, an upstream release between
  rehearsal and evaluation silently changes the thing being graded.
  This only stays true if the pin keeps matching the newest release, so
  **re-check the day before defending** (19.3 is due ~2026-08-20):

  ```bash
  curl -s "https://hub.docker.com/v2/repositories/gitlab/gitlab-ce/tags/?page_size=100&ordering=last_updated" \
    | tr ',' '\n' | grep '"name"' | grep -E 'ce\.0"' | head -5
  ```

  If a newer version has landed, bump the tag in `confs/gitlab.yaml`. Answer for
  the evaluator: *"it is the latest release; I pinned it by digest-stable tag so
  the demo cannot change under me mid-evaluation."*
- The app is reached at `http://localhost/` through `app-repo/ingress.yaml`,
  never `kubectl port-forward` — a forward dies when Argo CD replaces the pod.
  Only the Argo CD UI, which is not graded, is forwarded.
- `strategy: Recreate` matters: two pods on one `ReadWriteOnce` PVC would corrupt data.
- The startup probe allows 30 minutes before Kubernetes declares failure; without
  it the pod would be killed mid-`reconfigure` and loop forever.
- Bonus is only graded if the mandatory part is flawless — verify p1, p2 and p3
  still run on the same machine before the defense.
