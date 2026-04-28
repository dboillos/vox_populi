#!/bin/bash

if [ -z "$1" ]; then
    echo -e "\033[0;31mError: Proporciona un tag (ej: v1.2.36)\033[0m"
    exit 1
fi

NEW_TAG=$1
TEMP_LOCAL=".hash_local"
TEMP_RED=".hash_red"

echo -e "\033[0;34m[1/5] Compilación Determinista con Docker (Backend)...\033[0m"
docker build -t vox_populi_builder .
docker run --rm -v "$(pwd)":/project vox_populi_builder

echo -e "\n\033[0;34m[2/5] Compilación de Frontend y Git...\033[0m"
cd src/vox_populi_frontend && npm install && npm run build && cd ../..
git add .
git commit -m "release: $NEW_TAG (deterministic build)"
git tag -a "$NEW_TAG" -m "Release $NEW_TAG"
git push origin main --tags

echo -e "\n\033[0;34m[3/5] Desplegando en Internet Computer...\033[0m"
dfx identity use prod_deployer
export DFX_WARNING=-mainnet_plaintext_identity

# Subir WASM generado por Docker
dfx canister --network ic install vox_populi_backend \
  --mode upgrade \
  --wasm .dfx/ic/canisters/vox_populi_backend/vox_populi_backend.wasm \
  --wasm-memory-persistence keep

# Subir Frontend
dfx deploy --network ic vox_populi_frontend

echo -e "\n\033[0;34m[4/5] Ejecutando Auditoría de Integridad...\033[0m"

# --- BACKEND ---
HASH_BACKEND_LOCAL=$(sha256sum .dfx/ic/canisters/vox_populi_backend/vox_populi_backend.wasm | awk '{print $1}')
HASH_BACKEND_RED=$(dfx canister --network ic --identity anonymous info vox_populi_backend | grep "Module hash" | sed 's/.*0x//')

# --- FRONTEND ---
find src/vox_populi_frontend/dist -type f ! -name ".ic-assets.json5" -exec sha256sum {} + | awk '{print $1}' | LC_ALL=C sort > $TEMP_LOCAL
dfx canister --network ic --identity anonymous call vox_populi_frontend list '(record {})' | \
awk '/record \{/,/\};/ { if ($0 ~ /sha256 = opt blob/) hash=$0; if ($0 ~ /content_encoding = "identity"/) print hash }' | \
sed 's/.*blob "\(.*\)".*/\1/' | sed 's/\\//g' | LC_ALL=C sort > $TEMP_RED

echo -e "\n======================================="
echo "BACKEND LOCAL (DOCKER): $HASH_BACKEND_LOCAL"
echo "BACKEND RED (IC):       $HASH_BACKEND_RED"

if [ "$HASH_BACKEND_LOCAL" == "$HASH_BACKEND_RED" ]; then
    echo -e "\033[0;32m[OK] BACKEND VERIFICADO\033[0m"
else
    echo -e "\033[0;31m[FAIL] BACKEND NO COINCIDE\033[0m"
fi

if cmp -s "$TEMP_LOCAL" "$TEMP_RED"; then
    echo -e "\033[0;32m[OK] FRONTEND VERIFICADO\033[0m"
else
    echo -e "\033[0;31m[FAIL] FRONTEND NO COINCIDE\033[0m"
    diff $TEMP_LOCAL $TEMP_RED
fi
echo -e "======================================="

rm $TEMP_LOCAL $TEMP_RED
