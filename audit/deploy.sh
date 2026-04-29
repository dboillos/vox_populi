#!/bin/bash
# Ubicación: /audit/deploy.sh (Host)

if [ -z "$1" ]; then
    echo -e "\033[0;31mError: Proporciona un tag (ej: v1.2.62)\033[0m"
    exit 1
fi

NEW_TAG=$1
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# --- FASE 0: PRE-FLIGHT & BUILD ---
echo -e "\n\033[1;34m[1/6] FASE 0: VALIDANDO REQUISITOS DEL HOST\033[0m"

# 1. Check Docker
if ! docker info > /dev/null 2>&1; then
    echo -e "\033[0;31m[!] Error: Docker no está corriendo.\033[0m"; exit 1
fi

# 2. Check DFX en Host (Necesario para Fase 2)
if ! command -v dfx &> /dev/null; then
    echo -e "\033[0;31m[!] Error: dfx no está instalado en el Host (necesario para deploy).\033[0m"; exit 1
fi

# 3. Check Git en Host (Necesario para Fase 4)
if ! command -v git &> /dev/null; then
    echo -e "\033[0;31m[!] Error: git no está instalado en el Host.\033[0m"; exit 1
fi

# Construir/Actualizar imagen de auditoría
echo -e "\033[0;32mActualizando entorno de auditoría Docker...\033[0m"
docker build -t vox_populi_auditor .
chmod +x internal_audit.sh get_network_manifest.sh

# --- FASE 1: COMPILACIÓN (100% DOCKER) ---
echo -e "\n\033[1;34m[2/6] FASE 1: COMPILACIÓN BACKEND (DOCKER)\033[0m"
# Forzamos el uso del binario dfx INTERNO del contenedor
docker run --rm \
    -v "$SCRIPT_DIR/..":/project \
    --entrypoint /bin/bash \
    vox_populi_auditor -c "rm -rf .dfx/ic/canisters/vox_populi_backend && dfx build --network ic vox_populi_backend"

# --- FASE 2: DESPLIEGUE (HOST + IDENTIDAD) ---
echo -e "\n\033[1;34m[3/6] FASE 2: DESPLIEGUE A MAINNET\033[0m"
dfx identity use prod_deployer
export DFX_WARNING=-mainnet_plaintext_identity

# Instalamos el WASM que Docker acaba de generar
dfx canister --network ic install vox_populi_backend --mode upgrade --wasm "../.dfx/ic/canisters/vox_populi_backend/vox_populi_backend.wasm" --wasm-memory-persistence keep
dfx deploy --network ic vox_populi_frontend --no-wallet

# --- FASE 3: FIRMA (DOCKER) ---
echo -e "\n\033[1;34m[4/6] FASE 3: GENERANDO FIRMA CRIPTOGRÁFICA (DOCKER)\033[0m"
docker run --rm \
    -v "$SCRIPT_DIR/..":/project \
    -w /project/audit \
    --entrypoint /bin/bash \
    vox_populi_auditor -c "
    FRONTEND_DIST=\$(find /project -name 'index.html' | grep -E 'dist|build' | head -n 1 | xargs dirname)
    cd \"\$FRONTEND_DIST\" && find . -type f ! -name '*.map' ! -name '*.json5' ! -name '*.json' | sort | while read -r file; do
        hash=\$(sha256sum \"\$file\" | awk '{print \$1}')
        echo \"\$hash  \${file#./}\"
    done > /project/audit/assets.manifest
    cd /project/audit && sha256sum assets.manifest | awk '{print \$1}' > assets.hash
"

# --- FASE 4: GIT (HOST) ---
echo -e "\n\033[1;34m[5/6] FASE 4: NOTARÍA GIT\033[0m"
cd ..
git add .
git commit -m "release: $NEW_TAG"
git tag -a "$NEW_TAG" -m "Firma: $(cat audit/assets.hash 2>/dev/null)"
git push origin main --tags --force
cd audit

# --- FASE 5: AUDITORÍA FINAL (DOCKER) ---
echo -e "\n\033[1;34m[6/6] FASE 5: VALIDACIÓN INTEGRAL EN CONTENEDOR\033[0m"
docker run --rm \
    -v "$SCRIPT_DIR/..":/project \
    -w /project/audit \
    --entrypoint /bin/bash \
    vox_populi_auditor \
    ./internal_audit.sh