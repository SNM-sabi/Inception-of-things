# EXPLANATION — Step One, explained from zero

This file explains **only the first step** of our work: building the outer VM (Phase 0)
and then **p1 slice 1.1 — one virtual machine, with the right box and the right hostname.**

Nothing else. Not K3s yet. Not the second machine yet. Not the network yet.

It is written assuming you know nothing about virtualisation, Vagrant, or Kubernetes.
Every concept is introduced before it is used. Read it top to bottom once, then we build.

---

## 0. The 10-second map — what are we even building?

The subject asks for three labs that get progressively bigger:

| Part | One sentence |
|---|---|
| **p1** | Two computers-that-aren't-real, running a tiny Kubernetes, talking to each other. |
| **p2** | One such computer, running three websites, with a traffic cop that picks which website answers. |
| **p3** | No fake computers at all — Kubernetes inside Docker, and a robot that deploys your code when you push to GitHub. |
| **bonus** | Your own private GitHub, running inside that same Kubernetes. |

We own **p1 and p2**. We start at p1. And p1 starts with **one virtual machine that boots and has the right name.** That is genuinely the whole first slice. It sounds trivial. It is not — about a third of the ways this project fails happen right here, before Kubernetes is even installed.

---

## 1. Concept: what is a virtual machine?

Your laptop has one CPU, some RAM, and a disk. Normally one operating system (your Ubuntu) owns all of it.

A **virtual machine (VM)** is a *pretend computer* built out of your real computer's resources. A program called a **hypervisor** carves off, say, 1 CPU core and 512 MB of RAM, invents a fake hard disk (which is really just a big file), invents a fake network card, and then boots a *completely separate* operating system inside that fake hardware.

The OS inside doesn't know it's fake. It thinks it has its own machine.

Two words we will use constantly:

- **Host** — the real machine. Your Ubuntu desktop.
- **Guest** — the pretend machine running inside it. Our Debian VMs.

**Why do we want this?** Because we're going to install Kubernetes, mess with the network, and then *delete the whole thing and do it again* — ten times. You cannot do that to your real laptop. A VM is disposable. `vagrant destroy` and it's gone without a trace.

> **Analogy:** a VM is a sealed aquarium on your desk. You can pour anything into it, boil it, or empty it into the sink. Your room stays dry.

### 1.1 The two hypervisors we care about

| Name | What it is |
|---|---|
| **KVM** (with **libvirt** + **QEMU**) | Virtualisation built *into the Linux kernel*. Fast, native, already on your machine. `libvirt` is the management layer, `virsh` is its command-line tool. |
| **VirtualBox** | Oracle's cross-platform hypervisor. Runs on Windows/Mac/Linux. Installs as an add-on kernel module. |

We are using **KVM/libvirt**, and this is a deliberate choice with two reasons:

1. Your kernel is `7.0.0-28-generic`. Ubuntu's packaged VirtualBox (7.0.16) **cannot compile its kernel modules against a 7.0 kernel** — it would simply refuse to install.
2. We are going to run VMs *inside another VM* (see §2). KVM-inside-KVM ("nested virtualisation") is reliable and supported. VirtualBox-inside-KVM is famously not.

Is that allowed? Yes, and the subject says so explicitly. **Subject p4, blue box:** *"You can use any tools you want to set up your host virtual machine as well as the provider used in Vagrant."* We will quote that line if an evaluator asks.

---

## 2. Concept: why an *outer* VM? (Phase 0)

Here is a line that surprises everyone, from **subject p4, bullet 1, in bold**:

> *"The whole project has to be done in a **virtual machine**."*

Your machine is bare metal — you can prove it: `systemd-detect-virt` prints `none`. So to obey that line, we build **one big VM first**, and do everything inside it.

Which means we end up with VMs inside a VM:

```
Your Ubuntu laptop            ← bare metal (host)
└── Outer VM (Debian 13)      ← the "virtual machine" the subject demands
    │  8 GB RAM, 6 vCPU, 80 GB disk
    │  Vagrant + libvirt + Docker live here
    ├── smbarkiS   (1 CPU, 1024 MB)   ← p1's server VM
    └── smbarkiSW  (1 CPU, 512 MB)    ← p1's worker VM
```

That is what "nested virtualisation" means: the outer VM must itself be able to *create* VMs. For that, the fake CPU we give it must expose the hardware virtualisation instructions. In libvirt terms that's `cpu mode=host-passthrough` — "don't invent a generic CPU, hand the guest the real one's feature set."

**How we'll know it worked:** inside the outer VM, the file `/dev/kvm` exists. If it doesn't, the inner VMs can only run in slow software emulation (minutes per boot instead of seconds) and we fall back to building on bare metal instead. That's the Phase 0 decision gate — we check, we decide, we write down which we chose, because the evaluator may ask why.

**Why 8 GB for the outer VM?** It has to hold Debian itself (~1 GB), plus 1024 + 512 MB for the two inner VMs, plus later Docker and Kubernetes for p3. Your desktop already uses ~6.5 of 15 GB, so close Firefox and friends before starting. And a rule we'll keep: **never run p1/p2's VMs and p3's cluster at the same time.**

---

## 3. Concept: what is Vagrant, and what problem does it solve?

Without Vagrant, creating a VM means: download an ISO, open a GUI, click Next eight times, pick a disk size, sit through a Debian installer, invent a username and password, configure the network by hand. Twenty minutes of clicking. And when you destroy it, you do all twenty minutes again. And your teammate's VM is subtly different from yours.

**Vagrant turns all of that into a text file and one command.**

You write a file called `Vagrantfile` describing the machine you want. Then:

```bash
vagrant up
```

and Vagrant downloads a pre-built disk image, boots it, sets the hostname, configures the network, sets up SSH keys, and runs your setup scripts. Two minutes, zero clicks, and **identical on every machine** — which matters enormously, because the defense happens on our machine but the *scripts* must be reproducible.

The subject requires this. **Subject p6:** *"you must set up two machines... using Vagrant."*

### 3.1 The four Vagrant words you must know

**Box** — a pre-built VM disk image, ready to boot. Someone else already ran the Debian installer and saved the result. `debian/trixie64` is the official Debian project's box for Debian 13. Vagrant downloads it once (~500 MB) and caches it in `~/.vagrant.d/boxes/`, so the second `vagrant up` doesn't re-download.

> **Analogy:** a box is a factory-sealed laptop with the OS pre-installed. You don't install Windows; you unbox it and it boots.

**Provider** — *which hypervisor* actually runs the VM. Same Vagrantfile, different provider (`libvirt`, `virtualbox`, ...). This is why a box has to publish an artifact for your provider — `debian/trixie64` publishes **libvirt only**. Ask for it with VirtualBox and you get *"The box you're attempting to add doesn't support the provider you requested."* That's a real trap; we avoid it by using libvirt.

**Provisioner** — a script Vagrant runs *inside* the guest, automatically, right after first boot. This is where K3s will eventually be installed. We are **not** using it in slice 1.1.

**`vagrant ssh`** — logs you into the guest. No password. We'll explain why in §5.

### 3.2 The `.vagrant/` directory — and why it must never be committed

The moment you run `vagrant up`, Vagrant creates a hidden `.vagrant/` folder next to your Vagrantfile. It stores which VM belongs to this project (by UUID), and — critically — **the SSH private key it generated for each machine.**

A private key is a secret. Committing `.vagrant/` to git publishes it. It also breaks fresh clones, because the UUIDs inside point at VMs that don't exist on the new machine.

This is already handled — `.gitignore` at the repo root contains `.vagrant/` as of commit #1. Don't undo it.

---

## 4. Concept: machine *name* vs machine *hostname* (the one people get wrong)

The subject says, **p6:**

> *"The name of the machines... must be your login followed by an S for the server, and your login followed by SW for the server worker."*

Our login is `smbarki`, so: **`smbarkiS`** and **`smbarkiSW`**.

But "name" here touches **two different things**, and they are set by two different lines:

| | Set by | Who sees it | Our value |
|---|---|---|---|
| **Vagrant machine name** | `config.vm.define "smbarkiS"` | You. It's the label you type: `vagrant ssh smbarkiS`. Also becomes part of the hypervisor's domain name (`virsh list` shows something like `p1_smbarkiS`). | `smbarkiS` |
| **Guest hostname** | `config.vm.hostname = "smbarkiS"` | The OS inside. It's what `hostname` prints and what appears in your shell prompt. | `smbarkiS` |

They're independent. You could define the machine as `foo` and set its hostname to `bar` and Vagrant wouldn't complain. We set **both** to `smbarkiS`, because the evaluator will check both — they'll type `vagrant ssh smbarkiS` (needs the define) and then look at the prompt (needs the hostname).

### 4.1 A trap worth knowing *now*, before it scares you later

Much later, when K3s is running, `kubectl get nodes` will print the node's name in **lowercase**: `smbarkis`, not `smbarkiS`.

**That is not a bug and you must not "fix" it.** Kubernetes object names follow the RFC-1123 DNS rules, which forbid uppercase, so Kubernetes lowercases the hostname when it registers the node. The VM's actual hostname is still `smbarkiS` — `hostname` proves it. If you try to force it with `--node-name=smbarkiS`, K3s refuses to start at all.

Rehearse the sentence: *"The hostname is smbarkiS as required; Kubernetes canonicalises node names to lowercase because node names are DNS labels."*

---

## 5. Concept: how SSH works here, and why "no password" is free

**Subject p6:** *"SSH must be functional on both machines and only be used for the initial connection... A password should never be required."*

**SSH** is remote login. Two ways to authenticate:

- **Password** — you type a secret. Bad for automation: something must type it every time.
- **Key pair** — you hold a *private key* file; the server holds the matching *public key*. The server sends a challenge, your key answers it mathematically. Nothing to type.

Here is the good news: **Vagrant already does the key-pair thing, by default, with no configuration from us.** On first boot it generates a fresh keypair *per machine*, injects the public half into the guest's `~/.ssh/authorized_keys`, and stores the private half in `.vagrant/`. So `vagrant ssh smbarkiS` just works, passwordless, out of the box.

This means the requirement is satisfied by writing **zero lines**. Which leads to a rule:

> **Do NOT add `config.ssh.insert_key = false`, and do NOT inject your own key.** You'd be replacing per-machine generated keys with the well-known insecure default key — a security *regression* that reimplements something already working. Tutorials suggest it; ignore them.

To prove it passwordlessly *without* `vagrant ssh` (an evaluator may ask), you use the config Vagrant will happily print:

```bash
vagrant ssh-config smbarkiS      # shows Host, Port, IdentityFile
ssh -F <(vagrant ssh-config) smbarkiS hostname
```

---

## 6. Concept: the networking, previewed (we implement it in slice 1.2)

We don't touch the network in slice 1.1, but you need the mental model now, because it explains why the *next* slice exists at all.

**Every Vagrant VM gets a first network card that Vagrant fully controls, and it is always NAT.** NAT means the VM can reach the internet through the host, but nothing can reach *in*. Vagrant needs this card for `vagrant ssh` (it forwards a host port to the guest's port 22).

The consequence that bites everyone: **under NAT, every single VM gets the exact same IP address — `10.0.2.15`.** Both of our machines will have it. It's not a conflict, because each lives in its own private NAT world — but it means `10.0.2.15` is *meaningless* as an address for one VM to talk to another.

So in slice 1.2 we add a **second** network card on a **host-only / private network**: a virtual switch that connects the host and the VMs to each other, and nothing else. On that card we assign the fixed addresses the subject demands:

**Subject p6:** *"a dedicated IP address"* — and p7/p8 show **192.168.56.110** (server) and **192.168.56.111** (worker).

Why `192.168.56.x` specifically? It's the classic host-only range, and more importantly it's the literal the subject prints — and we match printed literals byte-for-byte.

**Local warning:** NordVPN is installed on this host. Its kill-switch inserts iptables rules ahead of everything else and will blackhole `192.168.56.x`. Disconnect it before any demo or you'll spend an hour debugging a network that's fine.

---

## 7. Now the actual first slice — 1.1

### What we are building

A `Vagrantfile` in `p1/` that defines **one** machine, from the Debian 13 box, named and hostnamed `smbarkiS`. Nothing else. No IP, no RAM tuning, no scripts.

### Why so small?

Because of the rule we agreed on: **advance in the smallest slice that can be observed working.** If we wrote the whole Vagrantfile at once and `vagrant up` failed, the cause could be the box, the provider, the network, the memory setting, the provisioning script, or a typo. Six suspects. With slice 1.1 there is exactly one thing that can be wrong, so a failure *tells you what it is*.

This costs about ninety seconds and saves hours. Every slice after this adds one suspect at a time.

### What the file will contain, line by line

```ruby
Vagrant.configure("2") do |config|
  config.vm.define "smbarkiS" do |server|
    server.vm.box      = "debian/trixie64"
    server.vm.hostname = "smbarkiS"
  end
end
```

| Line | Meaning |
|---|---|
| `Vagrant.configure("2")` | Use version 2 of Vagrant's configuration language. Not the Vagrant version — the *config schema* version. Every modern Vagrantfile starts this way. |
| `do \|config\|` | Ruby block syntax. `config` is the object we hang settings on. (A Vagrantfile is a real Ruby program, which is why you'll see loops and variables in later slices.) |
| `config.vm.define "smbarkiS"` | Declare a machine called `smbarkiS`. This is what makes multi-machine setups possible, and what `vagrant ssh smbarkiS` refers to. |
| `server.vm.box` | Which pre-built image to boot. |
| `server.vm.hostname` | What the guest OS calls itself. |

Note we're using `server.` inside the define block rather than `config.` — settings inside a `define` apply to *that machine only*. In slice 1.3 we add a second define block, and this separation is what keeps their settings apart.

### What we will run

```bash
cd p1
vagrant up
```

### What we expect to see — write this down *before* running it

1. `==> smbarkiS: Box 'debian/trixie64' could not be found. Attempting to find and install...` then a download progress bar. **First run only** — after that it's cached.
2. `==> smbarkiS: Creating domain with the following settings...` — "domain" is libvirt's word for a VM.
3. `==> smbarkiS: Setting hostname...`
4. `==> smbarkiS: Rsyncing folder: /home/.../p1/ => /vagrant` — Vagrant shares the project folder into the guest at `/vagrant`. Under libvirt this is a **one-way rsync**, host → guest. Remember that; it matters much later (it's why we won't try to copy a file *out* of the guest).
5. No errors, and the prompt comes back.

Then the proof:

```bash
vagrant ssh smbarkiS -c "hostname"
```

Expected output, exactly:

```
smbarkiS
```

And a look from the hypervisor's side:

```bash
virsh list --all
```

Expected: a running domain whose name contains `smbarkiS`.

### How we'll know it's *actually* right

Three things, all observable:
- The command printed `smbarkiS` — with the capital S. Not `debian`, not `smbarkis`.
- It printed it **without asking for a password**. That's the SSH requirement, already met.
- `virsh` sees the domain — proving it's genuinely a KVM VM, not something Vagrant faked.

### What could go wrong, and what it means

| Symptom | Cause | Fix |
|---|---|---|
| *"doesn't support the provider you requested"* | Vagrant defaulted to VirtualBox; this box is libvirt-only | `vagrant up --provider=libvirt`, or set `VAGRANT_DEFAULT_PROVIDER=libvirt` |
| *"Call to virDomainCreate failed"* / KVM permission denied | Your user isn't in the `libvirt` group, or `/dev/kvm` is missing inside the outer VM | Add to group and re-login; if `/dev/kvm` is missing, that's the Phase 0 gate failing — fall back to bare metal |
| Hangs at *"Waiting for domain to get an IP address"* | libvirt's default network isn't started | `virsh net-start default && virsh net-autostart default` |
| `hostname` prints `debian` | `vm.hostname` didn't apply | Check the spelling of the key; `vagrant reload` |
| Download crawls | It's ~500 MB, once | Wait. It's cached afterwards. |

If reality differs from the five expectations above **in any way**, we stop and explain the gap before writing another line. That gap is where the learning actually is.

---

## 8. What we are deliberately NOT doing in slice 1.1

Being explicit about this is half the discipline:

- ❌ No `private_network` / static IP — that's 1.2
- ❌ No memory or CPU settings — that's 1.2 (defaults are fine to just boot)
- ❌ No second machine — that's 1.3
- ❌ No K3s, no kubectl, no provisioning script — that's 1.4+
- ❌ No `swapoff`, no `update-alternatives --set iptables`, no `insert_key = false`, no extra plugins

That last row is the **cargo-cult filter**. Those lines appear in most Vagrantfiles you'll find online. Every one of them is either obsolete (Debian-10-era advice), redundant (K3s already sets `FailSwapOn: false`), or actively harmful. Our rule: **if you cannot explain a line, delete it** — because at defense, an unexplainable line is worse than a missing one. A missing line might not be noticed. An unexplainable line *will* be asked about.

---

## 9. The order of operations for step one

```
Phase 0                                        p1 slice 1.1
─────────────────────────────────────────────  ─────────────────────
1. Create outer VM (virt-manager)              5. Write p1/Vagrantfile
   Debian 13, 8 GB, 6 vCPU, 80 GB                 (one machine)
   cpu mode = host-passthrough                 6. vagrant up
2. Check /dev/kvm exists inside   ← GATE       7. vagrant ssh smbarkiS -c hostname
3. Install Vagrant 2.4.9 (HashiCorp apt repo)  8. Confirm: smbarkiS, no password
   + vagrant-libvirt plugin + qemu-system-x86  9. Explain what we saw
4. Verify: vagrant --version, virsh list       ─────────────────────
                                               → then slice 1.2
```

One note on step 3: **there is no `vagrant` package in Debian's or Ubuntu's repositories.** `apt install vagrant` fails or installs something ancient. You must add HashiCorp's apt repository. This bites people on the evaluator's machine too, so it's worth remembering.

---

## 10. Glossary — every term used above, in one line each

| Term | Meaning |
|---|---|
| **Host** | The real, physical machine. |
| **Guest** | The operating system running inside a VM. |
| **Hypervisor** | The software that creates and runs VMs (KVM, VirtualBox). |
| **KVM** | Kernel-based Virtual Machine — Linux's built-in hypervisor. |
| **QEMU** | The emulator that provides the fake hardware; pairs with KVM for speed. |
| **libvirt** | Management API/daemon on top of KVM+QEMU. `virsh` is its CLI. |
| **Domain** | libvirt's word for a virtual machine. |
| **Nested virtualisation** | Running a hypervisor *inside* a VM. |
| **`/dev/kvm`** | The device file proving hardware virtualisation is available. |
| **Vagrant** | Tool that builds VMs from a text file. |
| **Vagrantfile** | That text file. Ruby. Capital V, no extension. |
| **Box** | A pre-built, bootable VM image Vagrant downloads. |
| **Provider** | Which hypervisor Vagrant drives. |
| **Provisioner** | A script Vagrant runs inside the guest after boot. |
| **`.vagrant/`** | Vagrant's local state — contains SSH private keys. Never commit. |
| **NAT** | Network mode where the guest reaches out but nothing reaches in. Always NIC 1. |
| **Host-only / private network** | A virtual switch joining host and guests only. Where `192.168.56.x` lives. |
| **SSH key pair** | Passwordless authentication: private key on the client, public key on the server. |
| **RFC-1123** | The DNS naming rules Kubernetes follows — the reason node names are lowercase. |

---

## 11. Questions you should be able to answer after step one

If you can't answer these without looking, re-read the relevant section before we move on.

1. Why are we building an outer VM at all, and which line of the subject demands it? *(§2)*
2. Why libvirt and not VirtualBox — give two reasons, one of them about this specific machine. *(§1.1)*
3. What is the difference between `vm.define` and `vm.hostname`? Which one does `vagrant ssh smbarkiS` use? *(§4)*
4. Where does the passwordless SSH come from? How many lines did we write for it? *(§5)*
5. Why will both VMs have the IP `10.0.2.15`, and why doesn't that break anything yet? *(§6)*
6. Why is slice 1.1 not "write the whole Vagrantfile"? *(§7)*
7. Name three lines commonly found in Vagrantfiles that we refuse to write, and why. *(§8)*

---

**Next after this:** slice 1.2 — add the static IP `192.168.56.110` on a second NIC, plus the provider block (1 CPU, 1024 MB). Its proof: `ip -4 a` inside the guest shows `192.168.56.110`, and `ping 192.168.56.110` works **from the host**.
