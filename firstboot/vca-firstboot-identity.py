#!/bin/python3
# vca-firstboot-identity.py -- generate a UNIQUE VCA identity on first boot.
# Runs on the appliance (CPython 3.5.2), so NO `secrets` module -> random.SystemRandom (CSPRNG).
# Writes /opt/extron_config/{vca_config.json,mac_pool.json}: host identity + 50-VCP pool,
# LAA (02:) MACs disjoint from Extron's 00:05:a6 OUI, unique Extron-charset serials.
# unitassy prefixes are preserved (model/license gates): host 60-1963-01, VCPs 60-1838-01.
import json, os, random

CFG = "/opt/extron_config"
CS = "23456789ACDEFHJKLMNPQRTUVWXY"   # Extron unambiguous charset (no 0,1,B,G,I,O,S,Z)
rng = random.SystemRandom()           # os.urandom-backed; present in 3.5

def serial(n=7):
    return "".join(rng.choice(CS) for _ in range(n))

def laa_mac():
    return "02:" + ":".join("%02x" % rng.randrange(256) for _ in range(5))

used_ser, used_mac = set(), set()
def uniq(gen, seen):
    while True:
        v = gen()
        if v not in seen:
            seen.add(v); return v

host = {"unitassy": "60-1963-01", "ethaddr": laa_mac(), "unitser": uniq(serial, used_ser)}
with open(os.path.join(CFG, "vca_config.json"), "w") as f:
    json.dump(host, f)

arr = [{"ethaddr": uniq(laa_mac, used_mac), "unitser": uniq(serial, used_ser)} for _ in range(50)]
with open(os.path.join(CFG, "mac_pool.json"), "w") as f:
    json.dump({"unitassy": "60-1838-01", "container_array": arr}, f)

print("vca-firstboot: generated host serial %s mac %s + 50-VCP pool" % (host["unitser"], host["ethaddr"]))
