#!/bin/bash
# Ubicación: /audit/audit.sh (Host)

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

echo -e "\n\033[1;35m===============================================================\033[0m"
echo -e "\033[1;35m             SISTEMA DE AUDITORÍA UNIVERSAL VOX POPULI         \033[0m"
echo -e "\033[1;35m===============================================================\033[0m"

# --- FASE 0: REQUISITOS ---
echo -e "\n\033[1;34m[1/3] FASE 0: COMPROBANDO REQUISITOS DEL SISTEMA\033[0m"

if ! docker info > /dev/null 2>&1; then
    echo -e "\033[0;31m[!] ERROR: Docker no está operativo.\033[0m"
    exit 1
fi

# Verificación de archivos
FILES=("internal_audit.sh" "get_network_manifest.sh" "Dockerfile")
for file in "${FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo -e "\033[0;31m[!] ERROR CRÍTICO: Falta el archivo '$file'.\033[0m"
        exit 1
    fi
done

# Gestión de Imagen con PROGRESO VISIBLE
echo -e "\033[1;33mPreparando imagen de auditoría (Ubuntu + DFX + Node)...\033[0m"
echo -e "\033[0;37m(Si es la primera vez, esto puede tardar 2-3 minutos)\033[0m"

# Quitamos el silencio para ver el progreso de descarga y configuración
docker build -t vox_populi_auditor .

if [ $? -ne 0 ]; then
    echo -e "\033[0;31m[!] ERROR: Falló la construcción de la imagen.\033[0m"
    exit 1
fi

chmod +x internal_audit.sh get_network_manifest.sh

# --- FASES 1 & 2: EJECUCIÓN ---
echo -e "\n\033[1;34m[2/3] LANZANDO AUDITORÍA INTERNA EN CONTENEDOR\033[0m"
echo -e "\033[1;33mIMPORTANTE:\033[0m Verás el progreso de 'npm install' y 'dfx build' a continuación.\033[0m\n"

docker run --rm \
    -v "$SCRIPT_DIR/..":/project \
    -w /project/audit \
    --entrypoint /bin/bash \
    vox_populi_auditor \
    ./internal_audit.sh

EXIT_CODE=$?

echo -e "\n\033[1;35m===============================================================\033[0m"
if [ $EXIT_CODE -eq 0 ]; then
    echo -e "\033[1;32m          RESULTADO FINAL: AUDITORÍA SUPERADA [ OK ]           \033[0m"
else
    echo -e "\033[1;31m          RESULTADO FINAL: AUDITORÍA FALLIDA [ ERROR ]         \033[0m"
fi
echo -e "\033[1;35m===============================================================\033[0m\n"

exit $EXIT_CODE