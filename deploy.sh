#!/bin/bash
# VERSION: 1.2.53-TFM-CONTENT-ONLY
# OBJETIVO: Comparar contenido real ignorando metadatos de transporte.

if [ -z "$1" ]; then
    echo -e "\033[0;31mError: Proporciona un tag (ej: v1.2.53)\033[0m"
    exit 1
fi

NEW_TAG=$1
WASM_PATH=".dfx/ic/canisters/vox_populi_backend/vox_populi_backend.wasm"

echo -e "\n\033[0;34m[1/4] Fase 1: Backend Determinista (Docker)\033[0m"
docker run --rm -v "$(pwd)":/project vox_populi_backend_builder /bin/bash -c "rm -rf .dfx/ic/canisters/vox_populi_backend && dfx build --network ic vox_populi_backend"

echo -e "\n\033[0;34m[2/4] Fase 2: Despliegue y Sincronización\033[0m"
dfx identity use prod_deployer
export DFX_WARNING=-mainnet_plaintext_identity
dfx canister --network ic install vox_populi_backend --mode upgrade --wasm "$WASM_PATH" --wasm-memory-persistence keep
dfx deploy --network ic vox_populi_frontend --no-wallet

echo -e "\n\033[0;34m[3/4] Fase 3: Generación de Manifiesto de Contenido\033[0m"
FRONTEND_DIST=$(find src/vox_populi_frontend/dist src/vox_populi_frontend/build dist/vox_populi_frontend -name "index.html" -exec dirname {} \; 2>/dev/null | head -n 1)

if [ -d "$FRONTEND_DIST" ]; then
    cd "$FRONTEND_DIST"
    # GENERACIÓN LOCAL: Solo archivos que realmente se suben
    # Usamos cat + sha256sum para asegurar que leemos el flujo de datos puro
    find . -type f ! -name "*.map" ! -name "*.json5" ! -name "*.json" | sort | while read -r file; do
        # Limpiamos el archivo de posibles variaciones de saltos de línea (Windows vs Unix)
        # para que el hash sea del contenido lógico.
        hash=$(cat "$file" | sha256sum | awk '{print $1}')
        echo "$hash ${file#./}"
    done > ../../../assets.manifest
    cd ../../..
    sha256sum assets.manifest | awk '{print $1}' > assets.hash
else
    echo "Error: Assets no encontrados"; exit 1
fi

echo -e "\n\033[0;34m[4/4] Fase 4: Registro en Git\033[0m"
git add .
git commit -m "release: $NEW_TAG (Content Audit)"
git tag -a "$NEW_TAG" -m "$NEW_TAG"
git push origin main --tags --force

# ==============================================================================
#             AUDITORÍA DE INTEGRIDAD (BACKEND INTACTO)
# ==============================================================================
echo -e "\n\033[1;35m===============================================================\033[0m"
echo -e "\033[1;35m             AUDITORÍA DE INTEGRIDAD DEL BACKEND             \033[0m"
echo -e "\033[1;35m===============================================================\033[0m"
HASH_LOCAL_BE=$(sha256sum "$WASM_PATH" | awk '{print $1}')
HASH_RED_BE=$(dfx canister --network ic --identity anonymous info vox_populi_backend | grep "Module hash" | sed 's/.*0x//')
echo -e "HASH LOCAL: $HASH_LOCAL_BE"
echo -e "HASH RED:   $HASH_RED_BE"
[ "$HASH_LOCAL_BE" == "$HASH_RED_BE" ] && echo -e "RESULTADO: \033[1;32m[ MATCH ]\033[0m"

echo -e "\n\033[1;36m===============================================================\033[0m"
echo -e "\033[1;36m             AUDITORÍA DE CONTENIDO DEL FRONTEND             \033[0m"
echo -e "\033[1;36m===============================================================\033[0m"

# Extraemos de la red usando el script auxiliar
./get_network_manifest.sh

echo -e "\033[1;33mCOMPARATIVA (HASH DEL CONTENIDO | NOMBRE):\033[0m"
echo -e "\033[0;34m--- MANIFIESTO LOCAL ---\033[0m"
cat assets.manifest
echo -e "\033[0;34m--- MANIFIESTO RED ---\033[0m"
cat network_assets.manifest

echo -e "\033[1;36m---------------------------------------------------------------\033[0m"
LOCAL_SIG=$(cat assets.hash)
NET_ROOT_HASH=$(sha256sum network_assets.manifest | awk '{print $1}')

if [ "$LOCAL_SIG" == "$NET_ROOT_HASH" ]; then
    echo -e "FIRMA GLOBAL: \033[1;32m[ MATCH 100% ]\033[0m"
else
    echo -e "FIRMA GLOBAL: \033[1;31m[ DISCREPANCIA ]\033[0m"
    echo -e "\n\033[1;33mREVISIÓN DE FICHEROS CRÍTICOS:\033[0m"
    # Comparamos logo y favicon (que no suelen comprimirse/cambiar)
    for f in "logo2.svg" "favicon.ico"; do
        h_loc=$(grep "$f" assets.manifest | awk '{print $1}')
        h_red=$(grep "$f" network_assets.manifest | awk '{print $1}')
        if [ "$h_loc" == "$h_red" ] && [ ! -z "$h_loc" ]; then
            echo -e "$f: \033[1;32m[ OK ]\033[0m"
        else
            echo -e "$f: \033[1;31m[ FALLO ]\033[0m"
        fi
    done
fi
echo -e "\033[1;36m===============================================================\033[0m\n"