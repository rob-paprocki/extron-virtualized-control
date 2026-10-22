#!/usr/bin/env bash
# run-vca-lan.sh — boot the bridged (LAN) VCA on tap0/br0 under TCG.
# The guest eth0 and every VCP macvlan child pull real DHCP addresses on the LAN.
# Prereq: br0 (eth0 enslaved) + tap0 up on br0 (see bridge setup).
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
D=${VCA_DIR:-$HERE}                       # dir for image + logs/vars/pid (override with VCA_DIR)
IMG=${1:-$D/vca-portable-1.02.qcow2}
# auto-fetch from private R2 if the image isn't present (needs $VCA_IMAGE_URL or ~/.vca_image_url)
if [ ! -f "$IMG" ]; then
  if [ -x "$HERE/fetch-vca-image.sh" ] && { [ -n "${VCA_IMAGE_URL:-}" ] || [ -f "$HOME/.vca_image_url" ]; }; then
    echo "image not found; fetching from R2 -> $IMG"
    "$HERE/fetch-vca-image.sh" --out "$IMG"
  else
    echo "no image at $IMG and no R2 URL (\$VCA_IMAGE_URL / ~/.vca_image_url). Pass a path or publish to R2."; exit 1
  fi
fi
NAME=$(basename "$IMG" .qcow2)
MEM=${VCA_MEM:-10G}
GUESTMAC=${VCA_MAC:-02:61:8a:ec:a5:60}   # match randomized host identity (vca_config.json ethaddr)
LOG=$D/$NAME-serial.log
VARS=$D/$NAME-vars.fd
[ -f "$VARS" ] || cp /usr/share/OVMF/OVMF_VARS_4M.fd "$VARS"
: > "$LOG"
exec qemu-system-x86_64 \
  -name "$NAME" \
  -machine q35 -accel tcg -cpu max -m "$MEM" -smp 4 \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd \
  -drive if=pflash,format=raw,file="$VARS" \
  -drive file="$IMG",if=virtio,format=qcow2 \
  -netdev tap,id=n0,ifname=tap0,script=no,downscript=no \
  -device virtio-net-pci,netdev=n0,mac="$GUESTMAC" \
  -display none -serial file:"$LOG" \
  -monitor telnet:127.0.0.1:4445,server,nowait \
  -pidfile "$D/$NAME.pid"
