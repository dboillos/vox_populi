#!/bin/bash
# VERSION: v1.2.50-TFM-REAL-AUDIT
# DESCRIPCIÓN: Verificación cruzada exacta de Backend y Frontend (Red vs Local)

if [ -z "$1" ]; then
    echo -e "\033[0;31mError: Proporciona un tag (ej: v1.2.50)\033[0m"
    exit 1
fi

NEW_TAG=$1
WASM_PATH=".dfx/ic/canisters/vox_populi_backend/vox_populi_backend.wasm"

echo -e "\n\033[0;34m[1/4] Compilando Backend Determinista con Docker...\033[0m"
docker run --rm -v "$(pwd)":/project vox_populi_backend_builder /bin/bash -c "rm -rf .dfx/ic/canisters/vox_populi_backend && dfx build --network ic vox_populi_backend"

echo -e "\n\033[0;34m[2/4] Generando Certificación Local de Frontend...\033[0m"
if [ -d "src/vox_populi_frontend" ]; then
    cd src/vox_populi_frontend
    npm install && npm run build --no-scripts || true
    cd ../..
fi

FRONTEND_DIST=$(find src/vox_populi_frontend/dist src/vox_populi_frontend/build dist/vox_populi_frontend -name "index.html" -exec dirname {} \; 2>/dev/null | head -n 1)

if [ -d "$FRONTEND_DIST" ]; then
    cd "$FRONTEND_DIST"
    # Manifiesto Local: Formato "hash nombre"
    find . -type f ! -name "*.map" -exec sha256sum {} + | sed 's| \./| |' | sort > ../../../assets.manifest
    cd ../../..
    LOCAL_ROOT_HASH=$(sha256sum assets.manifest | awk '{print $1}')
    echo "$LOCAL_ROOT_HASH" > assets.hash
else
    echo -e "\033[0;31mError: No se localizaron assets locales.\033[0m"; exit 1
fi

echo -e "\n\033[0;34m[3/4] Sincronizando Git y Tag...\033[0m"
git add .
git commit -m "release: $NEW_TAG (Integrity Audit)"
git tag -d "$NEW_TAG" 2>/dev/null
git tag -a "$NEW_TAG" -m "$NEW_TAG"
git push origin main --tags --force

echo -e "\n\033[0;34m[4/4] Desplegando en Mainnet...\033[0m"
dfx identity use prod_deployer
export DFX_WARNING=-mainnet_plaintext_identity
dfx canister --network ic install vox_populi_backend --mode upgrade --wasm "$WASM_PATH" --wasm-memory-persistence keep
dfx deploy --network ic vox_populi_frontend --no-wallet

echo -e "\n\033[1;35m===============================================================\033[0m"
echo -e "\033[1;35m             AUDITORÍA DE INTEGRIDAD DEL BACKEND             \033[0m"
echo -e "\033[1;35m===============================================================\033[0m"
HASH_LOCAL_BE=$(sha256sum "$WASM_PATH" | awk '{print $1}')
HASH_RED_BE=$(dfx canister --network ic --identity anonymous info vox_populi_backend | grep "Module hash" | sed 's/.*0x//')
echo -e "HASH LOCAL (DOCKER): \033[0;36m$HASH_LOCAL_BE\033[0m"
echo -e "HASH EN RED (IC):    \033[0;36m$HASH_RED_BE\033[0m"
[ "$HASH_LOCAL_BE" == "$HASH_RED_BE" ] && echo -e "\033[1;32mRESULTADO BACKEND: [ OK ] - COINCIDENCIA TOTAL\033[0m"

echo -e "\n\033[1;36m===============================================================\033[0m"
echo -e "\033[1;36m             AUDITORÍA DETALLADA DEL FRONTEND                \033[0m"
echo -e "\033[1;36m===============================================================\033[0m"
echo "Consultando hashes directamente a la Mainnet..."

# USAMOS UN SCRIPT DE NODE.JS TEMPORAL PARA EXTRAER LOS HASHES DE RED SIN ERRORES DE PARSEO
node - e "
const { execSync } = require('child_process');
const raw = execSync('dfx canister --network ic --identity anonymous call vox_populi_frontend list \"(record {})\"').toString();
const matches = raw.matchAll(/key = \"(.*?)\";.*?content_hash = opt blob \"(.*?)\"/gs);
let output = [];
for (const m of matches) {
    const name = m[1].startsWith('/') ? m[1].substring(1) : m[1];
    const hash = m[2].replace(/\\\\/g, '').split('').map(c => c.charCodeAt(0).toString(16).padStart(2, '0')).join('');
    output.push(hash.substring(0, 64) + ' ' + name);
}
console.log(output.sort().join('\n'));
" > network_assets.manifest

echo -e "\033[1;33mCOMPARATIVA DE ARCHIVOS (HASH | NOMBRE):\033[0m"
echo -e "\033[0;34m--- DATOS LOCALES ---\033[0m"
cat assets.manifest
echo -e "\033[0;34m--- DATOS EN RED ---\033[0m"
cat network_assets.manifest

echo -e "\033[1;36m---------------------------------------------------------------\033[0m"
NET_ROOT_HASH=$(sha256sum network_assets.manifest | awk '{print $1}')
echo -e "FIRMA GLOBAL (LOCAL): \033[0;36m$(cat assets.hash)\033[0m"
echo -e "FIRMA GLOBAL (RED):   \033[0;36m$NET_ROOT_HASH\033[0m"

if [ "$(cat assets.hash)" == "$NET_ROOT_HASH" ]; then
    echo -e "\033[1;32mRESULTADO FRONTEND: [ OK ] - ARCHIVOS IDÉNTICOS\033[0m"
else
    echo -e "\033[1;31mRESULTADO FRONTEND: [ ERROR ] - DISCREPANCIA EN ACTIVOS\033[0m"
fi
echo -e "\033[1;36m===============================================================\033[0m\n"