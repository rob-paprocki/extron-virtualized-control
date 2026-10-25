#!/usr/bin/env bash
# fetch-vca-image.sh -- pull the VCA qcow2 from private R2 with a plain curl, and
# (optionally) convert it to another hypervisor's disk format. Zero secrets baked in:
# the URL is a presigned link minted by scripts/r2-publish-image.sh.
#
#   ./vm/fetch-vca-image.sh                       # -> vca-portable-1.02.qcow2
#   ./vm/fetch-vca-image.sh --out /path/img.qcow2 # custom output path
#   ./vm/fetch-vca-image.sh --convert vmdk        # fetch + make <img>.vmdk (VMware)
#   ./vm/fetch-vca-image.sh --convert raw         # fetch + make <img>.raw  (TrueNAS zvol)
#   ./vm/fetch-vca-image.sh --convert vhdx        # fetch + make <img>.vhdx (Hyper-V)
#   # to a remote target over ssh (URL + checksum travel as env, not baked in):
#   VCA_IMAGE_URL="$(cat ~/.vca_image_url)" VCA_IMAGE_SHA256="$(cat ~/.vca_image_url.sha256)" \
#     ssh target 'bash -s' < vm/fetch-vca-image.sh
#
# URL source  (first found): $VCA_IMAGE_URL, else ~/.vca_image_url
# sha256      (first found): $VCA_IMAGE_SHA256, else ~/.vca_image_url.sha256 (optional)
set -euo pipefail

OUT=vca-portable-1.02.qcow2
CONVERT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --out)     OUT=$2; shift 2;;
    --convert) CONVERT=$2; shift 2;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \?//'; exit 0;;
    --*)       echo "unknown option: $1"; exit 1;;
    *)         OUT=$1; shift;;   # legacy positional output path
  esac
done

# Public image (default). Override with $VCA_IMAGE_URL or ~/.vca_image_url (e.g. a private
# presigned URL) if you host your own.
DEFAULT_URL="https://vca-images.rpaprocki.com/vca-portable-1.02.qcow2"
DEFAULT_SHA="abfab491a186dafbb0078119d80851f947cb5281c537f4b961313570620dd3d2"
URL=${VCA_IMAGE_URL:-}
[ -z "$URL" ] && [ -f "$HOME/.vca_image_url" ] && URL=$(cat "$HOME/.vca_image_url")
[ -z "$URL" ] && URL="$DEFAULT_URL"

echo ">>> fetching image -> $OUT"
curl -fSL --retry 3 --retry-delay 5 "$URL" -o "$OUT"

SHA=${VCA_IMAGE_SHA256:-}
[ -z "$SHA" ] && [ -f "$HOME/.vca_image_url.sha256" ] && SHA=$(cat "$HOME/.vca_image_url.sha256")
[ -z "$SHA" ] && [ "$URL" = "$DEFAULT_URL" ] && SHA="$DEFAULT_SHA"
if [ -n "$SHA" ]; then
  echo ">>> verifying sha256"
  echo "$SHA  $OUT" | sha256sum -c - || { echo "CHECKSUM MISMATCH"; exit 1; }
else
  echo "(no sha256 provided; skipping integrity check)"
fi

if [ -n "$CONVERT" ]; then
  command -v qemu-img >/dev/null || { echo "need qemu-img (install qemu-utils) to --convert"; exit 1; }
  base=${OUT%.qcow2}
  case "$CONVERT" in
    vmdk) echo ">>> converting -> $base.vmdk (VMware)";  qemu-img convert -p -O vmdk -o subformat=streamOptimized "$OUT" "$base.vmdk";;
    raw)  echo ">>> converting -> $base.raw (TrueNAS/bhyve)"; qemu-img convert -p -O raw  "$OUT" "$base.raw";;
    vhdx) echo ">>> converting -> $base.vhdx (Hyper-V)"; qemu-img convert -p -O vhdx "$OUT" "$base.vhdx";;
    *) echo "unknown --convert format: $CONVERT (vmdk|raw|vhdx)"; exit 1;;
  esac
  echo ">>> converted: $base.$CONVERT"
fi
echo ">>> done: $OUT${CONVERT:+ (+ $base.$CONVERT)}"
