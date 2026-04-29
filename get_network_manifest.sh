#!/bin/bash
# NOMBRE: get_network_manifest.sh
# FUNCIÓN: Extrae los hashes de los activos del frontend directamente de la Mainnet

CANISTER_FRONTEND="4zjkp-mqaaa-aaaaj-qqwrq-cai"
OUTPUT_JSON="assets_network.json"
OUTPUT_MANIFEST="network_assets.manifest"

dfx canister --network ic --identity anonymous call $CANISTER_FRONTEND list '(record {})' --output json > $OUTPUT_JSON

python3 << 'EOF'
import json
import binascii

with open("assets_network.json") as f:
    data = json.load(f)

output = []
for item in data:
    try:
        key = item.get("key", "")
        if key.startswith("/"): key = key[1:]
        encodings = item.get("encodings", [])
        if not encodings: continue
        sha256 = encodings[0].get("sha256")
        if not sha256: continue
        
        hash_hex = binascii.hexlify(bytes(sha256[0])).decode()
        output.append(f"{hash_hex} {key}")
    except Exception:
        continue

output.sort()
with open("network_assets.manifest", "w") as f:
    f.write("\n".join(output) + "\n")
EOF

rm assets_network.json