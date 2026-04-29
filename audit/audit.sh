#!/bin/bash
# Ubicación: /audit/audit.sh (Host)

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

echo -e "\n\033[1;35m===============================================================\033[0m"
echo -e "\033[1;35m             AUDITORÍA DE INTEGRIDAD BAJO DEMANDA            \033[0m"
echo -e "\033[1;35m===============================================================\033[0m"

# --- FASE 0: PRE-FLIGHT & AUTO-BUILD ---
echo -e "\n\033[1;34m[1/3] FASE 0: VALIDANDO ENTORNO\033[0m"

if ! docker info > /dev/null 2>&1; then
    echo -e "\033[0;31m[!] Error: Docker no está corriendo.\033[0m"; exit 1
fi

# Comprobar si la imagen existe, si no, construirla automáticamente
if [[ "$(docker images -q vox_populi_auditor 2> /dev/null)" == "" ]]; then
    echo -e "\033[0;33m[!] Imagen vox_populi_auditor no encontrada. Construyendo...\033[0m"
    docker build -t vox_populi_auditor .
else
    echo -e "\033[0;32m[OK] Imagen vox_populi_auditor detectada.\033[0m"
fi

chmod +x internal_audit.sh get_network_manifest.sh

# --- FASE 1 & 2: EJECUCIÓN EN DOCKER ---
docker run --rm \
    -v "$SCRIPT_DIR/..":/project \
    -w /project/audit \
    vox_populi_auditor \
    ./internal_audit.sh

echo -e "\033[1;35m===============================================================\033[0m\n"