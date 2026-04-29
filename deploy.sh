#!/bin/bash
# VERSION: 1.2.55-TFM
# OBJETIVO: Despliegue con Auditoría Cruzada Determinista 100%.

if [ -z "$1" ]; then
    echo -e "\033[0;31mError: Proporciona un tag (ej: v1.2.55)\033[0m"
    exit 1
fi

NEW_TAG=$1
WASM_PATH=".dfx/ic/canisters/vox_populi_backend/vox_populi_backend.wasm"

echo -e "\n\033[0;34m[1/4] Fase 1: Compilación Backend Determinista (Docker)...\033[0m"
docker run --rm -v "$(pwd)":/project vox_populi_backend_builder /bin/bash -c "rm -rf .dfx/ic/canisters/vox_populi_backend && dfx build --network ic vox_populi_backend"

echo -e "\n\033[0;34m[2/4] Fase 2: Despliegue en Mainnet...\033[0m"
dfx identity use prod_deployer
export DFX_WARNING=-mainnet_plaintext_identity
dfx canister --network ic install vox_populi_backend --mode upgrade --wasm "$WASM_PATH" --wasm-memory-persistence keep
dfx deploy --network ic vox_populi_frontend --no-wallet

echo -e "\n\033[0;34m[3/4] Fase 3: Generación de Manifiesto Local Post-Build...\033[0m"
FRONTEND_DIST=$(find src/vox_populi_frontend/dist src/vox_populi_frontend/build dist/vox_populi_frontend -name "index.html" -exec dirname {} \; 2>/dev/null | head -n 1)

if [ -d "$FRONTEND_DIST" ]; then
    cd "$FRONTEND_DIST"
    # Generamos el manifiesto local EXACTAMENTE igual que el de red:
    # 1. Sin archivos de config/mapas. 2. Doble espacio entre hash y nombre (estándar sha256sum). 3. Ordenado.
    find . -type f ! -name "*.map" ! -name "*.json5" ! -name "*.json" | sort | while read -r file; do
        hash=$(sha256sum "$file" | awk '{print $1}')
        echo "$hash  ${file#./}"
    done > ../../../assets.manifest
    cd ../../..
    sha256sum assets.manifest | awk '{print $1}' > assets.hash
else
    echo -e "\033[0;31mError: Assets locales no encontrados.\033[0m"; exit 1
fi

echo -e "\n\033[0;34m[4/4] Fase 4: Registro de Evidencias en Git...\033[0m"
git add .
git commit -m "release: $NEW_TAG (Full Deterministic Audit)"
git tag -a "$NEW_TAG" -m "$NEW_TAG"
git push origin main --tags --force

# ==============================================================================
#             AUDITORÍA DE INTEGRIDAD DEL BACKEND
# ==============================================================================
echo -e "\n\033[1;35m===============================================================\033[0m"
echo -e "\033[1;35m             AUDITORÍA DE INTEGRIDAD DEL BACKEND             \033[0m"
echo -e "\033[1;35m===============================================================\033[0m"
HASH_LOCAL_BE=$(sha256sum "$WASM_PATH" | awk '{print $1}')
HASH_RED_BE=$(dfx canister --network ic --identity anonymous info vox_populi_backend | grep "Module hash" | sed 's/.*0x//')

echo -e "HASH LOCAL: \033[0;36m$HASH_LOCAL_BE\033[0m"
echo -e "HASH RED:   \033[0;36m$HASH_RED_BE\033[0m"

if [ "$HASH_LOCAL_BE" == "$HASH_RED_BE" ]; then
    echo -e "\033[1;32mRESULTADO BACKEND: [ OK ] - DETERMINISMO CONFIRMADO\033[0m"
else
    echo -e "\033[1;31mRESULTADO BACKEND: [ ERROR ] - DISCREPANCIA DETECTADA\033[0m"
fi

# ==============================================================================
#             AUDITORÍA DE INTEGRIDAD DEL FRONTEND
# ==============================================================================
echo -e "\n\033[1;36m===============================================================\033[0m"
echo -e "\033[1;36m             AUDITORÍA DE INTEGRIDAD DEL FRONTEND            \033[0m"
echo -e "\033[1;36m===============================================================\033[0m"

./get_network_manifest.sh

echo -e "\033[1;33mCOMPARATIVA (HASH CONTENIDO REAL | NOMBRE):\033[0m"
echo -e "\033[0;34m--- MANIFIESTO LOCAL ---\033[0m"
cat assets.manifest
echo -e "\033[0;34m--- MANIFIESTO RED (DESCARGADO) ---\033[0m"
cat network_assets.manifest

echo -e "\033[1;36m---------------------------------------------------------------\033[0m"
LOCAL_SIG=$(cat assets.hash)
NET_ROOT_HASH=$(sha256sum network_assets.manifest | awk '{print $1}')

echo -e "FIRMA GLOBAL LOCAL: \033[0;36m$LOCAL_SIG\033[0m"
echo -e "FIRMA GLOBAL RED:   \033[0;36m$NET_ROOT_HASH\033[0m"

if [ "$LOCAL_SIG" == "$NET_ROOT_HASH" ]; then
    echo -e "\033[1;32mVERDICTO FRONTEND: [ OK ] - INTEGRIDAD 100% CONFIRMADA\033[0m"
else
    echo -e "\033[1;31mVERDICTO FRONTEND: [ ERROR ] - DISCREPANCIA EN LA FIRMA GLOBAL\033[0m"
    echo -e "Nota: Revisa si hay diferencias de espacios o saltos de línea finales."
fi
echo -e "\033[1;36m===============================================================\033[0m\n"