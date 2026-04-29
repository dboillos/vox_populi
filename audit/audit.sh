#!/bin/bash
# Ubicación: /audit/audit.sh (Ejecutado en el HOST)

echo -e "\n\033[1;35m===============================================================\033[0m"
echo -e "\033[1;35m             AUDITORÍA DE INTEGRIDAD BAJO DEMANDA            \033[0m"
echo -e "\033[1;35m===============================================================\033[0m"

# --- FASE 0: PRE-FLIGHT CHECKS ---
echo -e "\n\033[1;34m[1/3] FASE 0: VALIDANDO ENTORNO Y PERMISOS\033[0m"

if ! docker info > /dev/null 2>&1; then
    echo -e "\033[0;31m[!] Error: Docker no está corriendo.\033[0m"; exit 1
fi

if [ ! -f "./internal_audit.sh" ]; then
    echo -e "\033[0;31m[!] Error: No se encuentra audit/internal_audit.sh\033[0m"; exit 1
fi

# Aseguramos permisos en el host antes de entrar
chmod +x internal_audit.sh get_network_manifest.sh
echo -e "\033[0;32mEntorno validado. Lanzando contenedor...\033[0m"

# --- FASE 1 & 2: EJECUCIÓN EN DOCKER ---
# Ejecutamos el script interno que contiene las fases 1 y 2 de la auditoría
docker run --rm \
    -v "$(pwd)/..":/project \
    -w /project/audit \
    vox_populi_auditor \
    ./internal_audit.sh

echo -e "\033[1;35m===============================================================\033[0m\n"