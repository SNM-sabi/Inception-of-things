# PHASE 0 — Building the outer VM, explained from zero

This is the companion to [EXPLANATION.md](EXPLANATION.md). That file explained the *concepts*
before we touched anything. This one explains **Phase 0 as we are actually doing it** — every
command, every file, every flag, and the three traps the research caught before they caught us.

Where we are right now:

| Phase 0 piece | Status |
|---|---|
| 0.1 Install the hypervisor toolchain on the laptop | ✅ done, verified |
| Download + verify the Debian 13 cloud image | ✅ done, SHA512 matches Debian's |
| Build the cloud-init seed ISO | ✅ done, label `cidata` verified |
| 0.2 Create the outer VM (`sudo bash ~/iot-create-vm.sh`) | ✅ done — `iot-host` at 192.168.122.182, `ssh iot-host` |
| 0.3 Gate: `/dev/kvm` exists *inside* the VM | ✅ **PASSED** — kvm_intel loaded, vmx on all 6 vCPUs |
| 0.4 Vagrant + vagrant-libvirt inside the VM, box pre-cached | ✅ done — Debian pkgs, `debian/trixie64` cached (867 MB) |
| **Next: p1 slice 1.1** — the five-line Vagrantfile | ⬅ **you are here** |

*(Docker inside the VM is deliberately deferred: p3's own `install.sh` must install it live
during the defense — subject p12's yellow box — and nothing in p1/p2 needs it.)*

---

## 1. What we installed on the laptop, and what each piece is

One `apt` command installed six things. Each has exactly one job:

| Package | Job, in one sentence |
|---|---|
| `qemu-system-x86` | The **emulator** — invents the fake CPU, disk, network card the guest will see. |
| `libvirt-daemon-system` | The **manager** — a background service (`libvirtd`) that creates, starts, stops and tracks VMs. |
| `libvirt-clients` | The **remote control** — gives us `virsh`, the command line for talking to the manager. |
| `virtinst` | The **builder** — gives us `virt-install`, which creates a VM from one command instead of a GUI wizard. |
| `virt-manager` | The **window** — a GUI where you can watch the VM's screen. Comfort, not necessity. |
| `cloud-image-utils` | The **seeder** — gives us `cloud-localds`, which packs our first-boot config into a tiny ISO. |

> **Analogy:** QEMU is the stage, libvirt is the stage manager, virsh is the walkie-talkie
> you use to give the stage manager orders, and virt-install is the crew that builds the set.

## 2. The mystery of the empty list — libvirt is TWO services, not one

Right after installing, we ran `virsh net-list --all` and got… nothing. Not an empty network —
*no networks at all*. That looked broken. It wasn't, and the reason will bite again later, so
learn it now:

**libvirt runs two separate worlds on the same machine.**

| World | URI | Who owns it | Has the NAT network? |
|---|---|---|---|
| System | `qemu:///system` | root / `libvirt` group members | **yes** — `default`, 192.168.122.0/24 |
| Session | `qemu:///session` | just you, unprivileged | no |

`virsh` silently picks a world based on who you are. Our shell wasn't in the `libvirt` group yet
(group membership is only read at login), so `virsh` quietly fell back to the *session* world and
truthfully reported that **it** had no networks. The system world had the `default` network active
and on autostart the whole time.

**Why you must remember this:** `vagrant-libvirt` — which we'll use inside the outer VM for p1 —
talks to `qemu:///system`. If `vagrant up` ever says it cannot connect to libvirt, the answer is
almost always: *this shell hasn't picked up the libvirt group yet; log out and back in.*

## 3. Installing an OS with no installer — cloud images

The classic way to make a VM is to boot the Debian installer ISO and answer questions for twenty
minutes. We are not doing that. Debian publishes **cloud images**: disks where the installation
has *already happened*. You copy the disk, boot it, and Debian is just… running, in seconds.

One problem: if the install already happened, nobody ever typed a username, a password, or a
hostname. The image is generic on purpose. Something must personalise it on first boot — that
something is **cloud-init** (§4).

### 3.1 Debian publishes three variants — the choice matters

| Variant | Size | What it is | Verdict |
|---|---|---|---|
| `generic` | 414 MB | Drivers for real hardware and every cloud | works, but carries dead weight |
| `genericcloud` | 326 MB | **Only virtio drivers — built for exactly our case: a KVM guest** | ✅ ours |
| `nocloud` | 389 MB | **No cloud-init at all.** Root login, no password, no SSH server | ☠ trap |

`nocloud` sounds like "no cloud, so for local VMs" — it is the opposite of what we want. It would
silently ignore our seed ISO, and we'd boot a VM with no user and no way in over SSH. The name
means "no cloud-*init*". Research confirmed one more detail worth knowing: Debian's *cloud kernel*
(used in `genericcloud`) deliberately keeps the SATA CD-ROM driver **because** config-drive ISOs
are how clouds hand configuration to VMs — so our seed CD is a first-class citizen, not a hack.

### 3.2 We verified the download — here's what that does and doesn't prove

```
ours:     769562604ecaac26...
Debian's: 769562604ecaac26...   → MATCH
```

We computed the SHA512 of our downloaded file and compared it to the sum Debian publishes on
`cloud.debian.org` over HTTPS. A match proves the file arrived **complete and uncorrupted, and is
the exact build Debian published** (`20260803-2559`, Debian 13.6). Honest caveat: Debian does not
GPG-sign these particular checksum files, so the trust anchor is the HTTPS connection to
`cloud.debian.org` — good enough for this project, and worth being able to say precisely.

## 4. cloud-init — the robot that personalises the machine on first boot

**cloud-init** is a small program inside the image that wakes up on every boot and asks: *"does
anyone have configuration for me?"* On first boot, it does everything an installer would have
asked interactively. We answer it with two tiny files:

- **`meta-data`** — identity: an instance-id and the hostname (`iot-host`).
- **`user-data`** — the wishlist. Ours says, in plain terms:
  - create user `sabdark`, in `sudo`, no password needed for sudo;
  - install this SSH public key (a fresh keypair we made just for this VM: `~/.ssh/iot_host_ed25519`);
  - also set a console password (`iot42`) — *fallback only*, usable at the virt-manager console; the VM is on a private NAT network, unreachable from outside the laptop;
  - grow the root filesystem to fill the whole disk (§5, the disk starts at 3 GiB);
  - install `qemu-guest-agent` so libvirt can ask the VM for its IP address;
  - run `apt update` once.

Those two files get packed into a 366 KB ISO — the **seed** — with `cloud-localds`. Think of it as
burning your answers to the installer's questions onto a CD and leaving it in the drive.

### 4.1 How does cloud-init FIND the seed? Twice, on purpose.

1. **Volume label.** The seed ISO's filesystem is labeled `cidata`. cloud-init scans every disk
   for that label. We verified ours: `blkid` reports `LABEL=cidata`.
2. **SMBIOS serial.** We also stamp `ds=nocloud` into the VM's virtual BIOS
   (`--sysinfo smbios,system.serial=ds=nocloud`). That is a second, independent hint.

Either alone is sufficient. We ship both — belt and braces — because a VM that boots with no
datasource is a VM with **no user and no key**, and the only fix is deleting it.

### 4.2 The trap we dodged: `virt-install --cloud-init`

virt-install has a built-in convenience flag that takes your `user-data` and does "all of this
for you". Most tutorials use it. **We must not**, and this is the single most important finding
of the research run:

> `--cloud-init` attaches the seed and the SMBIOS hint **only to the transient boot
> configuration** — the copy of the VM definition that lives while it runs *this once*. The
> **persistent** definition saved to disk gets **neither**. And the ISO it generated is deleted
> before `virt-install` even returns.
>
> Consequence: first boot works. Any reboot or crash **before cloud-init finishes** and the seed
> is gone forever — the VM comes back generic: no user, no key, no password. Unrecoverable;
> rebuild from scratch. During a live demo, that is a disaster with no error message.

Our script builds the seed itself and attaches it **permanently** as a SATA CD-ROM in the saved
definition. Re-seeding later is even possible (`cloud-init clean && reboot`). Cost: one 366 KB
file stays attached. Benefit: the failure mode ceases to exist.

## 5. The creation command, flag by flag

This is the heart of `~/iot-create-vm.sh`. Every flag was dry-run against the real libvirt before
being committed to the script — the generated XML was inspected, not assumed.

```bash
virt-install \
  --connect qemu:///system \                          # the system world (§2) — has the NAT network
  --name iot-host \
  --memory 6144 \                                     # ← was 8192; see below
  --vcpus 6 \                                         # of 16 host threads
  --cpu host-passthrough \                            # give the guest the REAL CPU incl. VT-x → nested KVM
  --disk path=.../iot-host.qcow2,format=qcow2,bus=virtio \
  --disk path=.../iot-host-seed.iso,device=cdrom,bus=sata,readonly=on \   # the seed, permanent (§4.2)
  --import \                                          # boot the existing disk; no installer exists
  --osinfo debian13 \                                 # guarded: falls back to debian12 if unknown (§5.2)
  --sysinfo smbios,system.serial=ds=nocloud \         # datasource hint #2 (§4.1)
  --network network=default,model=virtio \            # NAT: outer VM reaches the internet via the laptop
  --graphics vnc,listen=127.0.0.1 \                   # virt-manager can show its screen, localhost-only
  --console pty,target_type=serial \                  # `virsh console iot-host` works as a text fallback
  --noautoconsole                                     # return to the shell; don't attach
```

### 5.1 The sizing decisions, and why they changed

- **RAM 6144 MB, not 8192.** The laptop has 15 GiB; the desktop eats ~6. Giving the VM 8 GiB
  leaves ~1 GiB of headroom, and the moment the laptop starts swapping, the *nested* VMs inside
  become unusably slow — precisely during a demo. 6 GiB is ample for p1 (two inner VMs: 1024 +
  512 MB) and p3. It can be raised later with the VM powered off.
- **Disk 60 GiB, not 80.** The qcow2 file is *sparse* — it only occupies what is actually
  written, and 60 GiB is a ceiling, not an allocation. But the ceiling matters: if the VM ever
  filled it, it fills the **laptop's** root filesystem (115 GiB free). 60 caps the worst case at
  about half of that. The image ships as a 3 GiB disk; `qemu-img resize` raises the ceiling, and
  cloud-init's `growpart` stretches the filesystem to fill it on first boot.
- **6 vCPUs** — p1 needs little, but p3's k3d cluster and the GitLab bonus are CPU-hungry, and
  vCPUs (unlike RAM) cost nothing when idle.

### 5.2 `--osinfo` — mandatory, and guarded

`virt-install` **refuses to run** without `--osinfo` when importing, and it **aborts** on a name
its database doesn't know. Our laptop's database (June 2025) knows `debian13` — we proved it by
dry-run, and by feeding it a fake `debian99` to see the failure mode. But Ubuntu's *release*
pocket ships a 2023 database that has never heard of Debian 13, so the script checks at runtime
and falls back to `debian12`. The flag only picks sensible virtual-hardware defaults; a
one-version-old profile is harmless, an aborted command is not.

### 5.3 Why the disk lives in `/var/lib/libvirt/images`, not in `~/VMs`

QEMU does not run as root — libvirt drops it to a dedicated user, `libvirt-qemu`. Your home
directory is mode `750`: that user cannot even *traverse* into it. Additionally, AppArmor's
libvirt profile explicitly denies QEMU access to `@{HOME}`. A disk left in `~/VMs` produces a VM
that fails to open its own disk with a cryptic permission error. So the script *copies* the image
into libvirt's own directory and hands ownership to `libvirt-qemu:kvm`. (This is also why the
script needs `sudo`, and why the downloads in `~/VMs` remain untouched originals we can rebuild from.)

## 6. The three network layers — read this twice

After Phase 0 there will be **three** nested network worlds. Knowing which command runs in which
world is half of this project's debugging:

```
Laptop (machine A) ── WiFi 10.32.x.x ── internet
│
│  192.168.122.0/24        ← libvirt's "default" NAT (created in 0.1)
└── outer VM  iot-host     ← gets e.g. 192.168.122.37; A can SSH to it
    │
    │  192.168.56.0/24     ← created LATER by vagrant-libvirt INSIDE iot-host
    ├── smbarkiS   192.168.56.110      (p1/p2 server)
    └── smbarkiSW  192.168.56.111      (p1 worker)
```

The consequence, recorded in CLAUDE.md as a trap: **`192.168.56.110` does not exist from the
laptop's point of view.** Every `curl -H "Host: app1.com" http://192.168.56.110` in the subject —
and live at the defense — runs from a shell **inside `iot-host`**. When our docs say "from the
host", the host is machine B. This is not a limitation we work around; it *is* the topology the
subject's "host virtual machine" implies.

## 7. Facts the research fixed before they hurt us

We ran a six-agent verification pass (plus two adversarial reviewers) over every Phase 0
assumption. Three corrections mattered:

1. **Debian 13 ships Vagrant.** Our notes said *"no vagrant package exists in Debian/Ubuntu
   repos"* — false for Debian 13, which packages `vagrant` 2.3.7 *and* `vagrant-libvirt` 0.12.2.
   So inside the outer VM, installation is one boring `apt install vagrant vagrant-libvirt` — no
   third-party repo, no compiling Ruby extensions (historically the #1 breaker of clean runs).
   And Debian's 0.12.2 **is** the newest upstream vagrant-libvirt; upstream last committed in 2023.
2. **K3s stable moved** to `v1.36.3+k3s1` (Traefik 3.7.8) — pins bumped everywhere *before*
   anything was built with the old one.
3. **The `--cloud-init` transient-XML trap** (§4.2) — found by an adversarial reviewer that was
   explicitly told to try to break the plan. It did. That's the review working as intended.

Also re-verified as still current: k3d v5.9.0, Argo CD v3.4.6 (a 3-day-old v3.5.0 exists; we
stay put and re-check before defense), GitLab CE 19.2.1, `wil42/playground` has exactly tags
`v1` + `v2`.

## 8. The gate — what we check after the VM boots

Run the step:

```bash
sudo bash ~/iot-create-vm.sh
```

Expected: five numbered stages, then up to ~3 minutes of dots while first boot runs `apt update`,
then a box printing the VM's IP. Afterwards **the observations that decide everything**:

| # | Check (from the laptop) | Proves |
|---|---|---|
| 1 | `virsh list --all` → `iot-host  running` | the domain exists and is up |
| 2 | `ssh -i ~/.ssh/iot_host_ed25519 sabdark@<IP> hostname` → `iot-host` | cloud-init made our user + key + hostname |
| 3 | `ssh ... cloud-init status` → `status: done` | first-boot config finished, no errors |
| 4 | `ssh ... ls -l /dev/kvm` → the device exists | **THE GATE: nested virtualisation works** |
| 5 | `ssh ... df -h /` → ~59 GB | growpart stretched the filesystem |

Check 4 is the whole reason Phase 0 exists in this form. If `/dev/kvm` is absent inside the VM,
the p1 machines could only run in software emulation (minutes to boot, unusable to demo), and we
fall back to building on bare metal — a decision we'd make deliberately, note down, and be able
to defend. With `cpu mode=host-passthrough` on a CPU whose `kvm_intel nested=Y`, we expect it to
pass.

## 9. What could go wrong

| Symptom | Cause | Fix |
|---|---|---|
| `ERROR Unknown OS name 'debian13'` | old osinfo database | can't happen — script auto-falls-back to `debian12` |
| Script exits: "a domain named iot-host already exists" | a previous half-attempt | `sudo virsh destroy iot-host; sudo virsh undefine iot-host --remove-all-storage`, re-run |
| No IP after 5 min | first boot still in apt, or network issue | `sudo virsh console iot-host` (login `sabdark`/`iot42`), check `cloud-init status --long` |
| SSH refused but ping works | cloud-init not finished | wait; check via console |
| SSH asks for a password | wrong key file | use `-i ~/.ssh/iot_host_ed25519` explicitly |
| VM boots, `/dev/kvm` missing inside | nested virt not passed through | the gate fails → we stop, discuss, fall back per plan |

## 10. New glossary entries

| Term | Meaning |
|---|---|
| Cloud image | A disk with the OS pre-installed, personalised on first boot instead of at install time. |
| cloud-init | The program inside the image that does that personalisation. |
| NoCloud | cloud-init's "my config is on a local disk, not a cloud API" mode. |
| Seed / config drive | The tiny ISO carrying `user-data` + `meta-data`, labeled `cidata`. |
| `user-data` / `meta-data` | The wishlist (users, keys, packages…) / the identity (hostname, instance-id). |
| SMBIOS | The virtual BIOS's data area; we stamp `ds=nocloud` into its serial as a datasource hint. |
| qcow2 | QEMU's disk format: sparse (grows with use) and resizable. |
| Sparse file | A file whose unwritten parts occupy no real disk space. |
| `host-passthrough` | "Give the guest my real CPU's features" — the door to nested KVM. |
| Transient vs persistent XML | A VM's live definition for *this run* vs the saved one it boots from next time. The `--cloud-init` trap lives in this gap. |
| qemu-guest-agent | A helper inside the guest letting libvirt ask it things — like its IP (`virsh domifaddr`). |
| `qemu:///system` vs `qemu:///session` | libvirt's two worlds: the root-managed one with networking vs your private unprivileged one. |

## 11. Test yourself

1. Why is the `nocloud` image the wrong choice, despite the name? *(§3.1)*
2. cloud-init finds our seed two ways — name both. Why ship both? *(§4.1)*
3. Explain the `--cloud-init` trap in one sentence: what is lost, and when does the loss bite? *(§4.2)*
4. Why 6144 MB of RAM and not 8192, when more is "better"? *(§5.1)*
5. The disk says 60 GiB but the file is ~330 MB. Reconcile that. *(§5.1)*
6. Why can't the VM's disk live in your home directory? Two independent reasons. *(§5.3)*
7. An evaluator curls `192.168.56.110` from your laptop and gets nothing. Is p2 broken? *(§6)*
8. What exactly does check 4 (`/dev/kvm` inside) decide, and what is the fallback if it fails? *(§8)*

---

**Next after the gate passes:** Phase 0.4 — inside `iot-host`, install the toolchain with plain
`apt` (`vagrant`, `vagrant-libvirt`, `qemu-system-x86`, `libvirt-daemon-system`) plus Docker CE,
pre-cache the `debian/trixie64` Vagrant box, and then finally: **p1 slice 1.1**, the five-line
Vagrantfile from [EXPLANATION.md §7](EXPLANATION.md).
