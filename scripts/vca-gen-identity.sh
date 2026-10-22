#!/usr/bin/env bash
# vca-gen-identity.sh — write a RANDOM, unique VCA identity into an image/rootfs so
# every deployment differs (no two clones share the on-disk serials/MACs).
#
#   sudo ./vca-gen-identity.sh <rootfs-mountpoint> [--pool N] [--host-mac AA:BB:..] [--prefix TAG]
#
# Writes:
#   <root>/opt/extron_config/vca_config.json   (host identity; unitassy kept = 60-1963-01)
#   <root>/opt/extron_config/mac_pool.json     (N VCP {ethaddr,unitser}, N<=50 default 50)
# MACs are LOCALLY-ADMINISTERED (02:..) so they never collide with real Extron (00:05:A6) gear.
# Serials use Extron's unambiguous charset. unitassy prefixes are preserved (license/capability gate).
set -euo pipefail
ROOT=${1:?usage: vca-gen-identity.sh <rootfs-mountpoint> [--pool N] [--host-mac MAC] [--prefix TAG]}; shift
POOL=50; HOST_MAC=""; PREFIX=""
while [ $# -gt 0 ]; do case "$1" in
  --pool) POOL=$2; shift 2;;
  --host-mac) HOST_MAC=$2; shift 2;;
  --prefix) PREFIX=$2; shift 2;;
  *) echo "unknown arg $1" >&2; exit 2;;
esac; done
[ -d "$ROOT/opt/extron_config" ] || { echo "no $ROOT/opt/extron_config — is this a VCA rootfs?" >&2; exit 1; }

python3 -I - "$ROOT" "$POOL" "$HOST_MAC" "$PREFIX" <<'PY'
import sys, os, json, secrets
root, pool, host_mac, prefix = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
CS = "23456789ACDEFHJKLMNPQRTUVWXY"   # Extron-style unambiguous charset (no 0,1,B,G,I,O,S,Z)
def serial(n=7):
    body = "".join(secrets.choice(CS) for _ in range(n-1))
    return (prefix[:1].upper() if prefix else secrets.choice(CS)) + body
def laa_mac():
    # locally-administered, unicast: first octet 0x02; random remaining 5
    return "02:" + ":".join("%02x" % secrets.randbelow(256) for _ in range(5))

used_ser, used_mac = set(), set()
def uniq(gen, seen):
    while True:
        v = gen()
        if v not in seen: seen.add(v); return v

cfgdir = os.path.join(root, "opt/extron_config")
# host identity — KEEP unitassy 60-1963-01 (VCA100 license/capability gate)
host = {
  "unitassy": "60-1963-01",
  "ethaddr": (host_mac if host_mac else laa_mac()).lower(),
  "unitser": uniq(serial, used_ser),
}
with open(os.path.join(cfgdir, "vca_config.json"), "w") as f:
    json.dump(host, f)

# VCP pool — KEEP unitassy 60-1838-01 (VCP model), LAA MACs, unique serials
arr = [{"ethaddr": uniq(laa_mac, used_mac), "unitser": uniq(serial, used_ser)} for _ in range(pool)]
with open(os.path.join(cfgdir, "mac_pool.json"), "w") as f:
    json.dump({"unitassy": "60-1838-01", "container_array": arr}, f)

# drop any stale per-container stamped identity so it re-stamps from the new pool on next start
# (safe: setVCPINFO rewrites nv_params at VCP start)
print("host unitser =", host["unitser"], " host mac =", host["ethaddr"])
print("pool: %d VCPs, MACs 02:xx (locally-administered), unique serials" % pool)
PY
# mark personalized so a first-boot hook won't overwrite a deliberately-set identity
touch "$ROOT/opt/extron_config/.personalized" 2>/dev/null || true
echo "identity written to $ROOT/opt/extron_config/{vca_config.json,mac_pool.json}"
