#!/bin/bash
# Ubicación: /audit/deploy.sh
# Objetivo: Despliegue con auditoría hermética. NO ELIMINAR BLOQUES DE SALIDA VISUAL.

# --- 1. VALIDACIÓN DE ENTRADA ---
if [ -z "$1" ]; then
    echo -e "\033[0;31mError: Proporciona un tag (ej: v1.2.60)\033[0m"
    exit 1
fi

NEW_TAG=$1
WASM_PATH="../.dfx/ic/canisters/vox_populi_backend/vox_populi_backend.wasm"

echo -e "\n\033[1;34m[1/6] FASE 0: PRE-FLIGHT CHECKS\033[0m"
if ! docker info > /dev/null 2>&1; then
    echo -e "\033[0;31m[!] Error: Docker no está corriendo.\033[0m"; exit 1
fi

# Dar permisos a los scripts antes de empezar
chmod +x audit.sh get_network_manifest.sh

# --- 2. CONSTRUCCIÓN DE LA IMAGEN ---
echo -e "\n\033[1;34m[2/6] FASE 1: CONSTRUYENDO ENTORNO vox_populi_auditor\033[0m"
docker build -t vox_populi_auditor .

# --- 3. COMPILACIÓN DETERMINISTA ---
echo -e "\n\033[1;34m[3/6] FASE 2: COMPILACIÓN BACKEND EN DOCKER\033[0m"
docker run --rm -v "$(pwd)/..":/project vox_populi_auditor /bin/bash -c "rm -rf .dfx/ic/canisters/vox_populi_backend && dfx build --network ic vox_populi_backend"

if [ ! -f "$WASM_PATH" ]; then
    echo -e "\033[0;31m[!] Error: El WASM no se generó.\033[0m"; exit 1
fi

# --- 4. DESPLIEGUE A MAINNET ---
echo -e "\n\033[1;34m[4/6] FASE 3: DESPLIEGUE EN INTERNET COMPUTER\033[0m"
dfx identity use prod_deployer
export DFX_WARNING=-mainnet_plaintext_identity

cd ..
dfx canister --network ic install vox_populi_backend --mode upgrade --wasm ".dfx/ic/canisters/vox_populi_backend/vox_populi_backend.wasm" --wasm-memory-persistence keep
dfx deploy --network ic vox_populi_frontend --no-wallet
cd audit

# --- 5. EVIDENCIAS Y GIT ---
echo -e "\n\033[1;34m[5/6] FASE 4: FIRMA DE ASSETS Y NOTARÍA GIT\033[0m"
FRONTEND_DIST=$(find ../src/vox_populi_frontend/dist ../src/vox_populi_frontend/build ../dist/vox_populi_frontend -name "index.html" -exec dirname {} \; 2>/dev/null | head -n 1)

if [ -d "$FRONTEND_DIST" ]; then
    cd "$FRONTEND_DIST"
    find . -type f ! -name "*.map" ! -name "*.json5" ! -name "*.json" | sort | while read -r file; do
        hash=$(sha256sum "$file" | awk '{print $1}')
        echo "$hash  ${file#./}"
    done > ../../../audit/assets.manifest
    cd ../../../audit
    sha256sum assets.manifest | awk '{print $1}' > assets.hash
else
    echo -e "\033[0;31m[!] Error: Carpeta dist no encontrada.\033[0m"; exit 1
fi

cd ..
git add .
git commit -m "release: $NEW_TAG"
git tag -a "$NEW_TAG" -m "Hash: $(cat audit/assets.hash 2>/dev/null)"
git push origin main --tags --force
cd audit

# --- 6. AUDITORÍA FINAL (ESTE ES EL BLOQUE QUE NO SE TOCA) ---
echo -e "\n\033[1;35m===============================================================\033[0m"
echo -e "\033[1;35m             AUDITORÍA DE INTEGRIDAD DEL BACKEND             \033[0m"
echo -e "\033[1;35m===============================================================\033[0m"

# Obtenemos hashes (Backend)
HASH_LOCAL_BE=$(sha256sum "$WASM_PATH" | awk '{print $1}')
HASH_RED_BE=$(dfx canister --network ic --identity anonymous info vox_populi_backend | grep "Module hash" | sed 's/.*0x//')

echo -e "HASH LOCAL: \033[0;36m$HASH_LOCAL_BE\033[0m"
echo -e "HASH RED:   \033[0;36m$HASH_RED_BE\033[0m"

if [ "$HASH_LOCAL_BE" == "$HASH_RED_BE" ]; then
    echo -e "RESULTADO BACKEND: \033[1;32m[ OK ] - DETERMINISMO CONFIRMADO\033[0m"
else
    echo -e "RESULTADO BACKEND: \033[1;31m[ ERROR ] - FALLO DE INTEGRIDAD\033[0m"
fi

echo -e "\n\033[1;36m===============================================================\033[0m"
echo -e "\033[1;36m             AUDITORÍA DE INTEGRIDAD DEL FRONTEND            \033[0m"
echo -e "\033[1;36m===============================================================\033[0m"

# Ejecutamos la auditoría de Frontend DENTRO del Docker para asegurar que Venus funcione igual
docker run --rm \
    -v "$(pwd)/..":/project \
    -w /project/audit \
    vox_populi_auditor \
    bash -c "./get_network_manifest.sh && \
    echo -e '\033[0;34m--- MANIFIESTO LOCAL ---\033[0m' && \
    cat assets.manifest && \
    echo -e '\033[0;34m--- MANIFIESTO RED (DESCARGADO) ---\033[0m' && \
    cat network_assets.manifest && \
    LOCAL_SIG=\$(cat assets.hash) && \
    NET_ROOT_HASH=\$(sha256sum network_assets.manifest | awk '{print \$1}') && \
    echo -e '\033[1;36m---------------------------------------------------------------\033[0m' && \
    echo -e 'FIRMA GLOBAL LOCAL: \033[0;36m'\$LOCAL_SIG'\033[0m' && \
    echo -e 'FIRMA GLOBAL RED:   \033[0;36m'\$NET_ROOT_HASH'\033[0m' && \
    if [ \"\$LOCAL_SIG\" == \"\$NET_ROOT_HASH\" ]; then \
        echo -e '\033[1;32mVERDICTO FRONTEND: [ OK ] - INTEGRIDAD 100% CONFIRMADA\033[0m'; \
    else \
        echo -e '\033[1;31mVERDICTO FRONTEND: [ ERROR ] - DISCREPANCIA DETECTADA\033[0m'; \
    fi"

echo -e "\033[1;36m===============================================================\033[0m\n"