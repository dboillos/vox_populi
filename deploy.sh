#!/bin/bash

# Comprobación de argumentos
if [ -z "$1" ]; then
    echo -e "\033[0;31mError: Debes proporcionar un tag (ej: v1.0.1)\033[0m"
    echo "Uso: ./deploy.sh <tag>"
    exit 1
fi

NEW_TAG=$1
TEMP_LOCAL=".hash_local"
TEMP_RED=".hash_red"

echo -e "\033[0;34mIniciando despliegue para el tag: $NEW_TAG\033[0m"

# === 1. PREPARACIÓN Y GIT ===
echo -e "\n[1/5] Limpiando y compilando..."
rm -rf dist src/vox_populi_frontend/dist .dfx/ic
npm run build

echo -e "\n[2/5] Registrando en Git..."
git add .
git commit -m "release: despliegue verificado $NEW_TAG"
git tag -a "$NEW_TAG" -m "Release $NEW_TAG" 2>/dev/null || echo -e "\033[0;33mNota: El tag ya existe localmente\033[0m"
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

# FRONTEND: Assets
dfx deploy --network ic vox_populi_frontend

# === 4. VERIFICACIÓN FINAL ===
echo -e "\n[5/5] --- INICIANDO AUDITORÍA DE INTEGRIDAD ---"

# --- VERIFICACIÓN BACKEND ---
HASH_BACKEND_LOCAL=$(sha256sum .dfx/ic/canisters/vox_populi_backend/vox_populi_backend.wasm | awk '{print $1}')
HASH_BACKEND_RED=$(dfx canister --network ic --identity anonymous info vox_populi_backend | grep "Module hash" | sed 's/.*0x//')

# --- VERIFICACIÓN FRONTEND ---
find src/vox_populi_frontend/dist -type f ! -name ".ic-assets.json5" -exec sha256sum {} + | awk '{print $1}' | LC_ALL=C sort > $TEMP_LOCAL
dfx canister --network ic --identity anonymous call vox_populi_frontend list '(record {})' | \
awk '/record \{/,/\};/ { if ($0 ~ /sha256 = opt blob/) hash=$0; if ($0 ~ /content_encoding = "identity"/) print hash }' | \
sed 's/.*blob "\(.*\)".*/\1/' | sed 's/\\//g' | LC_ALL=C sort > $TEMP_RED

# === RESULTADO FINAL ===
echo -e "\n======================================="
VERDICT_BACKEND=false
VERDICT_FRONTEND=false

if [ "$HASH_BACKEND_LOCAL" == "$HASH_BACKEND_RED" ]; then
    echo -e "\033[0;32m[OK] BACKEND VERIFICADO (Match Total)\033[0m"
    VERDICT_BACKEND=true
else
    echo -e "\033[0;31m[FAIL] BACKEND NO COINCIDE\033[0m"
fi

if cmp -s "$TEMP_LOCAL" "$TEMP_RED"; then
    echo -e "\033[0;32m[OK] FRONTEND VERIFICADO (Match Total)\033[0m"
    VERDICT_FRONTEND=true
else
    echo -e "\033[0;31m[FAIL] FRONTEND NO COINCIDE\033[0m"
    echo "Diferencias encontradas:"
    diff $TEMP_LOCAL $TEMP_RED
fi

echo -e "======================================="

if [ "$VERDICT_BACKEND" = true ] && [ "$VERDICT_FRONTEND" = true ]; then
    echo -e "\033[1;32m¡MATCH TOTAL! El despliegue es 100% íntegro.\033[0m"
else
    echo -e "\033[1;31mADVERTENCIA: Hay discrepancias en el despliegue.\033[0m"
fi

# Limpieza
rm $TEMP_LOCAL $TEMP_RED
