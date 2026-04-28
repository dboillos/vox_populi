#!/bin/bash

if [ -z "$1" ]; then
    echo -e "\033[0;31mError: Proporciona un tag (ej: v1.2.42)\033[0m"
    exit 1
fi

NEW_TAG=$1
WASM_PATH=".dfx/ic/canisters/vox_populi_backend/vox_populi_backend.wasm"

echo -e "\n\033[0;34m[1/3] Compilando Backend Determinista con Docker...\033[0m"
# Limpieza específica para el backend
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

echo -e "\n\033[0;34m[3/3] Desplegando en la Red IC...\033[0m"
dfx identity use prod_deployer
export DFX_WARNING=-mainnet_plaintext_identity

# Instalación manual del WASM generado por Linux
dfx canister --network ic install vox_populi_backend --mode upgrade --wasm "$WASM_PATH" --wasm-memory-persistence keep

echo -e "\n\033[0;32m=== VERIFICACIÓN DE HASH FINAL ===\033[0m"
HASH_RED=$(dfx canister --network ic --identity anonymous info vox_populi_backend | grep "Module hash" | sed 's/.*0x//')
echo "HASH ACTUAL EN IC: $HASH_RED"
