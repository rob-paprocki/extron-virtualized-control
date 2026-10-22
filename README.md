# Extron VCA-100 Virtualization — deployment tooling

Tooling to deploy a portable Extron **VCA-100** appliance image on commodity hypervisors
(QEMU/KVM, Proxmox, VMware, UTM, TrueNAS, Hyper-V). The image is published separately and pulled
with `curl` (see [docs/DEPLOY.md](docs/DEPLOY.md)); this repo is the tooling and docs, with no
reverse-engineering material.

> For appliances you own. Extron's firmware and software remain Extron's property and are not
> distributed in this repository.

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
| `scripts/vca-proxmox.sh` | community-scripts-style Proxmox installer; fetches + verifies + builds the VM |
| `scripts/vca-gen-identity.sh` | write a unique identity (serials + locally-administered `02:` MACs) into an image |
| `firstboot/` | on first boot, self-generate a unique identity so no two clones collide |

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
