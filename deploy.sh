#!/bin/bash
# VERSION: 1.2.44-god-mode
# DESCRIPCIÓN: Build de assets con bypass de errores de Candid y auditoría integral

if [ -z "$1" ]; then
    echo -e "\033[0;31mError: Proporciona un tag (ej: v1.2.44)\033[0m"
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

echo -e "\n\033[0;34m[2/4] Generando Certificación de Assets (Frontend)...\033[0m"

# Bypass: Ejecutamos el build de vite/webpack directamente saltando los hooks de dfx
# que están causando el error de Candid
if [ -d "src/vox_populi_frontend" ]; then
    cd src/vox_populi_frontend
    # Usamos --no-scripts para evitar que dfx generate se dispare
    npm install && npm run build --no-scripts
    cd ../..
fi

# Localizamos la carpeta de salida
FRONTEND_DIST=$(find src/vox_populi_frontend/dist src/vox_populi_frontend/build dist/vox_populi_frontend -name "index.html" -exec dirname {} \; 2>/dev/null | head -n 1)

if [ -d "$FRONTEND_DIST" ]; then
    echo -e "Assets localizados en: \033[0;32m$FRONTEND_DIST\033[0m"
    find "$FRONTEND_DIST" -type f ! -name "*.map" -exec sha256sum {} + | sort > assets.manifest
    TOTAL_FRONTEND_HASH=$(sha256sum assets.manifest | awk '{print $1}')
    echo "$TOTAL_FRONTEND_HASH" > assets.hash
    echo -e "Firma del Frontend: \033[0;32m$TOTAL_FRONTEND_HASH\033[0m"
else
    echo -e "\033[0;31mError: No se pudo generar la carpeta dist. Revisa el build de npm.\033[0m"
    exit 1
fi

echo -e "\n\033[0;34m[3/4] Actualizando Git y Tag...\033[0m"
git add .
git commit -m "release: $NEW_TAG (integrity bypass certified)"
git tag -d "$NEW_TAG" 2>/dev/null
git tag -a "$NEW_TAG" -m "$NEW_TAG"
git push origin main --tags --force

echo -e "\n\033[0;34m[4/4] Desplegando y Verificando...\033[0m"
dfx identity use prod_deployer
export DFX_WARNING=-mainnet_plaintext_identity

# Primero el backend con el WASM de Docker
dfx canister --network ic install vox_populi_backend --mode upgrade --wasm "$WASM_PATH" --wasm-memory-persistence keep

# Luego el frontend (dfx se encargará de subir lo que acabamos de buildear)
dfx deploy --network ic vox_populi_frontend --no-wallet

# --- AUDITORÍA FINAL ---
echo -e "\n\033[1;35m===============================================================\033[0m"
echo -e "\033[1;35m             AUDITORÍA DE INTEGRIDAD FINAL                   \033[0m"
echo -e "\033[1;35m===============================================================\033[0m"
HASH_LOCAL=$(sha256sum "$WASM_PATH" | awk '{print $1}')
HASH_RED=$(dfx canister --network ic --identity anonymous info vox_populi_backend | grep "Module hash" | sed 's/.*0x//')
echo -e "BACKEND HASH (LOCAL): \033[0;36m$HASH_LOCAL\033[0m"
echo -e "BACKEND HASH (RED):   \033[0;36m$HASH_RED\033[0m"
[ "$HASH_LOCAL" == "$HASH_RED" ] && echo -e "RESULTADO BACKEND: \033[1;32m[ MATCH ]\033[0m" || echo -e "RESULTADO BACKEND: \033[1;31m[ FAIL ]\033[0m"
echo -e "FRONTEND SIGNATURE:   \033[0;36m$(cat assets.hash)\033[0m"
echo -e "\033[1;35m===============================================================\033[0m\n"