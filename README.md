# Extron VCA-100 Virtualization — deployment tooling

Tooling to deploy a portable Extron **VCA-100** appliance image on commodity hypervisors
(QEMU/KVM, Proxmox, VMware, UTM, TrueNAS, Hyper-V). The image is published separately and pulled
with `curl` (see [docs/DEPLOY.md](docs/DEPLOY.md)); this repo is the tooling and docs, with no
reverse-engineering material.

> For appliances you own. Extron's firmware and software remain Extron's property and are not
> distributed in this repository.

The VCA-100 is Extron's Virtual Control Appliance. It hosts Virtual Control Processors (VCPs). Each
VCP runs in its own container with its own serial and MAC address, and a deployment of this image
starts five of them.

## Prerequisites
- A hypervisor from the list above, with UEFI (OVMF) firmware. Hardware virtualization is
  recommended. Pure software emulation (TCG) is about 10 times slower.
- 8 GB of RAM or more for the VM. More RAM means more VCPs.
- A NIC and switch that allow multiple MACs, because each VCP presents its own MAC through macvlan.
- `bash` and `curl` to fetch the image, plus `qemu-img` (from `qemu-utils`) if you use `--convert`.
- For `vm/run-vca-lan.sh`: `qemu-system-x86_64`, the OVMF files under `/usr/share/OVMF`, and a
  bridge `br0` with your uplink enslaved and a `tap0` on it.
- For `scripts/vca-proxmox.sh`: root on a Proxmox VE host.
- To host your own image: a Cloudflare R2 bucket and `python3-boto3`.

## Layout
- `scripts/` — image hosting (private Cloudflare R2) + the Proxmox installer + identity helper
- `vm/` — QEMU launcher + the R2 `curl` fetch
- `firstboot/` — the self-personalization hook + generator baked into a deployed image
- `docs/` — the **[deployment guide](docs/DEPLOY.md)** and first-boot identity notes

## Quick start
Full walkthrough in **[docs/DEPLOY.md](docs/DEPLOY.md)**. In short:

1. Get the image (published at `https://vca-images.rpaprocki.com/vca-portable-1.02.qcow2`):
   `./vm/fetch-vca-image.sh` downloads and checksum-verifies it with no config.
2. Deploy per hypervisor: add `--convert vmdk|raw|vhdx` for VMware/TrueNAS/Hyper-V, or use
   `vm/run-vca-lan.sh` / `scripts/vca-proxmox.sh`, which fetch automatically when the image is absent.

To host your own image privately instead, see [docs/DEPLOY.md](docs/DEPLOY.md) (`scripts/r2-publish-image.sh`).

## Key tools
| tool | what it does |
|---|---|
| `scripts/r2-publish-image.sh` | upload the image to a **private** R2 bucket, mint a presigned URL + sha256 |
| `vm/fetch-vca-image.sh` | pull the image with a plain `curl` (optional `--convert` to vmdk/raw/vhdx) |
| `vm/run-vca-lan.sh` | boot the image **bridged** under QEMU; auto-fetches from R2 if absent |
| `scripts/vca-proxmox.sh` | community-scripts-style Proxmox installer; fetches the image (verified if you supply a sha256) and builds the VM |
| `scripts/vca-gen-identity.sh` | write a unique identity (serials + locally-administered `02:` MACs) into an image |
| `firstboot/` | on first boot, self-generate a unique identity so no two clones collide |

## Where settings live
- Image URL: the `$VCA_IMAGE_URL` environment variable, else the file `~/.vca_image_url`, else the
  built-in public URL. `vm/fetch-vca-image.sh` checks them in that order, and `scripts/vca-proxmox.sh`
  uses the same sources as the default for its image prompt.
- Image checksum: `$VCA_IMAGE_SHA256`, else the file `~/.vca_image_url.sha256`. The built-in URL has
  a built-in checksum in the fetch script. The Proxmox script checks a sha256 only if one of these is set.
- R2 credentials: `~/.r2_creds`, copied from `scripts/r2-creds.example`. Set `$R2_CREDS` to use
  another path. You only need this to host your own image.
- `vm/run-vca-lan.sh`: `VCA_MEM` (default `10G`), `VCA_MAC` (guest MAC, default `02:61:8a:ec:a5:60`)
  and `VCA_DIR` (where the image, logs and UEFI vars file live, default the `vm/` directory). The
  image path is the first argument.
- `scripts/vca-proxmox.sh`: whiptail prompts for VM ID, name, cores, RAM, storage, bridge, a second
  NIC, identity randomization and the image path or URL. The image can also be the first argument.
- `vm/fetch-vca-image.sh`: `--out <path>` and `--convert vmdk|raw|vhdx`.
- `scripts/vca-gen-identity.sh`: `--pool`, `--host-mac` and `--prefix`. Inside a deployed image the
  identity lives in `/opt/extron_config` (see [docs/FIRSTBOOT_IDENTITY.md](docs/FIRSTBOOT_IDENTITY.md)).
- Each script's header comment lists its options.

## Notes
- **Identity:** each deployment self-generates a unique host serial + `02:` MACs + per-VCP pool on
  first boot, so the same image deploys many times without collisions. See
  [docs/FIRSTBOOT_IDENTITY.md](docs/FIRSTBOOT_IDENTITY.md).
- **Access:** root shell on port 2222 (password = the unit serial, self-set on first boot and shown
  on the serial console / admin UI); admin/web UI is factory-fresh (set your own). No builder key or
  password is baked into the image.
- **Networking:** each VCP presents its own MAC via macvlan, so the vSwitch/bridge must allow
  multiple MACs (promiscuous / MAC-spoofing / forged-transmits).
- **Legal:** intended for appliances you own.
