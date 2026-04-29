#!/bin/bash
# VERSION: 1.2.52-TFM-TOTAL-MATCH
# OBJETIVO: Coincidencia exacta de hashes ignorando metadatos de despliegue.

if [ -z "$1" ]; then
    echo -e "\033[0;31mError: Proporciona un tag (ej: v1.2.52)\033[0m"
    exit 1
fi

NEW_TAG=$1
WASM_PATH=".dfx/ic/canisters/vox_populi_backend/vox_populi_backend.wasm"

echo -e "\n\033[0;34m[1/4] FASE 1: Compilación Backend Determinista\033[0m"
docker run --rm -v "$(pwd)":/project vox_populi_backend_builder /bin/bash -c "rm -rf .dfx/ic/canisters/vox_populi_backend && dfx build --network ic vox_populi_backend"

echo -e "\n\033[0;34m[2/4] FASE 2: Despliegue en Mainnet (Sincronización)\033[0m"
dfx identity use prod_deployer
export DFX_WARNING=-mainnet_plaintext_identity

# Desplegamos PRIMERO para que dfx genere los archivos finales en local
dfx canister --network ic install vox_populi_backend --mode upgrade --wasm "$WASM_PATH" --wasm-memory-persistence keep
dfx deploy --network ic vox_populi_frontend --no-wallet

echo -e "\n\033[0;34m[3/4] FASE 3: Generación de Manifiesto Post-Despliegue\033[0m"
# Buscamos la carpeta dist que dfx acaba de usar para el deploy
FRONTEND_DIST=$(find src/vox_populi_frontend/dist src/vox_populi_frontend/build dist/vox_populi_frontend -name "index.html" -exec dirname {} \; 2>/dev/null | head -n 1)

if [ -d "$FRONTEND_DIST" ]; then
    cd "$FRONTEND_DIST"
    # IMPORTANTE: Excluimos archivos de configuración (.json5) y mapas (.map) que no van a la red
    find . -type f ! -name "*.map" ! -name "*.json5" ! -name "*.json" -exec sha256sum {} + | sed 's| \./| |' | sort > ../../../assets.manifest
    cd ../../..
    sha256sum assets.manifest | awk '{print $1}' > assets.hash
else
    echo -e "Error: Assets no encontrados"; exit 1
fi

echo -e "\n\033[0;34m[4/4] FASE 4: Registro de Evidencias en Git\033[0m"
git add .
git commit -m "release: $NEW_TAG (Audit Synchronized)"
git tag -a "$NEW_TAG" -m "$NEW_TAG"
git push origin main --tags --force

# ==============================================================================
#             AUDITORÍA TÉCNICA FINAL (CON COMPARACIÓN REAL)
# ==============================================================================
echo -e "\n\033[1;35m===============================================================\033[0m"
echo -e "\033[1;35m             AUDITORÍA DE INTEGRIDAD DEL BACKEND             \033[0m"
echo -e "\033[1;35m===============================================================\033[0m"
HASH_LOCAL_BE=$(sha256sum "$WASM_PATH" | awk '{print $1}')
HASH_RED_BE=$(dfx canister --network ic --identity anonymous info vox_populi_backend | grep "Module hash" | sed 's/.*0x//')
echo -e "HASH LOCAL: \033[0;36m$HASH_LOCAL_BE\033[0m"
echo -e "HASH RED:   \033[0;36m$HASH_RED_BE\033[0m"
[ "$HASH_LOCAL_BE" == "$HASH_RED_BE" ] && echo -e "RESULTADO: \033[1;32m[ MATCH ]\033[0m"

echo -e "\n\033[1;36m===============================================================\033[0m"
echo -e "\033[1;36m             AUDITORÍA DETALLADA DEL FRONTEND                \033[0m"
echo -e "\033[1;36m===============================================================\033[0m"
./get_network_manifest.sh

echo -e "\033[1;33mCOMPARATIVA ARCHIVO POR ARCHIVO:\033[0m"
echo -e "\033[0;34m--- LOCAL ---\033[0m"
cat assets.manifest
echo -e "\033[0;34m--- RED ---\033[0m"
cat network_assets.manifest

echo -e "\033[1;36m---------------------------------------------------------------\033[0m"
LOCAL_SIG=$(cat assets.hash)
NET_ROOT_HASH=$(sha256sum network_assets.manifest | awk '{print $1}')

echo -e "FIRMA GLOBAL LOCAL: \033[0;36m$LOCAL_SIG\033[0m"
echo -e "FIRMA GLOBAL RED:   \033[0;36m$NET_ROOT_HASH\033[0m"

if [ "$LOCAL_SIG" == "$NET_ROOT_HASH" ]; then
    echo -e "\033[1;32mVERDICTO: INTEGRIDAD TOTAL CONFIRMADA (MATCH 100%)\033[0m"
else
    echo -e "\033[1;31mVERDICTO: DISCREPANCIA DETECTADA\033[0m"
    echo -e "\033[1;33mNota para TFM: Se comparan los hashes del CONTENIDO de los archivos."
    echo -e "Si los nombres difieren, los hashes del contenido también lo harán"
    echo -e "debido a que el nombre es un reflejo de su firma criptográfica.\033[0m"
fi
echo -e "\033[1;36m===============================================================\033[0m\n"