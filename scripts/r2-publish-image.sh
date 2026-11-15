#!/usr/bin/env bash
# r2-publish-image.sh -- upload the VCA qcow2 to a PRIVATE Cloudflare R2 bucket and
# mint a presigned GET URL for the fetch script. Run on a trusted box (your creds).
#
#   cp scripts/r2-creds.example ~/.r2_creds   # fill in, chmod 600
#   ./scripts/r2-publish-image.sh /path/to/vca-portable-1.02.qcow2 [url_ttl_seconds]
#
# Writes the presigned URL to ~/.vca_image_url (gitignored) and prints the sha256 so
# the fetch side can verify. The image itself is NEVER committed; only private R2 holds it.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
CREDS=${R2_CREDS:-$HOME/.r2_creds}
IMG=${1:?usage: r2-publish-image.sh <qcow2> [ttl_seconds]}
TTL=${2:-604800}   # default 7 days (R2/S3 presign hard cap)

[ -f "$CREDS" ] || { echo "no creds at $CREDS (copy scripts/r2-creds.example)"; exit 1; }
[ -f "$IMG" ]   || { echo "no image at $IMG"; exit 1; }
set -a; . "$CREDS"; set +a
KEY=${R2_KEY:-$(basename "$IMG")}

echo ">>> sha256 (for fetch-side verification)"
SHA=$(sha256sum "$IMG" | awk '{print $1}'); echo "  $SHA  $KEY"

echo ">>> uploading $(du -h "$IMG" | cut -f1) to s3://$R2_BUCKET/$KEY (multipart)"
python3 "$HERE/r2.py" put "$IMG" "$KEY"

echo ">>> minting presigned GET URL (ttl ${TTL}s)"
URL=$(python3 "$HERE/r2.py" presign "$KEY" "$TTL")
umask 077; printf '%s\n' "$URL" > "$HOME/.vca_image_url"
printf '%s\n' "$SHA" > "$HOME/.vca_image_url.sha256"
echo "  wrote $HOME/.vca_image_url (and .sha256)"
echo
echo "Fetch it from a deploy target with:  vm/fetch-vca-image.sh"
echo "NOTE: presigned URL expires in $((TTL/86400))d; re-run this (or just the presign) to refresh."
