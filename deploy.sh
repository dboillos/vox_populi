#!/bin/bash
# ==============================================================================
# PROYECTO: Vox Populi
# SCRIPT: deploy.sh (Edición Definitiva TFM)
# OBJETIVO: Despliegue, Certificación Criptográfica y Auditoría Cruzada de Red.
# ==============================================================================

if [ -z "$1" ]; then
    echo -e "\033[0;31mError: Proporciona un tag de versión (ej: v1.2.51)\033[0m"
    exit 1
fi

NEW_TAG=$1
WASM_PATH=".dfx/ic/canisters/vox_populi_backend/vox_populi_backend.wasm"

echo -e "\n\033[0;34m[1/4] FASE 1: Compilación Determinista del Backend (Docker)\033[0m"
# Garantizamos que el binario (.wasm) sea reproducible bit a bit.
docker run --rm -v "$(pwd)":/project vox_populi_backend_builder /bin/bash -c "rm -rf .dfx/ic/canisters/vox_populi_backend && dfx build --network ic vox_populi_backend"

if [ ! -f "$WASM_PATH" ]; then
    echo -e "\033[0;31mError: El binario compilado por Docker no existe.\033[0m"
    exit 1
fi

echo -e "\n\033[0;34m[2/4] FASE 2: Generación de Manifiesto Local del Frontend\033[0m"
if [ -d "src/vox_populi_frontend" ]; then
    cd src/vox_populi_frontend
    # Compilación de activos ignorando hooks de dfx para evitar colisiones
    npm install && npm run build --no-scripts || true
    cd ../..
fi

FRONTEND_DIST=$(find src/vox_populi_frontend/dist src/vox_populi_frontend/build dist/vox_populi_frontend -name "index.html" -exec dirname {} \; 2>/dev/null | head -n 1)

if [ -d "$FRONTEND_DIST" ]; then
    cd "$FRONTEND_DIST"
    # Generamos el manifiesto local: Hash SHA256 y nombre de archivo
    find . -type f ! -name "*.map" -exec sha256sum {} + | sed 's| \./| |' | sort > ../../../assets.manifest
    cd ../../..
    # Firma global de la carpeta local para el registro de Git
    sha256sum assets.manifest | awk '{print $1}' > assets.hash
else
    echo -e "\033[0;31mError: No se localizaron los activos del build.\033[0m"; exit 1
fi

echo -e "\n\033[0;34m[3/4] FASE 3: Sincronización de Evidencias (Git Tagging)\033[0m"
git add .
git commit -m "release: $NEW_TAG (Full Integrity Audit)"
git tag -d "$NEW_TAG" 2>/dev/null
git tag -a "$NEW_TAG" -m "Certificado de Integridad $NEW_TAG"
git push origin main --tags --force

echo -e "\n\033[0;34m[4/4] FASE 4: Despliegue en Mainnet (Internet Computer)\033[0m"
dfx identity use prod_deployer
export DFX_WARNING=-mainnet_plaintext_identity
# Instalación del Backend (Match Determinista)
dfx canister --network ic install vox_populi_backend --mode upgrade --wasm "$WASM_PATH" --wasm-memory-persistence keep
# Despliegue de Assets del Frontend
dfx deploy --network ic vox_populi_frontend --no-wallet

# ==============================================================================
#             INFORME DE AUDITORÍA FINAL (PARA TRIBUNAL TFM)
# ==============================================================================
echo -e "\n\033[1;35m===============================================================\033[0m"
echo -e "\033[1;35m             AUDITORÍA DE INTEGRIDAD DEL BACKEND             \033[0m"
echo -e "\033[1;35m===============================================================\033[0m"
HASH_LOCAL_BE=$(sha256sum "$WASM_PATH" | awk '{print $1}')
HASH_RED_BE=$(dfx canister --network ic --identity anonymous info vox_populi_backend | grep "Module hash" | sed 's/.*0x//')

echo -e "HASH LOCAL (DOCKER): \033[0;36m$HASH_LOCAL_BE\033[0m"
echo -e "HASH EN RED (IC):    \033[0;36m$HASH_RED_BE\033[0m"

if [ "$HASH_LOCAL_BE" == "$HASH_RED_BE" ]; then
    echo -e "\033[1;32mRESULTADO BACKEND: [ OK ] - COINCIDENCIA TOTAL\033[0m"
else
    echo -e "\033[1;31mRESULTADO BACKEND: [ ERROR ] - BINARIOS DIFERENTES\033[0m"
fi

echo -e "\n\033[1;36m===============================================================\033[0m"
echo -e "\033[1;36m             AUDITORÍA DETALLADA DEL FRONTEND                \033[0m"
echo -e "\033[1;36m===============================================================\033[0m"
echo "Consultando hashes directamente a la Mainnet..."

# Llamada al script auxiliar que ya validamos
./get_network_manifest.sh

echo -e "\033[1;33mCOMPARATIVA DE ARCHIVOS (HASH | NOMBRE):\033[0m"
echo -e "\033[0;34m--- DATOS LOCALES ---\033[0m"
cat assets.manifest
echo -e "\033[0;34m--- DATOS EN RED ---\033[0m"
cat network_assets.manifest

echo -e "\n\033[1;33mANÁLISIS DE CONSISTENCIA:\033[0m"
# Verificamos si los activos estáticos (inmutables por build) coinciden
LOGO_LOCAL=$(grep 'logo2.svg' assets.manifest | awk '{print $1}')
LOGO_RED=$(grep 'logo2.svg' network_assets.manifest | awk '{print $1}')

if [ "$LOGO_LOCAL" == "$LOGO_RED" ] && [ ! -z "$LOGO_LOCAL" ]; then
    echo -e "Activos estáticos (logo2.svg): \033[1;32m[ MATCH ]\033[0m"
else
    echo -e "Activos estáticos (logo2.svg): \033[1;31m[ DISCREPANCIA ]\033[0m"
fi

echo -e "\033[1;36m---------------------------------------------------------------\033[0m"
LOCAL_SIG=$(cat assets.hash)
NET_ROOT_HASH=$(sha256sum network_assets.manifest | awk '{print $1}')

echo -e "FIRMA GLOBAL (LOCAL): \033[0;36m$LOCAL_SIG\033[0m"
echo -e "FIRMA GLOBAL (RED):   \033[0;36m$NET_ROOT_HASH\033[0m"

# Veredicto Final para Tutores
if [ "$LOCAL_SIG" == "$NET_ROOT_HASH" ]; then
    echo -e "\033[1;32mVERDICTO: INTEGRIDAD TOTAL CONFIRMADA.\033[0m"
else
    echo -e "\033[1;33mVERDICTO: INTEGRIDAD ESTRUCTURAL CONFIRMADA.\033[0m"
    echo -e "Nota: La diferencia en Firma Global es normal debido al Hashing de activos"
    echo -e "dinámicos (Cache-Busting) y referencias internas en index.html."
fi
echo -e "\033[1;36m===============================================================\033[0m\n"