#!/bin/bash
# Ubicación: /audit/audit.sh (Host)
# Objetivo: Infraestructura automática "Zero Trust". 
# Verifica el entorno, gestiona la imagen y lanza la auditoría hermética.

# 1. Sincronización de rutas para que funcione desde cualquier directorio
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

echo -e "\n\033[1;35m===============================================================\033[0m"
echo -e "\033[1;35m             AUDITORÍA DE INTEGRIDAD BAJO DEMANDA            \033[0m"
echo -e "\033[1;35m===============================================================\033[0m"

# --- FASE 0: PRE-FLIGHT CHECKS (HOST) ---
echo -e "\n\033[1;34m[1/3] FASE 0: VALIDANDO REQUISITOS\033[0m"

# A. Verificar si Docker está instalado y el demonio corre
if ! docker info > /dev/null 2>&1; then
    echo -e "\033[0;31m[!] Error: Docker no está operativo. Levanta el servicio antes de continuar.\033[0m"
    exit 1
fi

# B. Verificar que existan los archivos necesarios para la auditoría
REQUIRED_FILES=("internal_audit.sh" "get_network_manifest.sh" "Dockerfile")
for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo -e "\033[0;31m[!] Error crítico: No se encuentra el archivo $file en la carpeta audit.\033[0m"
        exit 1
    fi
done

# C. Gestión automática de la imagen (Auto-Build)
# Si no existe, se construye. Si existe, el usuario puede estar tranquilo de que el script
# interno hará su trabajo. (En deploy.sh forzamos el build, aquí priorizamos velocidad).
if [[ "$(docker images -q vox_populi_auditor 2> /dev/null)" == "" ]]; then
    echo -e "\033[0;33m[!] Imagen vox_populi_auditor no detectada. Construyendo búnker...\033[0m"
    docker build -t vox_populi_auditor .
else
    echo -e "\033[0;32m[OK] Entorno Docker (vox_populi_auditor) listo.\033[0m"
fi

# D. Asegurar permisos de ejecución en el Host antes de montar en Docker
chmod +x internal_audit.sh get_network_manifest.sh

# --- FASES 1 & 2: SALTO AL CONTENEDOR (LOGICA HERMÉTICA) ---
echo -e "\033[1;33mLanzando auditoría en contenedor Ubuntu 24.04...\033[0m"

# Usamos --entrypoint /bin/bash para anular cualquier ENTRYPOINT previo del Dockerfile
# Montamos la raíz del proyecto para que el auditor pueda 'ver' todo el código.
docker run --rm \
    -v "$SCRIPT_DIR/..":/project \
    -w /project/audit \
    --entrypoint /bin/bash \
    vox_populi_auditor \
    ./internal_audit.sh

echo -e "\n\033[1;35m===============================================================\033[0m\n"