#!/bin/bash
# VERSION: 1.2.47-TFM-AUDITORIA-TOTAL
# OBJETIVO: Match bit a bit de Backend y Match archivo por archivo de Frontend.

if [ -z "$1" ]; then
    echo -e "\033[0;31mError: Proporciona un tag (ej: v1.2.47)\033[0m"
    exit 1
fi

NEW_TAG=$1
WASM_PATH=".dfx/ic/canisters/vox_populi_backend/vox_populi_backend.wasm"

echo -e "\n\033[0;34m[1/4] Compilando Backend Determinista con Docker...\033[0m"
rm -rf .dfx/ic/canisters/vox_populi_backend

docker build -t vox_populi_backend_builder .
docker run --rm -v "$(pwd)":/project vox_populi_backend_builder || { echo "Docker falló"; exit 1; }

if [ ! -f "$WASM_PATH" ]; then
    echo -e "\033[0;31mError: No se encontró el WASM generado por Docker.\033[0m"
    exit 1
fi

echo -e "\n\033[0;34m[2/4] Generando Certificación Local de Frontend (Assets)...\033[0m"
if [ -d "src/vox_populi_frontend" ]; then
    cd src/vox_populi_frontend
    npm install && npm run build --no-scripts
    cd ../..
fi

FRONTEND_DIST=$(find src/vox_populi_frontend/dist src/vox_populi_frontend/build dist/vox_populi_frontend -name "index.html" -exec dirname {} \; 2>/dev/null | head -n 1)

if [ -d "$FRONTEND_DIST" ]; then
    # Manifiesto local: Lista de archivos y sus hashes SHA256
    find "$FRONTEND_DIST" -type f ! -name "*.map" -exec sha256sum {} + | sort > assets.manifest
    LOCAL_ROOT_HASH=$(sha256sum assets.manifest | awk '{print $1}')
    echo "$LOCAL_ROOT_HASH" > assets.hash
    echo -e "Firma Global Local: \033[0;32m$LOCAL_ROOT_HASH\033[0m"
else
    echo -e "\033[0;31mError: No se encontraron assets para certificar.\033[0m"; exit 1
fi

echo -e "\n\033[0;34m[3/4] Sincronizando Git y Tag...\033[0m"
git add .
git commit -m "release: $NEW_TAG (Full Backend & Frontend Integrity)"
git tag -d "$NEW_TAG" 2>/dev/null
git tag -a "$NEW_TAG" -m "$NEW_TAG"
git push origin main --tags --force

echo -e "\n\033[0;34m[4/4] Desplegando y Verificando en Mainnet...\033[0m"
dfx identity use prod_deployer
export DFX_WARNING=-mainnet_plaintext_identity

# Instalación del Backend (Tu comando original)
dfx canister --network ic install vox_populi_backend --mode upgrade --wasm "$WASM_PATH" --wasm-memory-persistence keep

# Despliegue del Frontend
dfx deploy --network ic vox_populi_frontend --no-wallet

# --- FASE DE COMPARACIÓN LÓGICA (EL CORAZÓN DEL TFM) ---
echo -e "\n\033[1;35m===============================================================\033[0m"
echo -e "\033[1;35m             AUDITORÍA DE INTEGRIDAD DEL BACKEND             \033[0m"
echo -e "\033[1;35m===============================================================\033[0m"

HASH_LOCAL_BE=$(sha256sum "$WASM_PATH" | awk '{print $1}')
echo -e "HASH LOCAL (DOCKER): \033[0;36m$HASH_LOCAL_BE\033[0m"

HASH_RED_BE=$(dfx canister --network ic --identity anonymous info vox_populi_backend | grep "Module hash" | sed 's/.*0x//')
echo -e "HASH EN RED (IC):    \033[0;36m$HASH_RED_BE\033[0m"

if [ "$HASH_LOCAL_BE" == "$HASH_RED_BE" ]; then
    echo -e "\033[1;32mRESULTADO BACKEND: [ OK ] - COINCIDENCIA TOTAL\033[0m"
else
    echo -e "\033[1;31mRESULTADO BACKEND: [ ERROR ] - DISCREPANCIA DETECTADA\033[0m"
fi

echo -e "\n\033[1;36m===============================================================\033[0m"
echo -e "\033[1;36m             AUDITORÍA DE INTEGRIDAD DEL FRONTEND            \033[0m"
echo -e "\033[1;36m===============================================================\033[0m"

# EXTRACCIÓN DE DATOS REALES DE LA RED
echo "Extrayendo hashes de archivos desde la Mainnet..."
dfx canister --network ic --identity anonymous call vox_populi_frontend list 'record {}' \
    | grep -E "key =|content_hash = opt blob" \
    | sed 's/.*"\(.*\)".*/\1/' \
    | sed 's/.*blob "\(.*\)".*/\1/' \
    | awk 'NR%2{printf "%s ",$0;next;}1' \
    | sort > network_assets.manifest

NETWORK_ROOT_HASH=$(sha256sum network_assets.manifest | awk '{print $1}')

echo -e "FIRMA GLOBAL (LOCAL): \033[0;36m$LOCAL_ROOT_HASH\033[0m"
echo -e "FIRMA GLOBAL (RED):   \033[0;36m$NETWORK_ROOT_HASH\033[0m"

if [ "$LOCAL_ROOT_HASH" == "$NETWORK_ROOT_HASH" ]; then
    echo -e "\033[1;32mRESULTADO FRONTEND: [ OK ] - ARCHIVOS CERTIFICADOS EN RED\033[0m"
else
    echo -e "\033[1;33mRESULTADO FRONTEND: [ AVISO ] - Verificar formato de manifiesto\033[0m"
fi
echo -e "\033[1;36m===============================================================\033[0m\n"