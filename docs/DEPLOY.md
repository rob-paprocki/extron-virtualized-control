# Deploying the VCA image

Step-by-step instructions for spinning up the virtual VCA-100 on each hypervisor. The disk
image isn't in git (it's large), but it's published for download, so every deploy is the same two
moves: **get the image** (a plain `curl`), then **import/boot it** on your platform.

The image self-personalizes on first boot (unique serial + MACs), so you can deploy the same file
as many times as you want without collisions. See [FIRSTBOOT_IDENTITY.md](FIRSTBOOT_IDENTITY.md).

---

## Get the image

The image is published at:

    https://vca-images.rpaprocki.com/vca-portable-1.02.qcow2
    sha256  abfab491a186dafbb0078119d80851f947cb5281c537f4b961313570620dd3d2

`vm/fetch-vca-image.sh` downloads it and verifies that checksum with zero config:

```bash
./vm/fetch-vca-image.sh                     # -> vca-portable-1.02.qcow2
./vm/fetch-vca-image.sh --convert vmdk      # fetch + make .vmdk (VMware)
./vm/fetch-vca-image.sh --convert raw       # fetch + make .raw  (TrueNAS / bhyve)
./vm/fetch-vca-image.sh --convert vhdx      # fetch + make .vhdx (Hyper-V)
```

`run-vca-lan.sh` and `vca-proxmox.sh` call this automatically when the image is absent, so on those
two you can skip the explicit fetch. Or just `curl` the URL directly:

```bash
curl -fL https://vca-images.rpaprocki.com/vca-portable-1.02.qcow2 -o vca-portable-1.02.qcow2
```

**Hosting your own image instead (optional).** To serve a different image from your own private
Cloudflare R2 bucket, point the tooling at it (nothing is hardcoded):

1. `cp scripts/r2-creds.example ~/.r2_creds` (fill in account id / keys / bucket, `chmod 600`).
2. `sudo apt install -y python3-boto3 && ./scripts/r2-publish-image.sh <image.qcow2>` — uploads it
   and writes a presigned URL to `~/.vca_image_url` (+ `.sha256`), which the fetch tooling uses in
   preference to the default. Presigned URLs expire after 7 days; re-mint with
   `python3 scripts/r2.py presign <key> 604800 > ~/.vca_image_url`. Set `$VCA_IMAGE_URL` to override
   per-command.

---

## Per-platform

Every platform needs the same two things: **UEFI/OVMF firmware**, and a NIC/switch that **allows
multiple MACs** (each VCP presents its own MAC via macvlan). Use hardware virtualization (KVM and
friends) where you can. Pure software emulation (TCG) is ~10× slower.

### Plain QEMU / KVM (Linux, incl. this Kali)
```bash
# bridged on br0 (VCPs get real DHCP leases); auto-fetches if the image is missing:
VCA_MEM=10G VCA_MAC=02:... ./vm/run-vca-lan.sh
```
Prereqs: a bridge `br0` with your uplink enslaved and a `tap0` on it. No `/dev/kvm`? It still runs
under TCG, just slowly.

### Proxmox VE
On the Proxmox host, drop the presigned URL in `~/.vca_image_url` (and `.sha256`), then:
```bash
bash vca-proxmox.sh
```
It curls the image from R2, verifies the checksum, and builds a Q35/OVMF VM. Leave the NIC firewall
**off** so VCP MACs pass. For a second AV-LAN plane, answer yes to the dual-NIC prompt.

### VMware (Workstation / Fusion / ESXi)
```bash
./vm/fetch-vca-image.sh --convert vmdk     # -> vca-portable-1.02.vmdk
```
New VM → "I'll install the OS later" → Linux / Debian 10 64-bit → **UEFI** firmware. Remove the
default disk, "Add existing disk" → the `.vmdk` (SCSI). On the portgroup/vSwitch set **Promiscuous
mode = Accept, MAC address changes = Accept, Forged transmits = Accept**.

### UTM (macOS)
```bash
./vm/fetch-vca-image.sh                     # on the Mac (needs curl)
```
New VM → **Emulate** on Apple Silicon (x86-64 emulation, slow) or **Virtualize** on Intel (fast) →
Other → skip ISO → UEFI boot. Import `vca-portable-1.02.qcow2` directly (UTM reads qcow2). Use
"Bridged" networking for real LAN presence.

### TrueNAS
```bash
./vm/fetch-vca-image.sh --convert raw       # -> vca-portable-1.02.raw
```
- **SCALE (KVM):** add a VM (UEFI), create a Zvol ≥ image size, write the `.raw` to the zvol device
  (`qemu-img`/`dd`), or import the qcow2 via the VM wizard. Bridge to your LAN; don't filter MACs.
- **CORE (bhyve):** create a VM with a UEFI bootrom and attach the `.raw` as a disk device.

### Hyper-V (Windows)
```bash
./vm/fetch-vca-image.sh --convert vhdx      # -> vca-portable-1.02.vhdx
```
New VM → **Generation 2** → disable **Secure Boot** → attach the `.vhdx` → boot. On the VM's NIC
enable **MAC address spoofing** so the VCP MACs pass.

---

## After it boots

- **Root shell:** `ssh -p 2222 root@<ip>`, password = the unit's **serial** (set on first boot;
  read it from the serial console or the admin UI). No SSH key is baked in.
- **Admin / web UI:** factory-fresh, no password stored. Set your own on first use, like a new unit.
- **VCPs:** five come up by default, each with its own LAN MAC. Give the VM ≥8 GB RAM (more RAM =
  more VCPs).

Details: [FIRSTBOOT_IDENTITY.md](FIRSTBOOT_IDENTITY.md) (identity + credentials).
