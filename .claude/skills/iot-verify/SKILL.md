---
description: Verify one part of the Inception-of-Things project against the subject's graded checklist and report PASS/FAIL per requirement with real command output. Use when asked to verify, check, test, or confirm p1, p2, p3 or the bonus is working.
argument-hint: p1 | p2 | p3 | bonus
---

Run the evaluator's own commands for the requested part and report a verdict per requirement. **Never report a PASS without pasting the output that proves it.** If a check needs a manual fix-up to pass, it is a FAIL.

## Process

1. Determine the part from the argument. If none was given, infer from the files recently changed; if still ambiguous, ask.
2. Run that part's checks below, in order. Do not stop at the first failure — run them all so the report is complete.
3. Report a table: `Requirement | Command | Observed | PASS/FAIL`.
4. End with the count of failures. If any check failed, state plainly which gate is blocked; do not soften it.
5. Do not fix anything. This skill only observes.

## p1 — two VMs, K3s server + agent

```bash
cd p1
vagrant status                                          # both machines "running"
vagrant ssh smbarkiS -c "hostname"                      # smbarkiS
vagrant ssh smbarkiSW -c "hostname"                     # smbarkiSW
vagrant ssh smbarkiS -c "kubectl get nodes -o wide"     # 2x Ready, same version
vagrant ssh smbarkiS -c "ls -l /usr/local/bin/kubectl"  # symlink -> k3s
vagrant ssh smbarkiS -c "systemctl is-active k3s"       # active
vagrant ssh smbarkiSW -c "systemctl is-active k3s-agent"
ping -c1 192.168.56.110 && ping -c1 192.168.56.111
```

Checks: INTERNAL-IP column must read **192.168.56.110** and **192.168.56.111** — never a `192.168.121.x` management-network lease. ROLES must be `control-plane` and `<none>` — **not** `control-plane,master`: the legacy `master` label was removed upstream and K3s v1.36 no longer applies it (verified live 2026-08-08; older subject screenshots still show both). Node NAMEs are lowercase (`smbarkis`) — that is correct, not a failure. Both `vagrant ssh` calls must succeed without a password prompt.

## p2 — one VM, three apps, Ingress

```bash
cd p2
vagrant ssh smbarkiS -c "kubectl get all"               # no -n : apps live in default
vagrant ssh smbarkiS -c "kubectl get ingress"           # ADDRESS 192.168.56.110
vagrant ssh smbarkiS -c "kubectl describe ingress"      # Default backend must be app-three
curl -s -H "Host: app1.com" http://192.168.56.110
curl -s -H "Host: app2.com" http://192.168.56.110
curl -s http://192.168.56.110
curl -s -H "Host: nonsense.com" http://192.168.56.110
for i in $(seq 9); do curl -s -H "Host: app2.com" http://192.168.56.110 | head -1; done | sort | uniq -c
```

Checks: the three curls must return three **visibly different** apps. Both the bare-IP and the nonsense-Host requests must return app3. `kubectl get deploy` must show app-two at **3/3**, app-one and app-three at 1/1. The replica loop must show **3 distinct pod names** — one name repeated nine times means the Service is not load-balancing. All curls run **from the host**, never from inside the VM.

## p3 — K3d + Argo CD

```bash
k3d cluster list
kubectl get ns                                          # argocd AND dev, both Active
kubectl get pods -n argocd                              # all Running
kubectl get pods,deploy,svc,ingress -n dev
kubectl -n dev get deploy -o jsonpath='{.items[0].spec.template.spec.containers[0].image}'
curl -s http://localhost:8888/ ; echo
kubectl get application -n argocd -o wide
argocd app get <app> 2>/dev/null || kubectl get application -n argocd -o yaml | grep -A3 'sync\|health'
```

Checks: response body must be exactly `{"status":"ok", "message": "v1"}` or `"v2"` — the spacing is the subject's, do not normalise it. The Application must be **Synced + Healthy** with `syncPolicy.automated`. `repoURL` must be a **public** GitHub repo whose name contains `smbarki` — confirm by fetching it unauthenticated. There must be **no** copy of the app manifests under `p3/confs/`.

For the full GitOps loop, the v1→v2 push must be verified separately — that is `/iot-defense`, not this skill.

## bonus — GitLab

```bash
kubectl get ns gitlab
kubectl get pods,pvc,svc,ingress -n gitlab
curl -sI http://gitlab.gitlab.svc.cluster.local/-/readiness
kubectl get application -n argocd -o jsonpath='{.items[*].spec.source.repoURL}'
```

Checks: namespace is exactly `gitlab`; GitLab reports ready; the Argo CD `repoURL` points at the **local** GitLab, not github.com; and the deployed GitLab version matches the latest on the official site. Also re-run the whole p3 check set — the bonus must not have broken it.

## Structural checks (run for every part)

```bash
find . -maxdepth 2 -not -path './.git/*' -not -path './.claude/*' | sort
git status --porcelain
```

Folder names must be exactly `p1 p2 p3 bonus`, each with `scripts/` and `confs/`; `p3/` must have **no** Vagrantfile; `Vagrantfile` is spelled with a capital V and no extension; `.vagrant/` must not be tracked; and nothing needed for grading may be untracked.
