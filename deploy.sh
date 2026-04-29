#!/bin/bash
# VERSION: 1.2.48-TFM-VERIFICACION-TOTAL
# OBJETIVO: Evidencia absoluta de Backend (WASM) y Frontend (Assets)

if [ -z "$1" ]; then
    echo -e "\033[0;31mError: Proporciona un tag (ej: v1.2.48)\033[0m"
    exit 1
fi

NEW_TAG=$1
WASM_PATH=".dfx/ic/canisters/vox_populi_backend/vox_populi_backend.wasm"

echo -e "\n\033[0;34m[1/4] Compilando Backend Determinista con Docker...\033[0m"
rm -rf .dfx/ic/canisters/vox_populi_backend
docker build -t vox_populi_backend_builder .
docker run --rm -v "$(pwd)":/project vox_populi_backend_builder || { echo "Docker falló"; exit 1; }

echo -e "\n\033[0;34m[2/4] Generando Certificación Local de Frontend...\033[0m"
if [ -d "src/vox_populi_frontend" ]; then
    cd src/vox_populi_frontend
    npm install && npm run build --no-scripts
    cd ../..
fi

FRONTEND_DIST=$(find src/vox_populi_frontend/dist src/vox_populi_frontend/build dist/vox_populi_frontend -name "index.html" -exec dirname {} \; 2>/dev/null | head -n 1)

if [ -d "$FRONTEND_DIST" ]; then
    # Manifiesto Local Limpio: Solo Hash y Nombre (sin rutas relativas complejas)
    cd "$FRONTEND_DIST"
    find . -type f ! -name "*.map" -exec sha256sum {} + | sed 's| \./| |' | sort > ../../../assets.manifest
    cd ../../..
    LOCAL_ROOT_HASH=$(sha256sum assets.manifest | awk '{print $1}')
    echo "$LOCAL_ROOT_HASH" > assets.hash
else
    echo -e "\033[0;31mError: No se localizaron assets locales.\033[0m"; exit 1
fi

echo -e "\n\033[0;34m[3/4] Sincronizando Git y Tag...\033[0m"
git add .
git commit -m "release: $NEW_TAG (Integrity Audit)"
git tag -d "$NEW_TAG" 2>/dev/null
git tag -a "$NEW_TAG" -m "$NEW_TAG"
git push origin main --tags --force

echo -e "\n\033[0;34m[4/4] Desplegando en Mainnet...\033[0m"
dfx identity use prod_deployer
export DFX_WARNING=-mainnet_plaintext_identity
dfx canister --network ic install vox_populi_backend --mode upgrade --wasm "$WASM_PATH" --wasm-memory-persistence keep
dfx deploy --network ic vox_populi_frontend --no-wallet

# ==============================================================================
#             AUDITORÍA DE INTEGRIDAD (BACKEND INTACTO)
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

# EXTRACCIÓN Y NORMALIZACIÓN DE HASHES DE LA RED
# 1. Obtenemos la lista. 2. Limpiamos nombres. 3. Convertimos blobs a Hexadecimal limpio.
dfx canister --network ic --identity anonymous call vox_populi_frontend list 'record {}' \
    | grep -E "key =|content_hash = opt blob" \
    | sed 's/.*"\(.*\)".*/\1/' \
    | sed -E 's/.*blob "(.*)"/\1/' \
    | python3 -c "
import sys
lines = sys.stdin.readlines()
for i in range(0, len(lines), 2):
    name = lines[i].strip()
    blob = lines[i+1].strip().replace('\\\\', '\\')
    # Convertimos el formato blob de dfx a hex estándar
    hex_hash = ''.join([f'{ord(c):02x}' if ord(c) < 128 else f'{ord(c):02x}' for c in blob.encode('latin-1').decode('unicode_escape').encode('latin-1').hex()])
    # Solo nos interesan los primeros 64 caracteres (SHA-256)
    print(f'{hex_hash[:64]} {name}')
" | sort > network_assets.manifest

echo -e "\033[1;33mCOMPARATIVA DE ARCHIVOS (HASH | NOMBRE):\033[0m"
echo -e "\033[0;34m--- DATOS LOCALES ---\033[0m"
cat assets.manifest
echo -e "\033[0;34m--- DATOS EN RED ---\033[0m"
cat network_assets.manifest

echo -e "\033[1;36m---------------------------------------------------------------\033[0m"
NET_ROOT_HASH=$(sha256sum network_assets.manifest | awk '{print $1}')
echo -e "FIRMA GLOBAL (LOCAL): \033[0;36m$(cat assets.hash)\033[0m"
echo -e "FIRMA GLOBAL (RED):   \033[0;36m$NET_ROOT_HASH\033[0m"

if [ "$(cat assets.hash)" == "$NET_ROOT_HASH" ]; then
    echo -e "\033[1;32mRESULTADO FRONTEND: [ OK ] - INTEGRIDAD VERIFICADA ARCHIVO A ARCHIVO\033[0m"
else
    echo -e "\033[1;31mRESULTADO FRONTEND: [ ERROR ] - LOS ARCHIVOS NO COINCIDEN\033[0m"
fi
echo -e "\033[1;36m===============================================================\033[0m\n"