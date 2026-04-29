#!/bin/bash
# NOMBRE: get_network_manifest.sh
# FUNCIÓN: Auditoría por descarga directa y normalización de orden.

CANISTER_ID="4zjkp-mqaaa-aaaaj-qqwrq-cai"
URL_BASE="https://${CANISTER_ID}.icp0.io"
OUTPUT_MANIFEST="network_assets.manifest"

echo "Descargando activos de la red para auditoría final..."

# 1. Obtener la lista de archivos oficial del canister
dfx canister --network ic --identity anonymous call $CANISTER_ID list '(record {})' --output json > raw_list.json

# 2. Descargar, hashear y ordenar alfabéticamente por NOMBRE (igual que find/sort)
python3 << 'EOF'
import json, subprocess, hashlib, os

with open("raw_list.json") as f:
    data = json.load(f)

url_base = "https://4zjkp-mqaaa-aaaaj-qqwrq-cai.icp0.io"
assets = []

for item in data:
    key = item.get("key", "")
    full_url = f"{url_base}{key}"
    # Normalizar nombre (quitar / inicial)
    path_name = key[1:] if key.startswith("/") else key
    
    try:
        # Descarga real vía curl
        content = subprocess.check_output(["curl", "-sL", full_url])
        h = hashlib.sha256(content).hexdigest()
        assets.append((path_name, h))
    except:
        continue

# ORDENAR POR NOMBRE (esencial para que el hash global coincida con el local)
assets.sort(key=lambda x: x[0])

with open("network_assets.manifest", "w") as f:
    for name, hash_val in assets:
        f.write(f"{hash_val}  {name}\n")
EOF

rm raw_list.json