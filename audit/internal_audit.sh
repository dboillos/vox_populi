#!/bin/bash
# Ubicación: /audit/internal_audit.sh (Ejecutado DENTRO de Docker)

# --- A. VERIFICACIÓN BACKEND ---
echo -e "\n\033[1;34m[2/3] Verificando Backend (WASM) en red Mainnet...\033[0m"
WASM_PATH="../.dfx/ic/canisters/vox_populi_backend/vox_populi_backend.wasm"

if [ -f "$WASM_PATH" ]; then
    HASH_LOCAL_BE=$(sha256sum "$WASM_PATH" | awk '{print $1}')
    HASH_RED_BE=$(dfx canister --network ic --identity anonymous info vox_populi_backend 2>/dev/null | grep 'Module hash' | sed 's/.*0x//')
    
    echo -e "HASH LOCAL: \033[0;36m$HASH_LOCAL_BE\033[0m"
    echo -e "HASH RED:   \033[0;36m$HASH_RED_BE\033[0m"
    
    [ "$HASH_LOCAL_BE" == "$HASH_RED_BE" ] && \
        echo -e "RESULTADO: \033[1;32m[ OK ] - DETERMINISMO CONFIRMADO\033[0m" || \
        echo -e "RESULTADO: \033[1;31m[ ERROR ] - DISCREPANCIA\033[0m"
else
    echo -e "\033[1;31m[!] Error: WASM local no encontrado.\033[0m"
fi

# --- B. VERIFICACIÓN FRONTEND ---
echo -e "\n\033[1;34m[3/3] Verificando Frontend (Assets Reales vs Mainnet)...\033[0m"

# Buscar carpeta dist
FRONTEND_DIST=$(find ../src/vox_populi_frontend/dist ../src/vox_populi_frontend/build ../dist/vox_populi_frontend -name 'index.html' -exec dirname {} \; 2>/dev/null | head -n 1)

if [ -d "$FRONTEND_DIST" ]; then
    echo "Escaneando archivos locales y recalculando hashes..."
    # Generar manifiesto local
    (cd "$FRONTEND_DIST" && find . -type f ! -name '*.map' ! -name '*.json5' ! -name '*.json' | sort | while read -r file; do
        hash=$(sha256sum "$file" | awk '{print $1}')
        echo "$hash  ${file#./}"
    done) > ./assets.manifest
    sha256sum assets.manifest | awk '{print $1}' > assets.hash
else
    echo -e "\033[1;31m[!] Error: Carpeta dist no encontrada.\033[0m"; exit 1
fi

# Descarga de red
./get_network_manifest.sh

# Salida visual
echo -e "\033[0;34m--- MANIFIESTO LOCAL (RECALCULADO) ---\033[0m"
cat assets.manifest
echo -e "\033[0;34m--- MANIFIESTO RED (DESCARGADO) ---\033[0m"
cat network_assets.manifest

LOCAL_SIG=$(cat assets.hash)
NET_ROOT_HASH=$(sha256sum network_assets.manifest | awk '{print $1}')

echo -e "\033[1;36m---------------------------------------------------------------\033[0m"
echo -e "FIRMA GLOBAL LOCAL: \033[0;36m$LOCAL_SIG\033[0m"
echo -e "FIRMA GLOBAL RED:   \033[0;36m$NET_ROOT_HASH\033[0m"

if [ "$LOCAL_SIG" == "$NET_ROOT_HASH" ]; then
    echo -e "\033[1;32mVERDICTO FINAL: [ OK ] INTEGRIDAD 100% CONFIRMADA\033[0m"
else
    echo -e "\033[1;31mVERDICTO FINAL: [ ERROR ] DISCREPANCIA DETECTADA\033[0m"
    exit 1
fi