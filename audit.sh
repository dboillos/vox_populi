#!/bin/bash

# Colores para la terminal
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${BLUE}===============================================================${NC}"
echo -e "${BLUE}             SISTEMA DE AUDITORÍA VOX POPULI                 ${NC}"
echo -e "${BLUE}===============================================================${NC}"

# 1. Verificación de Docker
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}Error: Docker no está corriendo.${NC}"
    exit 1
fi

# 2. Compilación Determinista
echo -e "\n${CYAN}[1/3] Generando binario local con Docker...${NC}"
# Limpiamos solo el rastro del backend para asegurar una compilación fresca
rm -rf .dfx/ic/canisters/vox_populi_backend

# Usamos la imagen que ya tenemos configurada
docker run --rm -v "$(pwd)":/project vox_populi_backend_builder || { 
    echo -e "${RED}Fallo en la compilación de Docker.${NC}"; 
    exit 1; 
}

WASM_LOCAL=".dfx/ic/canisters/vox_populi_backend/vox_populi_backend.wasm"

if [ ! -f "$WASM_LOCAL" ]; then
    echo -e "${RED}Error: No se generó el archivo .wasm.${NC}"
    exit 1
fi

# 3. Obtención de Hashes
echo -e "\n${CYAN}[2/3] Calculando hashes...${NC}"

HASH_LOCAL=$(sha256sum "$WASM_LOCAL" | awk '{print $1}')
HASH_RED=$(dfx canister --network ic --identity anonymous info vox_populi_backend | grep "Module hash" | sed 's/.*0x//')

# 4. Veredicto Final
echo -e "\n${CYAN}[3/3] Comparación de integridad:${NC}"
echo -e "---------------------------------------------------------------"
echo -e "HASH LOCAL: ${CYAN}$HASH_LOCAL${NC}"
echo -e "HASH EN RED: ${CYAN}$HASH_RED${NC}"
echo -e "---------------------------------------------------------------"

if [ "$HASH_LOCAL" == "$HASH_RED" ]; then
    echo -e "${GREEN}VERDICT: [ MATCH ]${NC}"
    echo -e "${GREEN}El código local es idéntico al código ejecutándose en la IC.${NC}"
else
    echo -e "${RED}VERDICT: [ FAIL ]${NC}"
    echo -e "${RED}¡ALERTA! El código local NO coincide con el de la red.${NC}"
fi
echo -e "${BLUE}===============================================================${NC}\n"
