# Deploying the VCA image

These are the steps for running the virtual VCA-100 on each hypervisor. The disk image isn't in git
because it's large, but it's published for download. Every deploy is the same two moves: get the
image with a plain `curl`, then import and boot it on your platform.

The image gives itself a unique serial and unique MACs on first boot, so you can deploy the same
file as many times as you like without collisions. See [FIRSTBOOT_IDENTITY.md](FIRSTBOOT_IDENTITY.md).

---

## Get the image

The image is published at:

    https://vca-images.rpaprocki.com/vca-portable-1.02.qcow2
    sha256  abfab491a186dafbb0078119d80851f947cb5281c537f4b961313570620dd3d2

`vm/fetch-vca-image.sh` downloads it and checks that checksum, with no configuration:

```bash
./vm/fetch-vca-image.sh                     # downloads vca-portable-1.02.qcow2
./vm/fetch-vca-image.sh --convert vmdk      # also makes a .vmdk (VMware)
./vm/fetch-vca-image.sh --convert raw       # also makes a .raw (TrueNAS, bhyve)
./vm/fetch-vca-image.sh --convert vhdx      # also makes a .vhdx (Hyper-V)
```

`run-vca-lan.sh` calls the fetch script itself when the image is missing, and `vca-proxmox.sh`
downloads the image on its own, so on those two you can skip this step. You can also fetch the file
directly:

```bash
curl -fL https://vca-images.rpaprocki.com/vca-portable-1.02.qcow2 -o vca-portable-1.02.qcow2
```

### Hosting your own image (optional)

The tooling downloads the default image above unless you point it elsewhere. To serve a different image
from your own private Cloudflare R2 bucket, set `VCA_IMAGE_URL` or write a URL to `~/.vca_image_url`.

1. Copy the example credentials file, fill in the account ID, keys and bucket, and lock it down:
   `cp scripts/r2-creds.example ~/.r2_creds && chmod 600 ~/.r2_creds`.
2. Install `python3-boto3`, then upload with `./scripts/r2-publish-image.sh <image.qcow2>`. It writes a
   presigned URL to `~/.vca_image_url` (and the checksum to `~/.vca_image_url.sha256`), which the
   fetch tooling uses in preference to the default.
3. Presigned URLs expire after 7 days. To mint a new one, run
   `python3 scripts/r2.py presign <key> 604800 > ~/.vca_image_url`. Set `VCA_IMAGE_URL` to override the
   URL for a single command.

---

## Per platform

Every platform needs UEFI/OVMF firmware and a NIC or switch that allows multiple MACs, because each
VCP presents its own MAC through macvlan. Use hardware virtualization (KVM and friends) where you
can. Pure software emulation (TCG) is about ten times slower.

### Plain QEMU / KVM (Linux)

```bash
# Bridged on br0, so VCPs get real DHCP leases. Fetches the image if it's missing.
VCA_MEM=10G VCA_MAC=00:00:5E:00:53:20 ./vm/run-vca-lan.sh
```

You need a bridge `br0` with your uplink enslaved and a `tap0` on it. Without `/dev/kvm` it still
runs under TCG, just slowly.

### Proxmox VE

Run the script as root on the Proxmox host. It offers the default public image URL as the answer to
its image prompt. To use a different image, put its URL in `~/.vca_image_url` and its checksum in
`~/.vca_image_url.sha256` first, or pass a path or URL as the first argument.

```bash
bash scripts/vca-proxmox.sh
```

It downloads the image, checks the sha256 if you supplied one, and builds a Q35/OVMF VM. Leave the
NIC firewall off so the VCP MACs pass. For a second AV-LAN plane, answer yes to the dual-NIC prompt.

### VMware (Workstation, Fusion, ESXi)

```bash
./vm/fetch-vca-image.sh --convert vmdk     # makes vca-portable-1.02.vmdk
```

Create a VM with "I'll install the OS later", pick Linux / Debian 10 64-bit, and set the firmware to
UEFI. Remove the default disk and add the `.vmdk` as an existing disk (SCSI). On the portgroup or
vSwitch, set Promiscuous mode, MAC address changes and Forged transmits to Accept.

### UTM (macOS)

```bash
./vm/fetch-vca-image.sh                     # run on the Mac; needs curl
```

Create a new VM, choose Emulate on Apple Silicon (x86-64 emulation, slow) or Virtualize on Intel
(fast), pick Other, skip the ISO and boot with UEFI. Import `vca-portable-1.02.qcow2` directly, since
UTM reads qcow2. Use Bridged networking so the VM shows up on your LAN.

### TrueNAS

```bash
./vm/fetch-vca-image.sh --convert raw       # makes vca-portable-1.02.raw
```

- SCALE (KVM): add a UEFI VM and create a zvol at least as large as the image. Write the `.raw` to
  the zvol device with `qemu-img` or `dd`, or import the qcow2 through the VM wizard. Bridge to your
  LAN and don't filter MACs.
- CORE (bhyve): create a VM with a UEFI bootrom and attach the `.raw` as a disk device.

### Hyper-V (Windows)

```bash
./vm/fetch-vca-image.sh --convert vhdx      # makes vca-portable-1.02.vhdx
```

Create a Generation 2 VM, turn off Secure Boot, attach the `.vhdx` and boot. On the VM's NIC, enable
MAC address spoofing so the VCP MACs pass.

---

## After it boots

- Root shell: `ssh -p 2222 root@<ip>`. The password is the unit's serial, set on first boot. Read it
  from the serial console or the admin UI. No SSH key is baked in.
- Admin web UI: starts factory-fresh with no password stored. Set your own on first use, like a new
  unit.
- VCPs: five come up by default, each with its own LAN MAC. Give the VM at least 8 GB of RAM; more
  RAM means more VCPs.

For how identity and credentials work, see [FIRSTBOOT_IDENTITY.md](FIRSTBOOT_IDENTITY.md).
