#!/usr/bin/env bash
# vca-proxmox.sh — deploy a Virtual Control Appliance VM on Proxmox VE.
# Style/UX modeled on community-scripts/ProxmoxVE (whiptail prompts, colored msgs).
# Run ON a Proxmox host as root:
#     bash vca-proxmox.sh            # interactive
#     bash vca-proxmox.sh /path/or/URL/to/vca-portable.qcow2
#
# It will: prompt for VM settings, (optionally) randomize the VCA identity so this
# deployment has unique serials/MACs, create a Q35/OVMF VM, import the disk, and start it.
set -euo pipefail

# ---------- community-scripts-style UI ----------
YW=$'\033[33m'; GN=$'\033[1;92m'; RD=$'\033[01;31m'; CL=$'\033[m'; BL=$'\033[36m'
msg_info(){ printf " ${YW}•${CL} %s\n" "$*"; }
msg_ok(){   printf " ${GN}✓${CL} %s\n" "$*"; }
msg_err(){  printf " ${RD}✗${CL} %s\n" "$*" >&2; }
header(){ printf "${BL}
   __   ___  ___      ___  ___
  \\ \\ / / |/ __|__ _ / __|/ _ \\   Virtual Control Appliance
   \\ V /| | (__/ _\` | (__| (_) |  Proxmox deployer
    \\_/ |_|\\___\\__,_|\\___|\\___/
${CL}\n"; }

command -v qm >/dev/null || { msg_err "not a Proxmox host (qm not found)"; exit 1; }
[ "$(id -u)" = 0 ] || { msg_err "run as root"; exit 1; }
header

IMG_SRC="${1:-}"
need(){ command -v "$1" >/dev/null || { msg_info "installing $1"; apt-get install -y -q "$2" >/dev/null; }; }

ask(){ whiptail --title "VCA Deploy" --inputbox "$1" 9 64 "$2" 3>&1 1>&2 2>&3; }
yesno(){ whiptail --title "VCA Deploy" --yesno "$1" 9 64 3>&1 1>&2 2>&3; }

# ---------- gather settings ----------
NEXTID=$(pvesh get /cluster/nextid 2>/dev/null || echo 900)
VMID=$(ask "VM ID" "$NEXTID")
NAME=$(ask "VM name (hostname)" "vca-100")
CORES=$(ask "vCPU cores" "4")
RAM=$(ask "RAM (MB)   (>=8192; more = more VCPs)" "8192")
# storage + bridge menus from the host
STOR=$(ask "Target storage (VM disk)" "local-lvm")
BRIDGE=$(ask "LAN bridge" "vmbr0")
DUALNIC=no; yesno "Add a second NIC for an isolated AV-LAN plane?" && DUALNIC=yes
AVBRIDGE=""; [ "$DUALNIC" = yes ] && AVBRIDGE=$(ask "AV-LAN bridge (separate switch/VLAN)" "vmbr1")
RANDID=yes; yesno "Randomize identity (unique serials + locally-administered MACs) for THIS deployment?\n(Recommended so deployments don't clash.)" || RANDID=no
FIXVTLP=yes; yesno "Point deployed virtual panels (VTLP) at the local VCP so they come ONLINE\nin a browser / the Extron Control app with no physical panel? (Recommended.)" || FIXVTLP=no
# Default image source: a staged R2 presigned URL if present ($VCA_IMAGE_URL or
# ~/.vca_image_url, written by scripts/r2-publish-image.sh), else a local path. This lets
# you deploy straight from private R2 with a plain curl — no secret lives in this script.
IMG_URL_DEFAULT="${VCA_IMAGE_URL:-}"
[ -z "$IMG_URL_DEFAULT" ] && [ -f "$HOME/.vca_image_url" ] && IMG_URL_DEFAULT=$(cat "$HOME/.vca_image_url")
if [ -z "$IMG_SRC" ]; then
  IMG_SRC=$(ask "Path or URL to vca-portable.qcow2" "${IMG_URL_DEFAULT:-/root/vca-portable.qcow2}")
fi

# ---------- fetch image ----------
WORK=$(mktemp -d /var/tmp/vca.XXXX); QCOW="$WORK/vca.qcow2"
if printf '%s' "$IMG_SRC" | grep -qE '^https?://'; then
  need curl curl
  msg_info "downloading image from R2 (curl)"
  curl -fSL --retry 3 --retry-delay 5 "$IMG_SRC" -o "$QCOW" || { msg_err "download failed"; exit 1; }
  msg_ok "downloaded"
  # optional integrity check: $VCA_IMAGE_SHA256, else ~/.vca_image_url.sha256
  SHA="${VCA_IMAGE_SHA256:-}"
  [ -z "$SHA" ] && [ -f "$HOME/.vca_image_url.sha256" ] && SHA=$(cat "$HOME/.vca_image_url.sha256")
  if [ -n "$SHA" ]; then
    msg_info "verifying sha256"
    if echo "$SHA  $QCOW" | sha256sum -c - >/dev/null 2>&1; then msg_ok "checksum OK"; else msg_err "checksum MISMATCH"; exit 1; fi
  fi
else
  [ -f "$IMG_SRC" ] || { msg_err "image not found: $IMG_SRC"; exit 1; }
  cp --reflink=auto "$IMG_SRC" "$QCOW"
fi

# ---------- (optional) pre-boot rootfs injection: identity + VTLP controller address ----------
if [ "$RANDID" = yes ] || [ "$FIXVTLP" = yes ]; then
  need qemu-nbd qemu-utils; modprobe nbd max_part=8 2>/dev/null || true
  ND=/dev/nbd11; qemu-nbd -d "$ND" 2>/dev/null || true
  qemu-nbd -c "$ND" --format=qcow2 "$QCOW"; sleep 1; partprobe "$ND" 2>/dev/null || true
  MNT="$WORK/mnt"; mkdir -p "$MNT"
  ROOTDEV=$(blkid -L vca-root 2>/dev/null || echo "${ND}p3")   # root = ext4 labeled vca-root (p3)
  mount "$ROOTDEV" "$MNT"

  if [ "$RANDID" = yes ]; then
    msg_info "randomizing VCA identity (unique serials + 02: MACs)"
    python3 -I - "$MNT" <<'PY'
import sys,os,json,secrets
root=sys.argv[1]; CS="23456789ACDEFHJKLMNPQRTUVWXY"
ser=lambda n=7:"".join(secrets.choice(CS) for _ in range(n))
mac=lambda:"02:"+":".join("%02x"%secrets.randbelow(256) for _ in range(5))
us,um=set(),set()
def uq(g,s):
  while True:
    v=g();
    if v not in s: s.add(v); return v
d=os.path.join(root,"opt/extron_config")
json.dump({"unitassy":"60-1963-01","ethaddr":mac(),"unitser":uq(ser,us)}, open(os.path.join(d,"vca_config.json"),"w"))
json.dump({"unitassy":"60-1838-01","container_array":[{"ethaddr":uq(mac,um),"unitser":uq(ser,us)} for _ in range(50)]}, open(os.path.join(d,"mac_pool.json"),"w"))
open(os.path.join(d,".personalized"),"w").close()
print("new host serial:", json.load(open(os.path.join(d,"vca_config.json")))["unitser"])
PY
    # pin it: the packaged image ships armed to self-randomize on first boot; since we just
    # wrote a concrete identity for THIS VM, disarm so first boot doesn't overwrite it.
    rm -f "$MNT/opt/extron_config/.randomize-on-boot"
    msg_ok "identity randomized (pinned for this VM)"
  fi

  if [ "$FIXVTLP" = yes ]; then
    # A GUI-Designer project bakes in the processor's design-time IP; vtlp_ws_server dials the host
    # BY that address, so on a differently-addressed VCP the panel can't bridge -> "offline". For a
    # self-hosted VTLP the host is local, so 127.0.0.1 is correct and network-independent.
    msg_info "pointing deployed VTLP panels at the local VCP (so they come online, no physical panel)"
    python3 -I - "$MNT" 127.0.0.1 <<'PY'
import sys,os,json,glob
root=sys.argv[1].rstrip("/"); target=sys.argv[2]
def fix(p):
    try:
        with open(p) as f: d=json.load(f)
    except Exception: return False
    if not isinstance(d,dict): return False
    ch=False
    for k in ("Controller","TLP"):
        v=d.get(k)
        if isinstance(v,dict) and "Address" in v and v["Address"]!=target:
            v["Address"]=target; ch=True
    if ch:
        with open(p,"w") as f: json.dump(d,f)
    return ch
bases=["/var/VCP*/var/nortxe","/var/.myroot/VCP*projc/var/nortxe","/var/.myroot/host/VCP*projc/backup/nortxe"]
pats=[b+"/"+g+"/web/vtlp/*/resources/uiinterface/config.json" for b in bases for g in ("gve",".gve")]
seen=set(); n=0
for pat in pats:
    for p in glob.glob(root+pat):
        rp=os.path.realpath(p)
        if rp in seen: continue
        seen.add(rp)
        if fix(p): n+=1
print("VTLP controller addr -> %s on %d config(s)" % (target,n))
PY
    msg_ok "VTLP panels point at local VCP (online in a browser / Extron Control app)"
  fi

  umount "$MNT"; qemu-nbd -d "$ND"
fi

# ---------- create VM ----------
msg_info "creating VM $VMID ($NAME)"
NET1=""; [ "$DUALNIC" = yes ] && NET1="--net1 virtio,bridge=$AVBRIDGE,firewall=0"
qm create "$VMID" --name "$NAME" --memory "$RAM" --cores "$CORES" --cpu host \
  --machine q35 --bios ovmf --efidisk0 "$STOR:1,efitype=4m,pre-enrolled-keys=0" \
  --scsihw virtio-scsi-single \
  --net0 "virtio,bridge=$BRIDGE,firewall=0" $NET1 \
  --ostype l26 --onboot 0 --tablet 0 >/dev/null
msg_ok "VM shell created"

msg_info "importing disk into $STOR"
qm importdisk "$VMID" "$QCOW" "$STOR" >/dev/null 2>&1
DISK=$(qm config "$VMID" | awk -F': ' '/unused0/{print $2; exit}')
[ -n "$DISK" ] || { msg_err "import failed"; exit 1; }
qm set "$VMID" --scsi0 "${DISK},discard=on,ssd=1" >/dev/null
qm set "$VMID" --boot order=scsi0 >/dev/null
msg_ok "disk attached"

rm -rf "$WORK"

cat <<EOF

$(msg_ok "VCA $VMID ready")
  Start it:        qm start $VMID
  Console/serial:  qm terminal $VMID   (serial0 is wired)   or the noVNC console
  Root shell:      ssh -p 2222 root@<vm-ip>    (password = the unit serial, self-set on first boot)
  Web UI:          https://<vm-ip>/           (factory-fresh: no admin password stored — set your own)

IMPORTANT networking:
  Each VCP presents its own MAC on $BRIDGE via macvlan. Ensure that bridge/NIC does NOT
  filter guest MACs: in Proxmox, leave the NIC firewall OFF (set above) and do not enable
  MAC filtering. On the physical uplink switch, the port must accept multiple MACs.
$([ "$DUALNIC" = yes ] && echo "  AV-LAN: NIC2 is on $AVBRIDGE. Put that bridge on an isolated switch/VLAN.
  Dual-NIC per-VCP (eth0 LAN + eth1 AV-LAN) also needs ethernetPorts:2 + vcpct -e
  (the dual-NIC image is built on the build host).")
$([ "$RANDID" = yes ] && echo "  Identity: pinned now — unique serials + locally-administered (02:) MACs." || echo "  Identity: left to self-randomize on first boot (image ships armed); the VM gets a unique serial/MAC set automatically.")
$([ "$FIXVTLP" = yes ] && echo "  Virtual UI: deployed panels point at the local VCP — open https://<vcp-ip>/web/vtlp/<id>/ (admin login) or the Extron Control app; no physical panel needed." || echo "  Virtual UI: project controller addresses left as-is — a panel may show 'offline' if the project's controller IP != this VCP (re-run with VTLP fix).")

  Each deployment runs 5 VCPs (free tier), with a unique auto-generated identity.
EOF
