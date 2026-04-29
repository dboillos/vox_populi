#!/bin/bash
# NOMBRE: get_network_manifest.sh
# FUNCIÓN: Auditoría por descarga directa (Real-World Verification)

CANISTER_ID="4zjkp-mqaaa-aaaaj-qqwrq-cai"
URL_BASE="https://${CANISTER_ID}.icp0.io"
OUTPUT_MANIFEST="network_assets.manifest"
TMP_DIR="network_audit_tmp"

echo "Iniciando descarga de activos desde la red para auditoría..."
mkdir -p $TMP_DIR

# 1. Obtener la lista de archivos mediante el JSON que ya validamos
dfx canister --network ic --identity anonymous call $CANISTER_ID list '(record {})' --output json > raw_list.json

# 2. Descargar cada archivo y calcular su hash real
python3 << 'EOF'
import json, subprocess, hashlib, os

with open("raw_list.json") as f:
    data = json.load(f)

url_base = "https://4zjkp-mqaaa-aaaaj-qqwrq-cai.icp0.io"
output = []

for item in data:
    key = item.get("key", "")
    full_url = f"{url_base}{key}"
    path_name = key[1:] if key.startswith("/") else key
    
    # Descargamos el archivo real de la red
    try:
        # Usamos curl para obtener el contenido exacto (manejando compresión si la hay)
        content = subprocess.check_output(["curl", "-sL", full_url])
        
        # Calculamos SHA256 del contenido descargado
        h = hashlib.sha256(content).hexdigest()
        output.append(f"{h} {path_name}")
    except Exception as e:
        continue

output.sort()
with open("network_assets.manifest", "w") as f:
    f.write("\n".join(output) + "\n")
EOF

rm raw_list.json
rm -rf $TMP_DIR