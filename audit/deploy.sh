#!/bin/bash
# Ubicación: /audit/deploy.sh
# Objetivo: Despliegue con compilación y auditoría 100% delegada a Docker.

# --- 1. VALIDACIÓN DE ENTRADA Y ENTORNO ---
if [ -z "$1" ]; then
    echo -e "\033[0;31mError: Proporciona un tag (ej: v1.2.60)\033[0m"
    exit 1
fi

NEW_TAG=$1
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

echo -e "\n\033[1;34m[1/6] FASE 0: PRE-FLIGHT CHECKS\033[0m"
if ! docker info > /dev/null 2>&1; then
    echo -e "\033[0;31m[!] Error: Docker no está corriendo.\033[0m"; exit 1
fi

chmod +x internal_audit.sh get_network_manifest.sh

# --- 2. CONSTRUCCIÓN DE LA IMAGEN ---
echo -e "\n\033[1;34m[2/6] FASE 1: CONSTRUYENDO ENTORNO vox_populi_auditor\033[0m"
docker build -t vox_populi_auditor .

# --- 3. COMPILACIÓN DETERMINISTA (DOCKER) ---
echo -e "\n\033[1;34m[3/6] FASE 2: COMPILACIÓN BACKEND EN DOCKER\033[0m"
docker run --rm -v "$SCRIPT_DIR/..":/project vox_populi_auditor /bin/bash -c "rm -rf .dfx/ic/canisters/vox_populi_backend && dfx build --network ic vox_populi_backend"

# --- 4. DESPLIEGUE A MAINNET (HOST - Necesita tus llaves) ---
echo -e "\n\033[1;34m[4/6] FASE 3: DESPLIEGUE EN INTERNET COMPUTER\033[0m"
dfx identity use prod_deployer
export DFX_WARNING=-mainnet_plaintext_identity

# Desplegamos usando el WASM recién generado por Docker
dfx canister --network ic install vox_populi_backend --mode upgrade --wasm "../.dfx/ic/canisters/vox_populi_backend/vox_populi_backend.wasm" --wasm-memory-persistence keep
dfx deploy --network ic vox_populi_frontend --no-wallet

# --- 5. EVIDENCIAS Y GIT (DOCKER + HOST) ---
echo -e "\n\033[1;34m[5/6] FASE 4: FIRMA DE ASSETS Y NOTARÍA GIT\033[0m"

# Delegamos el escaneo y firma a Docker para asegurar que los hashes sean "Linux-standard"
docker run --rm -v "$SCRIPT_DIR/..":/project -w /project/audit vox_populi_auditor /bin/bash -c "
    FRONTEND_DIST=\$(find /project -name 'index.html' | grep -E 'dist|build' | head -n 1 | xargs dirname)
    cd \"\$FRONTEND_DIST\"
    find . -type f ! -name '*.map' ! -name '*.json5' ! -name '*.json' | sort | while read -r file; do
        hash=\$(sha256sum \"\$file\" | awk '{print \$1}')
        echo \"\$hash  \${file#./}\"
    done > /project/audit/assets.manifest
    cd /project/audit
    sha256sum assets.manifest | awk '{print \$1}' > assets.hash
"

# Git sí ocurre en el Host (donde tienes tus credenciales de GitHub)
cd ..
git add .
git commit -m "release: $NEW_TAG"
git tag -a "$NEW_TAG" -m "Firma: $(cat audit/assets.hash 2>/dev/null)"
git push origin main --tags --force
cd audit

# --- 6. AUDITORÍA FINAL (DOCKER) ---
# Usamos exactamente el mismo script que usará el auditor en Venus
docker run --rm \
    -v "$SCRIPT_DIR/..":/project \
    -w /project/audit \
    vox_populi_auditor \
    ./internal_audit.sh