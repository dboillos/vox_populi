#!/bin/bash
# Ubicación: /audit/internal_audit.sh (Dentro de Docker)
# Objetivo: Auditoría autónoma "Zero Trust" desde el código fuente.

# 1. Navegar a la raíz del proyecto para asegurar contexto global
# El contenedor arranca en /project/audit, subimos uno para ver todo el código
cd ..
ROOT_DIR=$(pwd)

echo -e "\n\033[1;34m[PASO 0] PREPARANDO ENTORNO LIMPIO EN CONTENEDOR\033[0m"
echo -e "Directorio raíz: $ROOT_DIR"

# Limpieza radical para evitar que restos de compilaciones de Mac afecten a Venus
echo "Eliminando rastros de compilaciones previas..."
rm -rf .dfx dist node_modules src/declarations

# Instalación de dependencias
echo "Instalando dependencias de Node (npm install)..."
npm install --quiet > /dev/null 2>&1

# Generación de declaraciones (Crucial para que el Frontend sepa hablar con el Backend)
echo "Generando interfaces de canisters (dfx generate)..."
dfx generate vox_populi_backend > /dev/null 2>&1

# --- FASE 1: AUDITORÍA DE BACKEND (WASM) ---
echo -e "\n\033[1;34m[1/2] FASE 1: AUDITORÍA DE BACKEND\033[0m"

echo "Compilando Backend en entorno Ubuntu 24.04 determinista..."
dfx build --network ic vox_populi_backend > /dev/null 2>&1

# Localizar el binario generado
WASM_PATH=$(find "$ROOT_DIR/.dfx/ic/canisters/vox_populi_backend" -name "vox_populi_backend.wasm" 2>/dev/null)

if [ -f "$WASM_PATH" ]; then
    HASH_LOCAL_BE=$(sha256sum "$WASM_PATH" | awk '{print $1}')
    
    echo "Consultando Hash actual en la red Internet Computer..."
    HASH_RED_BE=$(dfx canister --network ic --identity anonymous info vox_populi_backend 2>/dev/null | grep 'Module hash' | sed 's/.*0x//')
    
    echo -e "HASH GENERADO (DOCKER): \033[0;36m$HASH_LOCAL_BE\033[0m"
    echo -e "HASH EN MAINNET:        \033[0;36m$HASH_RED_BE\033[0m"
    
    if [ "$HASH_LOCAL_BE" == "$HASH_RED_BE" ]; then
        echo -e "\033[1;32mRESULTADO BACKEND: [ OK ] - COINCIDENCIA TOTAL\033[0m"
    else
        echo -e "\033[1;31mRESULTADO BACKEND: [ ERROR ] - DISCREPANCIA DETECTADA\033[0m"
        BACKEND_FAIL=true
    fi
else
    echo -e "\033[1;31m[!] ERROR CRÍTICO: El compilador no generó el archivo .wasm\033[0m"
    exit 1
fi

# --- FASE 2: AUDITORÍA DE FRONTEND (ASSETS) ---
echo -e "\n\033[1;34m[2/2] FASE 2: AUDITORÍA DE FRONTEND\033[0m"

echo "Compilando activos del Frontend..."
npm run build > /dev/null 2>&1

# Localizar la carpeta de salida (dist)
FRONTEND_DIST=$(find "$ROOT_DIR" -name "index.html" | grep "dist" | head -n 1 | xargs dirname)

if [ -d "$FRONTEND_DIST" ]; then
    echo -e "Carpeta de distribución hallada en: $FRONTEND_DIST"
    
    # Crear manifiesto local de archivos compilados
    cd "$FRONTEND_DIST"
    find . -type f ! -name "*.map" ! -name "*.json5" ! -name "*.json" | sort | while read -r file; do
        hash=$(sha256sum "$file" | awk '{print $1}')
        echo "$hash  ${file#./}"
    done > "$ROOT_DIR/audit/assets.manifest"
    
    # Calcular firma global
    cd "$ROOT_DIR/audit"
    sha256sum assets.manifest | awk '{print $1}' > assets.hash
    
    # Descargar manifiesto de la red
    echo "Descargando activos reales de la red para comparación..."
    ./get_network_manifest.sh > /dev/null 2>&1
    
    LOCAL_SIG=$(cat assets.hash)
    NET_ROOT_HASH=$(sha256sum network_assets.manifest | awk '{print $1}')

    echo -e "FIRMA LOCAL (DOCKER): \033[0;36m$LOCAL_SIG\033[0m"
    echo -e "FIRMA RED (DESCARGA): \033[0;36m$NET_ROOT_HASH\033[0m"

    if [ "$LOCAL_SIG" == "$NET_ROOT_HASH" ]; then
        echo -e "\033[1;32mRESULTADO FRONTEND: [ OK ] - INTEGRIDAD CONFIRMADA\033[0m"
    else
        echo -e "\033[1;31mRESULTADO FRONTEND: [ ERROR ] - LOS ARCHIVOS NO COINCIDEN\033[0m"
        FRONTEND_FAIL=true
    fi
else
    echo -e "\033[1;31m[!] ERROR: No se encontró la carpeta 'dist' tras la compilación.\033[0m"
    exit 1
fi

# Salida final para el lanzador audit.sh
if [ "$BACKEND_FAIL" = true ] || [ "$FRONTEND_FAIL" = true ]; then
    exit 1
else
    exit 0
fi