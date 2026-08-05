---
description: Explain a file, line, flag, or concept in the Inception-of-Things project — what it does, which subject requirement it serves, and what breaks without it. Use when asked what something does or why it is there, before implementing a new slice, or to check whether a line is cargo-cult that should be deleted.
argument-hint: <file, flag, or concept>
---

The project is graded by an evaluator asking questions. A line nobody can explain is worse than a missing line: it is a line that will be asked about. This skill turns "it works" into "I know why it works".

## Process

For whatever was named, answer these five, in this order, and keep each to a few sentences:

1. **What it does** — mechanically, concretely. Not the docstring; what actually happens on the machine.
2. **Which subject requirement it serves** — quote the subject and give the page number. Read `en.subject.pdf` if unsure. If it serves no requirement, say so — that is the most useful answer this skill can give.
3. **What breaks without it** — the specific symptom, at the specific moment it would appear. "It wouldn't work" is not an answer; "the agent joins, `get nodes` reads Ready, and the failure stays hidden until p2's traffic test" is.
4. **What the alternatives were, and why not them** — the evaluator's favourite follow-up.
5. **The one-sentence defense answer** — what to actually say out loud when asked.

## Cargo-cult verdict

End with one of:

- **KEEP** — it serves a requirement or prevents a real failure.
- **DELETE** — it is copied from a tutorial and does nothing here. Say what it was probably copied from.
- **KEEP BUT KNOW** — redundant in our setup, harmless, but must be explainable if asked.

Be willing to say DELETE about our own code. The project rule is that an unexplainable flag gets removed, and this is where that gets decided. Known examples already ruled on in `CLAUDE.md`: `--advertise-address` (DELETE, it defaults to `--node-ip`), `--bind-address` (DELETE, actively breaks kubectl), `swapoff -a` (DELETE, K3s sets `FailSwapOn: false`), `update-alternatives --set iptables` (DELETE, Debian-10-era advice), `--flannel-iface` (KEEP BUT KNOW, cheap insurance once `--node-ip` is set).

## Before implementing a new slice

Same five questions, in advance, plus: **what we expect to see when it works**, as a concrete command and its expected output. That expectation gets checked against reality afterwards — if what we saw differs from what we predicted, explain the gap before moving on. That gap is where the actual learning is.

## Sources, in priority order

1. `en.subject.pdf` — the only thing that decides whether something is required.
2. `CLAUDE.md` and `PLAN.md` — decisions already made and their justification.
3. Official upstream docs (k3s.io, k3d.io, argo-cd.readthedocs.io, Traefik, Vagrant). Fetch them rather than recalling; versions move.

Blog posts and other students' repos are not sources. Several of them are actively wrong for the versions we pinned.
