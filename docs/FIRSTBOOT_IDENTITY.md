# First-boot identity

A disk image is a byte-for-byte clone. Deploy it several times as-is and every instance reports
the same host serial and the same VCP MAC and serial pool. On a shared LAN the clones collide with
each other, and could collide with real Extron gear. To avoid that, each deployment generates its own
identity on first boot, uses it, and then disarms itself. You don't edit anything by hand.

## What an identity is

The appliance reads its identity from two files under `/opt/extron_config`:

- `vca_config.json` is the host: `{"unitassy":"60-1963-01","ethaddr":<MAC>,"unitser":<serial>}`
- `mac_pool.json` is the VCP pool: `{"unitassy":"60-1838-01","container_array":[{ethaddr,unitser}×50]}`

`extron_info.sh` (runlevel S) and `heripc` (which builds the VCP containers, each bound to a pool MAC
with `-A <mac>`) read these early in boot. The `unitassy` prefixes are model and license identifiers,
so they are kept. Only the serials and MACs are regenerated.

## The mechanism

Two files are installed in every image:

| File | Role |
|---|---|
| `/usr/local/sbin/vca-firstboot-identity.py` | Generator. Writes a fresh `vca_config.json` and `mac_pool.json`. |
| `/etc/init.d/vca-firstboot-identity` | SysV hook. Runs the generator if the arm flag is present, then clears the flag. |

The generator runs under the appliance's CPython 3.5.2, which has no `secrets` module, so it uses
`random.SystemRandom`, an `os.urandom`-backed generator. Serials draw from Extron's unambiguous
charset `23456789ACDEFHJKLMNPQRTUVWXY` (no `0 1 B G I O S Z`). MACs are locally administered (`02:...`),
which keeps them off Extron's `00:05:A6` OUI, so a virtual VCP can't clash with physical gear. Serials
and MACs are de-duplicated within a run.

The hook's LSB header declares `X-Start-Before: extron_info.sh heripc` and
`Default-Start: S 2 3 4 5`, so the identity is rewritten before anything reads it. The image enables
the hook without `systemctl enable`: the init script is dropped in place and `S08vca-firstboot-identity`
symlinks are created in `rcS.d` and `rc{2,3,4,5}.d`. At boot, `systemd-sysv-generator` turns those and
the LSB header into a unit with the right `Before=` ordering.

The hook only fires when `/opt/extron_config/.randomize-on-boot` exists. On success it removes that
flag and touches `.personalized`, so it runs once and later boots keep the generated identity. If
generation fails, the flag stays set and an error goes to the log (`logger -t vca-firstboot`), so a
transient failure retries instead of leaving you with a colliding identity.

A fresh image ships armed, with a neutral placeholder identity (`unitser:"0000000"`,
`ethaddr:"00:00:5E:00:53:00"`) that the first boot overwrites.

## Lifecycle

```
build image                     first boot                    every boot after
----------------------------    --------------------------    ----------------------
install generator and hook      flag present? yes             flag absent: no-op
set .randomize-on-boot          generate a unique identity    keep the generated identity
stage placeholder identity      rm flag, touch .personalized
```

## Operating it

To re-randomize an existing instance, for example before cloning it again, run
`touch /opt/extron_config/.randomize-on-boot && reboot`. The next boot regenerates the identity.

To pin a specific identity, remove the flag with `rm /opt/extron_config/.randomize-on-boot` and edit
the two JSON files by hand, keeping the `unitassy` prefixes and using `02:` MACs. When you choose
"randomize" in `scripts/vca-proxmox.sh`, the script does the equivalent for you: it writes one
concrete identity for that VM and removes the flag.

## Credentials

The image carries no admin password and no SSH key. The first-boot hook sets up what you need.

- **Root shell (port 2222).** The password is the host serial. The image starts with the placeholder
  serial (`0000000`) as root's password, and the hook regenerates the serial and runs `chpasswd` so
  the two match. Each clone therefore has its own root password. Read it from the serial console at
  boot, from device discovery, or in the admin UI. `sshd` allows root password login with
  `PermitEmptyPasswords no`. No authorized key is installed, so add your own for key login. A stock
  VCA doesn't expose this shell.
- **Admin web UI.** It starts factory-fresh. The credential store (`cstore.enc` in
  `/var/extron/xstore/xstore.db`) is empty, so you set the admin password on first use, as on a real
  unit. nginx, `login.html` and the VCPs all run normally in this state.

To pin a specific root password, run `rm /opt/extron_config/.randomize-on-boot` and set it by hand.

## Checking that it worked

After the first boot of a clone:

- `/opt/extron_config/.randomize-on-boot` is gone and `/opt/extron_config/.personalized` exists.
- `unitser` in `vca_config.json` is a new 7-character serial, and `ethaddr` starts with `02:`.
- The VCP containers were launched with `-A` MACs from the new `mac_pool.json`. That shows the hook
  ran before `heripc` read the pool.
- Logging in as root on port 2222 works with the new serial as the password, and
  `/root/.ssh/authorized_keys` is empty or absent.
