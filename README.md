# extron-virtualized-control

Scripts and docs for running a portable Extron VCA-100 Virtual Control Appliance image on QEMU/KVM, Proxmox, VMware, UTM, TrueNAS or Hyper-V. The VCA-100 hosts Virtual Control Processors (VCPs); each runs in its own container with its own serial and MAC, and the image starts five of them.

[![Release](https://img.shields.io/github/v/release/rob-paprocki/extron-virtualized-control)](https://github.com/rob-paprocki/extron-virtualized-control/releases)
[![CI](https://github.com/rob-paprocki/extron-virtualized-control/actions/workflows/ci.yml/badge.svg)](https://github.com/rob-paprocki/extron-virtualized-control/actions/workflows/ci.yml)
[![License: Apache-2.0](https://img.shields.io/github/license/rob-paprocki/extron-virtualized-control)](LICENSE)
[![Last commit](https://img.shields.io/github/last-commit/rob-paprocki/extron-virtualized-control)](https://github.com/rob-paprocki/extron-virtualized-control/commits/main)

> [!NOTE]
> For appliances you own. Extron's firmware and software remain Extron's property and aren't distributed here. The disk image is hosted separately and fetched with `curl`.

## Why

- One image covers every platform. Fetch it once, then convert it to `vmdk`, `raw` or `vhdx` if your platform needs that.
- Each clone makes its own host serial and MAC addresses on first boot, so the same file deploys many times without collisions.
- A Proxmox installer script builds the VM, and a QEMU launcher boots the image bridged onto your LAN.
- No builder key or password is baked into the image.

**Scope:** this repo is tooling and docs. It has no Extron firmware, source or decrypted images, and the qcow2 is hosted elsewhere.

## Requirements

| Item | Needed |
|---|---|
| Host | Linux with QEMU/KVM, or Proxmox VE, VMware, UTM, TrueNAS or Hyper-V |
| Firmware | UEFI/OVMF |
| Network | A bridge or vSwitch that allows multiple MACs (promiscuous mode, MAC changes and forged transmits accepted) |
| Tools | `bash`, `curl`, `qemu-img` for format conversion |
| Memory | 10 GB for the default launcher settings |

Hardware virtualization is strongly recommended. Pure software emulation (TCG) runs about ten times slower.

## Install

```bash
git clone https://github.com/rob-paprocki/extron-virtualized-control.git && cd extron-virtualized-control
./vm/fetch-vca-image.sh      # downloads vca-portable-1.02.qcow2 and verifies its checksum
```

The fetch script needs no configuration. It stops with `CHECKSUM MISMATCH` if the download doesn't match the published checksum.

## Quick start

Boot the image bridged onto your LAN with QEMU (needs a bridge `br0` and a `tap0` on it):

```bash
VCA_MEM=10G ./vm/run-vca-lan.sh
```

Other platforms:

```bash
./vm/fetch-vca-image.sh --convert vmdk   # VMware
./vm/fetch-vca-image.sh --convert raw    # TrueNAS, bhyve
./vm/fetch-vca-image.sh --convert vhdx   # Hyper-V
bash scripts/vca-proxmox.sh              # Proxmox VE: creates the VM for you
```

The full walkthrough for each hypervisor is in [docs/DEPLOY.md](docs/DEPLOY.md).

## Tools

| Tool | What it does |
|---|---|
| `vm/fetch-vca-image.sh` | Pulls the image with a plain `curl`; `--convert` makes a vmdk, raw or vhdx copy |
| `vm/run-vca-lan.sh` | Boots the image bridged under QEMU; fetches it first if it's missing |
| `scripts/vca-proxmox.sh` | Proxmox installer in the community-scripts style; fetches, verifies and builds the VM |
| `scripts/vca-gen-identity.sh` | Writes a unique identity (serials and locally administered MACs) into an image |
| `scripts/r2-publish-image.sh` | Uploads an image to a private Cloudflare R2 bucket and prints a presigned URL and sha256 |
| `firstboot/` | The hook and generator baked into the image that create a unique identity on first boot |

## Configuration

| Variable | Default | Purpose |
|---|---|---|
| `VCA_MEM` | `10G` | Guest memory for `run-vca-lan.sh` |
| `VCA_MAC` | `00:00:5E:00:53:20` | Guest MAC for `run-vca-lan.sh`; set your own for a real LAN |
| `VCA_DIR` | the script's folder | Where `run-vca-lan.sh` keeps the image, logs and UEFI variables |
| `VCA_IMAGE_URL` | the published image | Fetch from a different URL |
| `VCA_IMAGE_SHA256` | checksum of the published image | Checksum to verify a different image; without one, a custom URL isn't verified |

<details>
<summary>Notes</summary>

- Each deployment generates a host serial, `02:` MACs and a per-VCP pool on first boot. See [docs/FIRSTBOOT_IDENTITY.md](docs/FIRSTBOOT_IDENTITY.md).
- A root shell listens on port 2222. Its password is the unit serial, set on first boot and shown on the serial console and the admin UI. The admin web UI starts factory-fresh, so set your own password on first use.
- Each VCP presents its own MAC through macvlan, so the bridge or vSwitch must allow several MACs.
- To serve an image from your own private R2 bucket, see [docs/DEPLOY.md](docs/DEPLOY.md).

- `vm/fetch-vca-image.sh` and the Proxmox script also read `~/.vca_image_url` and `~/.vca_image_url.sha256` when `VCA_IMAGE_URL` and `VCA_IMAGE_SHA256` are unset. R2 credentials (only needed to host your own image) go in `~/.r2_creds`, copied from `scripts/r2-creds.example`; set `R2_CREDS` to use another path.
- `scripts/vca-proxmox.sh` prompts for VM ID, name, cores, RAM, storage, bridge, a second NIC, identity randomization and the image path or URL.

</details>

## Help

Questions and bug reports go in [Issues](https://github.com/rob-paprocki/extron-virtualized-control/issues).

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

## License

[Apache-2.0](LICENSE) (c) 2026 Rob Paprocki.
