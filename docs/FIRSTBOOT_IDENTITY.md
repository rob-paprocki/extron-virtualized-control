# First-boot identity randomization

A packaged image is a byte-for-byte clone. If you deploy it N times as-is, every instance
reports the **same** host serial and the **same** VCP MAC/serial pool, so on a shared LAN the
clones collide with each other (and risk colliding with real Extron gear). This mechanism makes
each deployment **self-personalize on first boot**: it generates a unique identity, uses it, and
disarms itself, with nothing to edit by hand.

## What an identity is

The appliance reads its identity from two files under `/opt/extron_config`:

- `vca_config.json` — the **host**: `{"unitassy":"60-1963-01","ethaddr":<MAC>,"unitser":<serial>}`
- `mac_pool.json` — the **VCP pool**: `{"unitassy":"60-1838-01","container_array":[{ethaddr,unitser}×50]}`

`extron_info.sh` (runlevel S) and `heripc` (which builds the VCP containers, each bound to a pool
MAC via `-A <mac>`) read these early in boot. The `unitassy` prefixes are model/license identifiers
and are **preserved**. Only the serials and MACs are regenerated.

## The mechanism

Two files, installed into every image by `the image build tooling`:

| file | role |
|---|---|
| `/usr/local/sbin/vca-firstboot-identity.py` | generator — writes a fresh `vca_config.json` + `mac_pool.json` |
| `/etc/init.d/vca-firstboot-identity` | SysV hook — runs the generator if the arm-flag is present, then clears it |

**Generator.** Runs under the appliance's CPython 3.5.2, which has no `secrets` module, so it uses
`random.SystemRandom` (an `os.urandom`-backed CSPRNG). Serials use Extron's unambiguous charset
`23456789ACDEFHJKLMNPQRTUVWXY` (no `0 1 B G I O S Z`). MACs are **locally-administered** (`02:…`),
which keeps them off Extron's `00:05:A6` OUI so a virtual VCP can never clash with physical gear.
Serials and MACs are de-duplicated within the run.

**Hook + ordering.** The LSB header declares `X-Start-Before: extron_info.sh heripc` and
`Default-Start: S 2 3 4 5`, so the identity is rewritten **before** anything reads it. The image is
enabled without `systemctl enable` at build time: `the build tooling` drops the init script and creates
`S08vca-firstboot-identity` symlinks in `rcS.d` + `rc{2,3,4,5}.d`, and `systemd-sysv-generator`
turns those plus the LSB header into a unit with the correct `Before=` ordering at boot.

**Arm / consume.** The hook only fires when `/opt/extron_config/.randomize-on-boot` exists. On
success it removes that flag and touches `.personalized`, so it runs **once**. Subsequent boots
keep the generated identity. If generation fails it leaves the flag set and logs an error (via
`logger -t vca-firstboot`), so a transient failure retries rather than shipping a colliding identity.

A freshly packaged image ships **armed**, with a neutral placeholder identity
(`unitser:"0000000"`, `ethaddr:"02:00:00:00:00:00"`) that is overwritten on the first boot.

## Lifecycle

```
package (the build tooling)         first boot                 every boot after
─────────────────────────       ──────────────────────     ────────────────────
install generator + hook        flag present?  yes          flag absent → no-op
set .randomize-on-boot          → generate unique id        keep the generated id
stage placeholder identity      → rm flag, touch .personalized
```

## Operating it

- **Re-randomize** an existing instance (e.g. before cloning it again):
  `touch /opt/extron_config/.randomize-on-boot && reboot` — next boot regenerates.
- **Pin** a specific identity (disable self-randomization): remove the flag and edit the two JSON
  files by hand, keeping the `unitassy` prefixes and using `02:` MACs:
  `rm /opt/extron_config/.randomize-on-boot`. `scripts/vca-proxmox.sh` does exactly this when you
  choose "randomize" — it writes one concrete identity for that VM and removes the flag.

## Credentials (distributable images)

A packaged image carries **no builder secret**, not the appliance's admin password, not the
build host's SSH key. `the image build tooling` scrubs credentials at package time and the first-boot
hook provisions fresh ones:

- **Root shell (port 2222).** The password is the **host serial**. The image is staged with the
  placeholder serial (`0000000`) as the root password; the first-boot hook regenerates the serial
  and runs `chpasswd` to set root's password to it. So every clone's root password is unique and is
  simply its serial. Read it from the serial console at boot, from device discovery, or the admin
  UI. `sshd` allows root + password login but **`PermitEmptyPasswords no`**; no authorized key is
  baked in (add your own if you want key login). This port-2222 root shell is *our* addition for
  administering the VM; a stock VCA does not expose it (see `README.md`).
- **Admin / web UI.** Factory-fresh: the encrypted credential store (`cstore.enc` in
  `/var/extron/xstore/xstore.db`) is emptied, so the appliance boots to a "no credential / default
  config" state (`cstore: no credential in xstore → setting default config`) and the deployer sets
  their own admin password on first use, exactly like unboxing a real unit. The box boots healthy in
  this state (nginx up, `login.html` served, all VCPs running).

To pin a build to a specific root password instead, disarm first-boot (`rm
/opt/extron_config/.randomize-on-boot`) and set root's password by hand.

## Verified

On a reboot test the host serial changed `FXNE289 → KRQYCKT`, `vca_config.json`'s `ethaddr` changed
to a fresh `02:` MAC, the flag cleared and `.personalized` was set. Decisively, the rebuilt
VCP0 container launched with `-A 02:1c:b8:0f:80:b4`, matching the **newly generated** pool entry.
That proves the hook ran before `heripc` consumed the pool. All 5 VCPs came up on the new identity.

The credential scheme was verified on a re-baked image end to end: first boot generated serial
`R4TM9MD`; offline, `crypt(serial)` matched root's `/etc/shadow` hash, `authorized_keys` was empty,
`sshd` had `PermitEmptyPasswords no`, and the admin `cstore` had 0 rows. Live, a **password** login
(pubkey auth disabled) as `root` with `R4TM9MD` succeeded, and the booted box was healthy. 5 VCPs
ran, nginx was up, `login.html` returned 200, and the admin credential store was empty (factory-fresh).
