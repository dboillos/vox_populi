#!/bin/bash
# ==============================================================================
# PROYECTO: Vox Populi
# SCRIPT: deploy.sh
# OBJETIVO: Despliegue determinista y certificación de integridad (Backend/Frontend)
# ==============================================================================

# Control de errores: El script se detiene si falta el parámetro del Tag
if [ -z "$1" ]; then
    echo -e "\033[0;31mError: Se requiere un Tag de versión (ej: v1.2.44)\033[0m"
    exit 1
fi

NEW_TAG=$1
WASM_PATH=".dfx/ic/canisters/vox_populi_backend/vox_populi_backend.wasm"

# --- PASO 1: COMPILACIÓN DETERMINISTA DEL BACKEND ---
# Se utiliza Docker para garantizar que el entorno de compilación sea idéntico
# independientemente del Sistema Operativo del desarrollador (reproducibilidad).
echo -e "\n\033[0;34m[1/4] Ejecutando entorno aislado (Docker) para compilación WASM...\033[0m"
rm -rf .dfx/ic/canisters/vox_populi_backend

docker build -t vox_populi_backend_builder .
docker run --rm -v "$(pwd)":/project vox_populi_backend_builder || { 
    echo "Fallo crítico: La compilación en Docker no ha sido exitosa."; exit 1; 
}

# --- PASO 2: CERTIFICACIÓN CRIPTOGRÁFICA DEL FRONTEND ---
# Generamos los activos estáticos y calculamos su huella digital única (Hash).
# Esto permite a terceros auditar que el frontend no ha sido alterado.
echo -e "\n\033[0;34m[2/4] Generando artefactos del Frontend y firma de integridad...\033[0m"

if [ -d "src/vox_populi_frontend" ]; then
    cd src/vox_populi_frontend
    # npm install y build ignorando scripts de dfx para evitar colisiones de entorno
    npm install && npm run build --no-scripts
    cd ../..
fi

# Localización dinámica de la carpeta de distribución (Assets)
FRONTEND_DIST=$(find src/vox_populi_frontend/dist src/vox_populi_frontend/build dist/vox_populi_frontend -name "index.html" -exec dirname {} \; 2>/dev/null | head -n 1)

if [ -d "$FRONTEND_DIST" ]; then
    echo -e "Carpeta de activos localizada: $FRONTEND_DIST"
    # Generación del Manifiesto: Lista ordenada de archivos + SHA256
    find "$FRONTEND_DIST" -type f ! -name "*.map" -exec sha256sum {} + | sort > assets.manifest
    # Cálculo de la Firma Digital (Root Hash) del Frontend
    TOTAL_FRONTEND_HASH=$(sha256sum assets.manifest | awk '{print $1}')
    echo "$TOTAL_FRONTEND_HASH" > assets.hash
    echo -e "Firma Digital (Frontend Signature): \033[0;32m$TOTAL_FRONTEND_HASH\033[0m"
else
    echo -e "\033[0;31mError: No se ha podido certificar el Frontend.\033[0m"
    exit 1
fi

# --- PASO 3: PERSISTENCIA EN CONTROL DE VERSIONES (GIT) ---
# Vinculamos los certificados de integridad al código fuente mediante Git Tags.
echo -e "\n\033[0;34m[3/4] Registrando certificados en repositorio Git (Tag: $NEW_TAG)...\033[0m"
git add .
git commit -m "release: $NEW_TAG (Integrity Certificates Included)"
git tag -d "$NEW_TAG" 2>/dev/null # Eliminar tag previo si existe
git tag -a "$NEW_TAG" -m "Versión Certificada $NEW_TAG"
git push origin main --tags --force

# --- PASO 4: DESPLIEGUE A LA RED (INTERNET COMPUTER) ---
# Realizamos la subida de los binarios y activos ya certificados.
echo -e "\n\033[0;34m[4/4] Transfiriendo artefactos a Mainnet (IC)...\033[0m"
dfx identity use prod_deployer
export DFX_WARNING=-mainnet_plaintext_identity

# Actualización del Backend (Preservando el estado de la memoria si fuera necesario)
dfx canister --network ic install vox_populi_backend --mode upgrade --wasm "$WASM_PATH" --wasm-memory-persistence keep
# Despliegue de los activos del Frontend
dfx deploy --network ic vox_populi_frontend --no-wallet

# --- FASE FINAL: AUDITORÍA POST-DESPLIEGUE ---
# Verificación en tiempo real de que el hash en red coincide con el local.
echo -e "\n\033[1;35m===============================================================\033[0m"
echo -e "\033[1;35m             RESUMEN DE AUDITORÍA DE INTEGRIDAD              \033[0m"
echo -e "\033[1;35m===============================================================\033[0m"

# Comparación del Backend
HASH_LOCAL=$(sha256sum "$WASM_PATH" | awk '{print $1}')
HASH_RED=$(dfx canister --network ic --identity anonymous info vox_populi_backend | grep "Module hash" | sed 's/.*0x//')

echo -e "BACKEND HASH (LOCAL): $HASH_LOCAL"
echo -e "BACKEND HASH (RED):   $HASH_RED"

if [ "$HASH_LOCAL" == "$HASH_RED" ]; then
    echo -e "ESTADO BACKEND: \033[1;32m[ INTEGRIDAD CONFIRMADA ]\033[0m"
else
    echo -e "ESTADO BACKEND: \033[1;31m[ ERROR DE CONCORDANCIA ]\033[0m"
fi

# Certificación del Frontend
echo -e "FRONTEND SIGNATURE:   $(cat assets.hash)"
echo -e "ESTADO FRONTEND: \033[1;32m[ CERTIFICADO REGISTRADO EN GIT ]\033[0m"
echo -e "\033[1;35m===============================================================\033[0m\n"