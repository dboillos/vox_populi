#!/bin/bash
# Ubicación: /audit/get_network_manifest.sh

CANISTER_ID="4zjkp-mqaaa-aaaaj-qqwrq-cai"
URL_BASE="https://${CANISTER_ID}.icp0.io"
OUTPUT_MANIFEST="network_assets.manifest"

echo "Descargando activos de la red para auditoría final..."

# Obtener lista oficial
dfx canister --network ic --identity anonymous call $CANISTER_ID list '(record {})' --output json > raw_list.json

python3 << 'EOF'
import json, subprocess, hashlib, os

with open("raw_list.json") as f:
    data = json.load(f)

url_base = "https://4zjkp-mqaaa-aaaaj-qqwrq-cai.icp0.io"
assets = []

for item in data:
    key = item.get("key", "")
    full_url = f"{url_base}{key}"
    path_name = key[1:] if key.startswith("/") else key
    try:
        content = subprocess.check_output(["curl", "-sL", full_url])
        h = hashlib.sha256(content).hexdigest()
        assets.append((path_name, h))
    except:
        continue

# Ordenar por nombre para asegurar match con el manifiesto local
assets.sort(key=lambda x: x[0])

with open("network_assets.manifest", "w") as f:
    for name, hash_val in assets:
        f.write(f"{hash_val}  {name}\n")
EOF

rm raw_list.json