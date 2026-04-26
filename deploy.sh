#!/bin/bash

# Comprobación de argumentos
if [ -z "$1" ]; then
    echo "Error: Debes proporcionar un tag (ej: v1.0.1)"
    echo "Uso: ./deploy.sh <tag>"
    exit 1
fi

NEW_TAG=$1

echo "Iniciando despliegue para el tag: $NEW_TAG"

# === 1. PREPARACIÓN Y GIT ===
echo -e "\n[1/5] Limpiando y compilando..."
rm -rf dist src/vox_populi_frontend/dist .dfx/ic
npm run build

echo -e "\n[2/5] Registrando en Git..."
git add .
git commit -m "release: despliegue verificado $NEW_TAG"
git tag -a "$NEW_TAG" -m "Release $NEW_TAG"
git push origin main --tags

# === 2. BUILD Y CHECK ===
echo -e "\n[3/5] Ejecutando dfx build check..."
dfx build --network ic --check

# === 3. DESPLIEGUE EN IC ===
echo -e "\n[4/5] Desplegando en Internet Computer..."
dfx identity use prod_deployer
export DFX_WARNING=-mainnet_plaintext_identity

# BACKEND: Modo Upgrade
dfx canister --network ic install vox_populi_backend \
  --mode upgrade \
  --wasm .dfx/ic/canisters/vox_populi_backend/vox_populi_backend.wasm \
  --wasm-memory-persistence keep

# OPCIÓN B (COMENTADA POR SEGURIDAD):
# dfx canister --network ic install vox_populi_backend --mode reinstall --wasm .dfx/ic/canisters/vox_populi_backend/vox_populi_backend.wasm

# FRONTEND: Assets
dfx deploy --network ic vox_populi_frontend

# === 4. VERIFICACIÓN FINAL ===
echo -e "\n[5/5] --- VERIFICACIÓN DE INTEGRIDAD ---"

echo -e "\n--- BACKEND ---"
echo "LOCAL (Wasm):"
sha256sum .dfx/ic/canisters/vox_populi_backend/vox_populi_backend.wasm
echo "RED (Module):"
dfx canister --network ic --identity anonymous info vox_populi_backend | grep "Module hash"

echo -e "\n--- FRONTEND (LISTA DE HASHES) ---"
echo "LISTA LOCAL:"
find src/vox_populi_frontend/dist -type f ! -name ".ic-assets.json5" -exec sha256sum {} + | awk '{print $1}' | LC_ALL=C sort
echo "LISTA EN RED:"
dfx canister --network ic --identity anonymous call vox_populi_frontend list '(record {})' | \
awk '/record \{/,/\};/ { if ($0 ~ /sha256 = opt blob/) hash=$0; if ($0 ~ /content_encoding = "identity"/) print hash }' | \
sed 's/.*blob "\(.*\)".*/\1/' | sed 's/\\//g' | LC_ALL=C sort

echo -e "\nProceso finalizado para $NEW_TAG"
