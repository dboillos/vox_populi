#!/bin/bash

# Colores
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}===============================================================${NC}"
echo -e "${BLUE}             SISTEMA DE AUDITORÍA VOX POPULI                 ${NC}"
echo -e "${BLUE}===============================================================${NC}"

# 1. COMPROBACIÓN DE DOCKER (OBLIGATORIO)
if ! command -v docker &> /dev/null; then
    echo -e "${RED}ERROR: Docker no detectado. Es imprescindible para el determinismo.${NC}"
    exit 1
fi

# 2. COMPROBACIÓN DE DFX (OPCIONAL PARA COMPARACIÓN AUTOMÁTICA)
HAS_DFX=true
if ! command -v dfx &> /dev/null; then
    echo -e "${YELLOW}AVISO: 'dfx' no está instalado. No podré consultar la red automáticamente.${NC}"
    HAS_DFX=false
fi

# 3. COMPILACIÓN DETERMINISTA
echo -e "\n${CYAN}[1/3] Generando binario local con Docker...${NC}"
# Limpieza de builds previos
rm -rf .dfx/ic/canisters/vox_populi_backend

# Ejecución del contenedor
docker run --rm -v "$(pwd)":/project vox_populi_backend_builder || { 
    echo -e "${RED}ERROR: Docker falló. Asegúrate de tener la imagen 'vox_populi_backend_builder' creada.${NC}"
    exit 1; 
}

WASM_LOCAL=".dfx/ic/canisters/vox_populi_backend/vox_populi_backend.wasm"

# 4. VEREDICTO
echo -e "\n${CYAN}[2/3] Cálculo de Hash Local...${NC}"
if [ ! -f "$WASM_LOCAL" ]; then
    echo -e "${RED}ERROR: No se encontró el archivo .wasm generado.${NC}"
    exit 1
fi

HASH_LOCAL=$(sha256sum "$WASM_LOCAL" | awk '{print $1}')
echo -e "HASH LOCAL: ${GREEN}$HASH_LOCAL${NC}"

echo -e "\n${CYAN}[3/3] Comparación con la Red (Mainnet)...${NC}"
if [ "$HAS_DFX" = true ]; then
    # Consultar a la red de forma anónima
    HASH_RED=$(dfx canister --network ic --identity anonymous info vox_populi_backend 2>/dev/null | grep "Module hash" | sed 's/.*0x//')
    
    if [ -z "$HASH_RED" ]; then
        echo -e "${RED}ERROR: No se pudo conectar con el Internet Computer o el canister no existe.${NC}"
    else
        echo -e "HASH EN RED: ${GREEN}$HASH_RED${NC}"
        echo -e "---------------------------------------------------------------"
        if [ "$HASH_LOCAL" == "$HASH_RED" ]; then
            echo -e "${GREEN}VEREDICTO: [ MATCH ] - Integridad confirmada.${NC}"
        else
            echo -e "${RED}VEREDICTO: [ FAIL ] - El binario local NO coincide con el de la red.${NC}"
        fi
    fi
else
    echo -e "${YELLOW}Comparación automática saltada (falta dfx).${NC}"
    echo -e "Compara manualmente el HASH LOCAL con el que esperas en la red."
fi

echo -e "${BLUE}===============================================================${NC}\n"