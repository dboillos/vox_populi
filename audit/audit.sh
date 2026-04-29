#!/bin/bash
# Ubicación: /audit/audit.sh
# Objetivo: Auditoría de integridad total con validación de dependencias.

# --- 1. VALIDACIÓN DE DEPENDENCIAS (FUNDAMENTAL) ---
check_dependency() {
    if ! command -v "$1" &> /dev/null; then
        echo -e "\033[0;31m[!] ERROR DE SISTEMA: No se encuentra '$1'.\033[0m"
        echo -e "\033[0;33mPara solucionar esto en Venus, instala dfx con:\033[0m"
        echo -e "sh -ci \"\$(curl -fsSL https://internetcomputer.org/install.sh)\"\n"
        exit 1
    fi
}

echo -e "\n\033[1;35m===============================================================\033[0m"
echo -e "\033[1;35m             AUDITORÍA DE INTEGRIDAD BAJO DEMANDA            \033[0m"
echo -e "\033[1;35m===============================================================\033[0m"

# Comprobamos herramientas antes de empezar
check_dependency "dfx"
check_dependency "python3"
check_dependency "sha256sum"
check_dependency "curl"

# --- 2. CONFIGURACIÓN DE RUTAS ---
# El WASM está un nivel arriba respecto a /audit
WASM_PATH="../.dfx/ic/canisters/vox_populi_backend/vox_populi_backend.wasm"
NETWORK_SCRIPT="./get_network_manifest.sh"

# --- 3. AUDITORÍA BACKEND ---
echo -e "\033[1;33m[1/2] Verificando integridad del Backend...\033[0m"
if [ -f "$WASM_PATH" ]; then
    HASH_LOCAL_BE=$(sha256sum "$WASM_PATH" | awk '{print $1}')
    HASH_RED_BE=$(dfx canister --network ic --identity anonymous info vox_populi_backend 2>/dev/null | grep "Module hash" | sed 's/.*0x//')
    
    if [ -z "$HASH_RED_BE" ]; then
        BE_STATUS="\033[1;31m[ ERROR: No se pudo conectar con la red o canister inexistente ]\033[0m"
    else
        echo -e "Hash Local: \033[0;36m$HASH_LOCAL_BE\033[0m"
        echo -e "Hash Red:   \033[0;36m$HASH_RED_BE\033[0m"
        if [ "$HASH_LOCAL_BE" == "$HASH_RED_BE" ]; then
            BE_STATUS="\033[1;32m[ OK: DETERMINISMO CONFIRMADO ]\033[0m"
        else
            BE_STATUS="\033[1;31m[ ERROR: DISCREPANCIA EN BINARIO ]\033[0m"
        fi
    fi
else
    BE_STATUS="\033[1;33m[ SALTADO: No existe el .wasm local en la ruta esperada ]\033[0m"
fi
echo -e "Resultado Backend: $BE_STATUS\n"

# --- 4. AUDITORÍA FRONTEND ---
echo -e "\033[1;33m[2/2] Verificando integridad del Frontend...\033[0m"
if [ -f "$NETWORK_SCRIPT" ]; then
    # Ejecutamos el script de descarga
    bash "$NETWORK_SCRIPT"
    
    if [ -f "assets.hash" ] && [ -f "network_assets.manifest" ]; then
        LOC_SIG=$(cat assets.hash)
        NET_SIG=$(sha256sum network_assets.manifest | awk '{print $1}')
        
        echo -e "Firma Local (Git): \033[0;36m$LOC_SIG\033[0m"
        echo -e "Firma Red (Venus): \033[0;36m$NET_SIG\033[0m"
        
        if [ "$LOC_SIG" == "$NET_SIG" ]; then
            FE_STATUS="\033[1;32m[ OK: INTEGRIDAD 100% ]\033[0m"
        else
            FE_STATUS="\033[1;31m[ ERROR: DISCREPANCIA DETECTADA ]\033[0m"
        fi
    else
        FE_STATUS="\033[1;31m[ ERROR: Faltan archivos de firma para comparar ]\033[0m"
    fi
else
    FE_STATUS="\033[1;31m[ ERROR: No se encuentra get_network_manifest.sh ]\033[0m"
fi
echo -e "Resultado Frontend: $FE_STATUS"

echo -e "\033[1;35m---------------------------------------------------------------\033[0m"
echo -e "AUDITORÍA FINALIZADA."
echo -e "\033[1;35m===============================================================\033[0m\n"