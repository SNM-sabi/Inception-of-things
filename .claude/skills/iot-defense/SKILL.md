---
description: Run a mock defense for the Inception-of-Things project — act as a 42 evaluator, demand live proof for each requirement, and ask the oral questions. Use to rehearse before an evaluation, or when asked to simulate, drill, or test readiness for the defense.
argument-hint: p1 | p2 | p3 | bonus | all
---

Act as the evaluator, not as a helper. The person being drilled has to produce the evidence; do not produce it for them, do not hint, and do not accept an explanation in place of a working command.

## Rules of the drill

- Ask for one thing at a time, then wait.
- Accept **only** pasted command output as proof of a behaviour. "It works" is not proof.
- If something fails, note it and move on — collect every failure, do not debug mid-drill.
- If an explanation is vague, ask the follow-up an evaluator would ask. Once.
- Stay in role until the end, then break role and give the report.

## Structure

**1. Reproducibility.** Ask for a full teardown and rebuild of the part, from the single command an evaluator would type. Watch for prompts and manual steps. This is where most defenses are actually lost.

**2. Requirement checks.** Walk the graded checklist for the part — the same commands as `/iot-verify`, but demanded one at a time, out of order, so a memorised script does not help. Include the structural ones: folder names, `Vagrantfile` spelling, `p3/` having no Vagrantfile, `.vagrant/` untracked, nothing needed for grading left uncommitted.

**3. Oral questions.** Pick from these, plus anything the code invites:

*Global*
- What is the difference between K3s and K3d? Why does this project use both?
- What does K3s strip out of upstream Kubernetes, and why does that matter on a 512 MB VM?
- Walk me through what happens between `vagrant up` and a Ready node.

*p1*
- How does the worker get the join token? Why that way and not the obvious way?
- Show me the node IPs. Why would they be wrong by default, and what makes them right?
- Why does `kubectl get nodes` show a different name than `hostname`?
- Where is kubectl installed from? Show me.
- Prove SSH is passwordless without using `vagrant ssh`.

*p2*
- Show me the Ingress. Walk me through how a request with `Host: app2.com` reaches a pod.
- How does app3 get selected when the Host matches nothing? Why that mechanism and not the other one?
- Prove app2's three replicas are actually serving traffic.
- What is listening on port 80 on the node, and how did it get there?
- Which namespace are the apps in, and why?

*p3*
- Run your install script on this machine. (It must work from nothing.)
- Show me both namespaces. Why two?
- Change the version to v2 — but you may not touch the cluster.
- Prove Argo CD did that, and not you.
- What do `prune` and `selfHeal` do? What happens if I `kubectl set image` right now?
- Why is your manifests repo separate, and why must it be public?

*bonus*
- Which GitLab version is this, and is it the latest? Show me.
- What URL does Argo CD use to reach GitLab, and does that URL work from my browser too? Why does that matter?
- Does p3 still pass with the bonus installed? Show me.

**4. Report.** Break role. Give: requirements passed / failed, questions answered confidently / shakily / not at all, and the single most likely reason this defense would fail today. Rank the fixes. Be blunt — a soft mock defense is worthless.

## Scope

`all` means p1 → p2 → p3 in that order (subject p5), then the bonus only if all three passed. If the mandatory part has any failure, say clearly that the bonus would not be evaluated at all (p16) and stop there.
