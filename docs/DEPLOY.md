# Deploying the VCA image

Step-by-step instructions for spinning up the virtual VCA-100 on each hypervisor. The disk
image is **not** in this repo (it's Extron's proprietary firmware, and it's large). You host it
yourself in a private Cloudflare R2 bucket and pull it with `curl`. Every deploy is the same two
moves: **get the image**, then **import/boot it** on your platform.

The image self-personalizes on first boot (unique serial + MACs), so you can deploy the same file
as many times as you want without collisions. See [FIRSTBOOT_IDENTITY.md](FIRSTBOOT_IDENTITY.md).

---

## One-time: host the image in private R2

Do this once, on a trusted machine that has the qcow2 (e.g. the box you built it on).

1. **Enable R2** in the Cloudflare dashboard (it asks for a payment method even for the free
   10 GB tier) and create a bucket, e.g. `vca-images`.
2. **Make an R2 API token:** dashboard → R2 → *Manage R2 API Tokens* → *Create* → "Object Read &
   Write", scoped to that bucket. Note the **Access Key ID**, **Secret**, and your **account ID**.
3. **Fill the creds file** and lock it down:
   ```bash
   cp scripts/r2-creds.example ~/.r2_creds
   chmod 600 ~/.r2_creds
   # edit ~/.r2_creds: account id, access key, secret, R2_BUCKET=vca-images
   ```
4. **Publish** (uploads the image, mints a presigned URL + checksum):
   ```bash
   sudo apt install -y python3-boto3        # Debian/Kali; or: pip install boto3
   ./scripts/r2-publish-image.sh /path/to/vca-portable-1.02.qcow2
   ```
   This writes the presigned URL to `~/.vca_image_url` and the sha256 to
   `~/.vca_image_url.sha256`. Both are gitignored; nothing secret enters the repo.

> **Presigned URLs expire after 7 days** (an S3/R2 limit). To refresh without re-uploading:
> ```bash
> set -a; . ~/.r2_creds; set +a
> python3 scripts/r2.py presign vca-portable-1.02.qcow2 604800 > ~/.vca_image_url
> ```
> Want a permanent URL instead? Put the bucket behind an R2 custom domain + Cloudflare Access
> service token and `curl` it with two headers. Ask and we'll wire it up.

---

## Get the image on the deploy host

Copy `~/.vca_image_url` (and `.sha256`) to the machine doing the deploy, or export the URL:

```bash
# simplest — reads ~/.vca_image_url, verifies the checksum:
./vm/fetch-vca-image.sh

# fetch + convert to another disk format in one step:
./vm/fetch-vca-image.sh --convert vmdk     # VMware
./vm/fetch-vca-image.sh --convert raw      # TrueNAS / bhyve
./vm/fetch-vca-image.sh --convert vhdx     # Hyper-V

# from your workstation straight into a remote box over ssh (no file copy):
VCA_IMAGE_URL="$(cat ~/.vca_image_url)" VCA_IMAGE_SHA256="$(cat ~/.vca_image_url.sha256)" \
  ssh target 'bash -s' < vm/fetch-vca-image.sh
```

`run-vca-lan.sh` and `vca-proxmox.sh` call this automatically when the image isn't already present,
so on those two you can skip the explicit fetch.

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
