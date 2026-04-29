#!/bin/bash
# Ubicación: /audit/internal_audit.sh (Dentro de Docker)

# --- FASE 1: BACKEND ---
echo -e "\n\033[1;34m[2/3] FASE 1: VERIFICACIÓN BACKEND (WASM)\033[0m"
WASM_PATH=$(find /project -name "vox_populi_backend.wasm" | head -n 1)

if [ -n "$WASM_PATH" ]; then
    HASH_LOCAL_BE=$(sha256sum "$WASM_PATH" | awk '{print $1}')
    HASH_RED_BE=$(dfx canister --network ic --identity anonymous info vox_populi_backend 2>/dev/null | grep 'Module hash' | sed 's/.*0x//')
    echo -e "HASH LOCAL: \033[0;36m$HASH_LOCAL_BE\033[0m"
    echo -e "HASH RED:   \033[0;36m$HASH_RED_BE\033[0m"
    [ "$HASH_LOCAL_BE" == "$HASH_RED_BE" ] && echo -e "RESULTADO: \033[1;32m[ OK ]\033[0m" || echo -e "RESULTADO: \033[1;31m[ ERROR ]\033[0m"
else
    echo -e "\033[1;31m[!] Error: No hay WASM. Para auditar el backend tras un clone, debes subir el .wasm al repo.\033[0m"
fi

# --- FASE 2: FRONTEND (COMPILACIÓN Y AUDITORÍA) ---
echo -e "\n\033[1;34m[3/3] FASE 2: VERIFICACIÓN FRONTEND (COMPILANDO...)\033[0m"

# 1. Instalamos dependencias y compilamos para generar el 'dist' real
cd /project
echo "Instalando Node dependencies (silencioso)..."
npm install --quiet > /dev/null 2>&1
echo "Compilando Frontend determinísticamente..."
npm run build > /dev/null 2>&1

# 2. Localizamos la carpeta 'dist' recién generada
FRONTEND_DIST=$(find /project -name "index.html" | grep "dist" | head -n 1 | xargs dirname)

if [ -d "$FRONTEND_DIST" ]; then
    echo -e "Carpeta generada: \033[0;33m$FRONTEND_DIST\033[0m"
    cd "$FRONTEND_DIST"
    find . -type f ! -name "*.map" ! -name "*.json5" ! -name "*.json" | sort | while read -r file; do
        hash=$(sha256sum "$file" | awk '{print $1}')
        echo "$hash  ${file#./}"
    done > /project/audit/assets.manifest
    cd /project/audit
    sha256sum assets.manifest | awk '{print $1}' > assets.hash
else
    echo -e "\033[1;31m[!] Error: Falló la compilación o no se generó carpeta dist.\033[0m"; exit 1
fi

# 3. Descarga de red y comparación
# Instalamos python3 si falta para el script de descarga
apt-get update && apt-get install -y python3 > /dev/null 2>&1
./get_network_manifest.sh

echo -e "\n\033[0;34m--- MANIFIESTO LOCAL (COMPILADO AHORA) ---\033[0m"
cat assets.manifest
echo -e "\033[0;34m--- MANIFIESTO RED (DESCARGADO) ---\033[0m"
cat network_assets.manifest

LOCAL_SIG=$(cat assets.hash)
NET_ROOT_HASH=$(sha256sum network_assets.manifest | awk '{print $1}')

echo -e "\n\033[1;36m---------------------------------------------------------------\033[0m"
echo -e "FIRMA LOCAL: \033[0;36m$LOCAL_SIG\033[0m"
echo -e "FIRMA RED:   \033[0;36m$NET_ROOT_HASH\033[0m"

if [ "$LOCAL_SIG" == "$NET_ROOT_HASH" ]; then
    echo -e "\033[1;32mVERDICTO FINAL: [ OK ] INTEGRIDAD CONFIRMADA\033[0m"
else
    echo -e "\033[1;31mVERDICTO FINAL: [ ERROR ] EL CÓDIGO DEL REPO NO COINCIDE CON LA RED\033[0m"
    exit 1
fi