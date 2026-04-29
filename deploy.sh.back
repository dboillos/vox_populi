#!/bin/bash

if [ -z "$1" ]; then
    echo -e "\033[0;31mError: Proporciona un tag (ej: v1.2.40)\033[0m"
    exit 1
fi

NEW_TAG=$1
WASM_PATH=".dfx/ic/canisters/vox_populi_backend/vox_populi_backend.wasm"

echo -e "\n\033[0;34m[1/3] Compilando Backend Determinista con Docker...\033[0m"
rm -rf .dfx/ic/canisters/vox_populi_backend

docker build -t vox_populi_backend_builder .
docker run --rm -v "$(pwd)":/project vox_populi_backend_builder || { echo "Docker falló"; exit 1; }

if [ ! -f "$WASM_PATH" ]; then
    echo -e "\033[0;31mError: No se encontró el WASM generado por Docker.\033[0m"
    exit 1
fi

echo -e "\n\033[0;34m[2/3] Actualizando Git y Tag...\033[0m"
git add .
git commit -m "release: $NEW_TAG (backend deterministic)"
git tag -a "$NEW_TAG" -m "$NEW_TAG"
git push origin main --tags

echo -e "\n\033[0;34m[3/3] Desplegando y Verificando...\033[0m"
dfx identity use prod_deployer
export DFX_WARNING=-mainnet_plaintext_identity

# Instalación
dfx canister --network ic install vox_populi_backend --mode upgrade --wasm "$WASM_PATH" --wasm-memory-persistence keep

# --- FASE DE COMPARACIÓN LÓGICA ---
echo -e "\n\033[1;35m===============================================================\033[0m"
echo -e "\033[1;35m             AUDITORÍA DE INTEGRIDAD DEL BACKEND             \033[0m"
echo -e "\033[1;35m===============================================================\033[0m"

# Obtener Hash Local (Docker)
HASH_LOCAL=$(sha256sum "$WASM_PATH" | awk '{print $1}')
echo -e "HASH LOCAL (DOCKER): \033[0;36m$HASH_LOCAL\033[0m"

# Obtener Hash de la Red (IC)
HASH_RED=$(dfx canister --network ic --identity anonymous info vox_populi_backend | grep "Module hash" | sed 's/.*0x//')
echo -e "HASH EN RED (MAINNET): \033[0;36m$HASH_RED\033[0m"

echo -e "\033[1;35m---------------------------------------------------------------\033[0m"

if [ "$HASH_LOCAL" == "$HASH_RED" ]; then
    echo -e "\033[1;32mRESULTADO: [ OK ] - LOS HASHES COINCIDEN BIT A BIT\033[0m"
    echo -e "\033[1;32mEl despliegue es 100% determinista y verificable.\033[0m"
else
    echo -e "\033[1;31mRESULTADO: [ ERROR ] - LOS HASHES NO COINCIDEN\033[0m"
    echo -e "\033[1;31mCuidado: El binario en la red no es el que generó Docker.\033[0m"
fi
echo -e "\033[1;35m===============================================================\033[0m"
