#!/bin/bash
# Ubicación: Raíz del proyecto (vox_populi/deploy.sh)
# Uso: ./deploy.sh v1.X.X

VERSION=$1
if [ -z "$VERSION" ]; then
    echo -e "\033[0;31m[!] Error: Debes especificar una versión (ej: ./deploy.sh v1.2.70)\033[0m"
    exit 1
fi

# --- LÓGICA DE RUTAS INTELIGENTE ---
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
if [[ "$SCRIPT_DIR" == */audit ]]; then
    ROOT_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
    AUDIT_PATH="$SCRIPT_DIR"
else
    ROOT_DIR="$SCRIPT_DIR"
    AUDIT_PATH="$SCRIPT_DIR/audit"
fi
cd "$ROOT_DIR"

echo -e "\n\033[1;35m===============================================================\033[0m"
echo -e "\033[1;35m             SISTEMA DE DESPLIEGUE TOTAL VOX POPULI            \033[0m"
echo -e "\033[1;35m===============================================================\033[0m"

# --- FASE 0: COMPROBACIÓN DE HERRAMIENTAS ---
echo -e "\n\033[1;34m[1/7] FASE 0: VERIFICANDO REQUISITOS DEL HOST\033[0m"

if ! docker info > /dev/null 2>&1; then
    echo -e "\033[0;31m[!] ERROR: Docker no está operativo.\033[0m"; exit 1
fi
echo -e "\033[0;32m[OK] Docker detectado.\033[0m"

if ! command -v dfx &> /dev/null; then
    echo -e "\033[0;31m[!] ERROR: dfx no está instalado.\033[0m"; exit 1
fi
echo -e "\033[0;32m[OK] dfx detectado.\033[0m"

FILES=("$AUDIT_PATH/audit.sh" "$AUDIT_PATH/internal_audit.sh" "$AUDIT_PATH/Dockerfile" "$AUDIT_PATH/get_network_manifest.sh")
for file in "${FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo -e "\033[0;31m[!] ERROR: Falta '$file'.\033[0m"; exit 1
    fi
done
chmod +x "$AUDIT_PATH"/*.sh
echo -e "\033[0;32m[OK] Scripts de auditoría listos.\033[0m"

# --- FASE 1: LIMPIEZA DE CACHÉ ---
echo -e "\n\033[1;34m[2/7] FASE 1: LIMPIEZA DE ARTEFACTOS PREVIOS\033[0m"
rm -rf .dfx/ic/canisters/vox_populi_backend
rm -rf .dfx/ic/canisters/vox_populi_frontend
mkdir -p .dfx/ic/canisters/vox_populi_backend
echo "Caché purgada para evitar falsos positivos."

# --- FASE 2: COMPILACIÓN EN DOCKER ---
echo -e "\n\033[1;34m[3/7] FASE 2: COMPILANDO WASM DENTRO DE DOCKER\033[0m"
docker build -t vox_populi_auditor "$AUDIT_PATH" > /dev/null 2>&1

docker run --rm -v "$ROOT_DIR":/project -w /project vox_populi_auditor \
    /bin/bash -c "dfx build --network ic vox_populi_backend"

WASM_LOCAL=".dfx/ic/canisters/vox_populi_backend/vox_populi_backend.wasm"
if [ ! -f "$WASM_LOCAL" ]; then
    echo -e "\033[0;31m[!] ERROR: Docker no generó el WASM.\033[0m"; exit 1
fi
echo -e "\033[0;32m[OK] WASM generado por Docker con éxito.\033[0m"

# --- FASE 3: INSTALACIÓN FORZADA EN LA RED (IC) ---
echo -e "\n\033[1;34m[4/7] FASE 3: INSTALACIÓN FORZADA EN LA RED (IC)\033[0m"
dfx identity use prod_deployer

echo "Subiendo binario de Docker a vox_populi_backend..."
# Usamos flags largos para evitar el error '-w' y añadimos la persistencia de memoria exigida por IC
dfx canister --network ic install vox_populi_backend \
    --mode upgrade \
    --wasm "$WASM_LOCAL" \
    --wasm-memory-persistence keep

if [ $? -ne 0 ]; then
    echo -e "\033[0;31m[!] ERROR en el upgrade del backend.\033[0m"; exit 1
fi

echo "Desplegando Frontend..."
dfx deploy --network ic vox_populi_frontend

# --- FASE 4: NOTARÍA GIT ---
echo -e "\n\033[1;34m[5/7] FASE 4: REGISTRO Y TAG EN GIT\033[0m"
if command -v sha256sum &> /dev/null; then
    HASH_WASM=$(sha256sum "$WASM_LOCAL" | awk '{print $1}')
else
    HASH_WASM=$(shasum -a 256 "$WASM_LOCAL" | awk '{print $1}')
fi

git add .
git commit -m "release: $VERSION (Docker Build: $HASH_WASM)"
git tag -a "$VERSION" -m "Build determinista $VERSION"
git push origin main --tags
echo -e "\033[0;32m[OK] Código notariado en GitHub.\033[0m"

# --- FASE 5: LA PRUEBA DE LA VERDAD (AUDITORÍA) ---
echo -e "\n\033[1;34m[6/7] FASE 5: VALIDACIÓN POST-DEPLOY (AUDIT-CHECK)\033[0m"
"$AUDIT_PATH/audit.sh"
AUDIT_EXIT=$?

# --- FASE 6: RESUMEN FINAL ---
echo -e "\n\033[1;34m[7/7] FASE 6: RESUMEN DEL PROCESO\033[0m"
if [ $AUDIT_EXIT -eq 0 ]; then
    echo -e "\033[1;32m===============================================================\033[0m"
    echo -e "\033[1;32m   ✅ ÉXITO TOTAL: RED Y DOCKER COINCIDEN AL 100%              \033[0m"
    echo -e "\033[1;32m===============================================================\033[0m"
else
    echo -e "\033[1;31m===============================================================\033[0m"
    echo -e "\033[1;31m   ❌ ERROR: EL DESPLIEGUE TERMINÓ PERO FALLÓ LA AUDITORÍA     \033[0m"
    echo -e "\033[1;31m===============================================================\033[0m"
    exit 1
fi