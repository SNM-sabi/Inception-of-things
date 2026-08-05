---
description: Destroy a part of the Inception-of-Things project completely and rebuild it from zero, then verify it, proving the evaluator can reproduce it live. Use before any commit, push, or move to the next part, or when asked to do a clean run, rebuild from scratch, or test reproducibility.
argument-hint: p1 | p2 | p3 | bonus
---

This is the gate. The subject is defended on a machine that starts clean, so "it works right now" is worth nothing — only "it works after a full teardown" counts. Most defense failures are things that only worked because of state left over from a previous attempt.

## Process

1. **Warn before destroying.** State exactly what will be torn down and confirm, unless the user already said to just do it. This deletes VMs and clusters.
2. Tear down completely (below).
3. Rebuild with the single command an evaluator would type. **Time it.**
4. Run `/iot-verify` for the same part.
5. Report: total wall-clock time, any prompt or manual step that appeared, and the verify table.

**Any of these is a FAIL, even if the end state looks correct:**
- A prompt appeared and needed an answer.
- A step had to be re-run, or anything was fixed by hand.
- The rebuild depended on a file, image, or cluster left over from before.
- It took long enough that an evaluator would lose patience — note the time and say so.

## p1 / p2

```bash
cd p1                      # or p2
vagrant destroy -f
rm -rf .vagrant
time vagrant up            # the ONLY command allowed to be run
```

Also confirm no stale domains survived: `virsh list --all` (libvirt) or `VBoxManage list vms` (VirtualBox). A leftover `smbarkiS` from a previous run will cause a name clash or silently satisfy a check it should not.

## p3

```bash
k3d cluster delete iot
docker system prune -af --volumes      # ask first; this wipes unrelated images too
time bash p3/scripts/install.sh
time bash p3/scripts/create_cluster.sh
```

The install script is itself a graded artifact (p12: it runs *during* the defense). Watch for anything that assumes Docker is already installed, that the user is already in the `docker` group, or that a `kubectl` context already exists.

## bonus

```bash
kubectl delete namespace gitlab --wait
rm -rf "$HOME/.iot-storage"            # the bind-mounted GitLab data
time bash bonus/scripts/install.sh
```

Then re-run `/iot-clean-run p3` as well: the bonus must be purely additive, and p3 alone must still pass.

## After a passing clean run

Say plainly that the gate is met, and remind that the remaining gate conditions are non-automatable: every line explainable without notes, and nothing outside that part's folder changed (`git status`).
