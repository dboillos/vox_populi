#!/bin/bash
# VERSION: v1.2.51-TFM-PRO-FINAL
# OBJETIVO: Evitar bloqueos en la auditoría de red y mostrar tabla comparativa real.

if [ -z "$1" ]; then
    echo -e "\033[0;31mError: Proporciona un tag (ej: v1.2.51)\033[0m"
    exit 1
fi

NEW_TAG=$1
WASM_PATH=".dfx/ic/canisters/vox_populi_backend/vox_populi_backend.wasm"

echo -e "\n\033[0;34m[1/4] Compilando Backend Determinista con Docker...\033[0m"
# Mantenemos tu compilación docker intacta
docker run --rm -v "$(pwd)":/project vox_populi_backend_builder /bin/bash -c "rm -rf .dfx/ic/canisters/vox_populi_backend && dfx build --network ic vox_populi_backend"

echo -e "\n\033[0;34m[2/4] Generando Certificación Local de Frontend...\033[0m"
if [ -d "src/vox_populi_frontend" ]; then
    cd src/vox_populi_frontend
    npm install && npm run build --no-scripts || true
    cd ../..
fi

FRONTEND_DIST=$(find src/vox_populi_frontend/dist src/vox_populi_frontend/build dist/vox_populi_frontend -name "index.html" -exec dirname {} \; 2>/dev/null | head -n 1)

if [ -d "$FRONTEND_DIST" ]; then
    cd "$FRONTEND_DIST"
    # Manifiesto Local: Formato estándar SHA256
    find . -type f ! -name "*.map" -exec sha256sum {} + | sed 's| \./| |' | sort > ../../../assets.manifest
    cd ../../..
    LOCAL_ROOT_HASH=$(sha256sum assets.manifest | awk '{print $1}')
    echo "$LOCAL_ROOT_HASH" > assets.hash
else
    echo -e "\033[0;31mError: No se localizaron assets locales.\033[0m"; exit 1
fi

echo -e "\n\033[0;34m[3/4] Sincronizando Git y Tag...\033[0m"
git add .
git commit -m "release: $NEW_TAG (Full Audit)"
git tag -d "$NEW_TAG" 2>/dev/null
git tag -a "$NEW_TAG" -m "$NEW_TAG"
git push origin main --tags --force

echo -e "\n\033[0;34m[4/4] Desplegando en Mainnet...\033[0m"
dfx identity use prod_deployer
export DFX_WARNING=-mainnet_plaintext_identity
dfx canister --network ic install vox_populi_backend --mode upgrade --wasm "$WASM_PATH" --wasm-memory-persistence keep
dfx deploy --network ic vox_populi_frontend --no-wallet

# ==============================================================================
#             AUDITORÍA DE INTEGRIDAD (TU LÓGICA DE BACKEND INTACTA)
# ==============================================================================
echo -e "\n\033[1;35m===============================================================\033[0m"
echo -e "\033[1;35m             AUDITORÍA DE INTEGRIDAD DEL BACKEND             \033[0m"
echo -e "\033[1;35m===============================================================\033[0m"
HASH_LOCAL_BE=$(sha256sum "$WASM_PATH" | awk '{print $1}')
HASH_RED_BE=$(dfx canister --network ic --identity anonymous info vox_populi_backend | grep "Module hash" | sed 's/.*0x//')
echo -e "HASH LOCAL (DOCKER): \033[0;36m$HASH_LOCAL_BE\033[0m"
echo -e "HASH EN RED (IC):    \033[0;36m$HASH_RED_BE\033[0m"
[ "$HASH_LOCAL_BE" == "$HASH_RED_BE" ] && echo -e "\033[1;32mRESULTADO BACKEND: [ OK ] - COINCIDENCIA TOTAL\033[0m"

echo -e "\n\033[1;36m===============================================================\033[0m"
echo -e "\033[1;36m             AUDITORÍA DETALLADA DEL FRONTEND                \033[0m"
echo -e "\033[1;36m===============================================================\033[0m"
echo "Consultando hashes directamente a la Mainnet..."

# EXTRACCIÓN SEGURA: Guardamos la respuesta cruda en un archivo para que no se bloquee el pipe
dfx canister --network ic --identity anonymous call vox_populi_frontend list '(record {})' > raw_network.txt

# Procesamos con Python (más robusto para el TFM) para generar el manifiesto de red
python3 -c "
import re, binascii
with open('raw_network.txt', 'r') as f:
    content = f.read()
# Buscamos pares de key y blob
items = re.findall(r'key = \"(.*?)\";.*?content_hash = opt blob \"(.*?)\"', content, re.S)
with open('network_assets.manifest', 'w') as out:
    lines = []
    for key, blob in items:
        # Limpiar nombre (quitar / inicial)
        name = key[1:] if key.startswith('/') else key
        # Decodificar el blob de dfx (formato octal/hex)
        decoded = blob.encode('latin-1').decode('unicode_escape').encode('latin-1')
        hex_hash = binascii.hexlify(decoded).decode()[:64]
        lines.append(f'{hex_hash} {name}')
    lines.sort()
    out.write('\n'.join(lines) + '\n')
"

echo -e "\033[1;33mCOMPARATIVA DE ARCHIVOS (HASH | NOMBRE):\033[0m"
echo -e "\033[0;34m--- DATOS LOCALES ---\033[0m"
cat assets.manifest
echo -e "\033[0;34m--- DATOS EN RED ---\033[0m"
cat network_assets.manifest

echo -e "\033[1;36m---------------------------------------------------------------\033[0m"
NET_ROOT_HASH=$(sha256sum network_assets.manifest | awk '{print $1}')
LOCAL_SIG=$(cat assets.hash)

echo -e "FIRMA GLOBAL (LOCAL): \033[0;36m$LOCAL_SIG\033[0m"
echo -e "FIRMA GLOBAL (RED):   \033[0;36m$NET_ROOT_HASH\033[0m"

if [ "$LOCAL_SIG" == "$NET_ROOT_HASH" ]; then
    echo -e "\033[1;32mRESULTADO FRONTEND: [ OK ] - ARCHIVOS IDÉNTICOS\033[0m"
else
    echo -e "\033[1;31mRESULTADO FRONTEND: [ ERROR ] - DISCREPANCIA EN ACTIVOS\033[0m"
fi
echo -e "\033[1;36m===============================================================\033[0m\n"

# Limpieza silenciosa
rm raw_network.txt