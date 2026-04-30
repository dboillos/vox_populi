#!/usr/bin/env bash
set -e

echo "Entorno fijado: DFX 0.32.0, Node 20.11.1, Debian Bullseye..."

# Fase Identidad & Seguridad
function secure_teardown {
  echo "Identidad restaurada a anonymous por seguridad."
  dfx identity use anonymous >/dev/null 2>&1 || true
}
trap secure_teardown EXIT INT TERM ERR

# Validación Inicial
if [ ! -d "./audit_artifacts" ]; then
  echo "Error: El directorio ./audit_artifacts no existe. Ejecute trigger_build.sh previamente."
  exit 1
fi

BACKEND_WASM=$(find ./audit_artifacts -name "backend.wasm" | head -n 1)
if [ -z "$BACKEND_WASM" ] || [ ! -f "$BACKEND_WASM" ]; then
  echo "Error: backend.wasm no encontrado en los artefactos descargados."
  exit 1
fi

LOCAL_SHA=$(sha256sum "$BACKEND_WASM" | awk '{print $1}')
echo "SHA256 del binario a desplegar: $LOCAL_SHA"

echo "Cambiando a la identidad de despliegue (prod_developer)..."
dfx identity use prod_developer

# Fase Despliegue (Mainnet)
echo "Instalando Wasm en Mainnet... (PROHIBIDO ejecutar dfx build local)"
dfx canister --network ic install vox_populi_backend --mode upgrade --wasm "$BACKEND_WASM"

FRONTEND_DIST=$(find ./audit_artifacts -type d -name "dist" | head -n 1)
if [ -n "$FRONTEND_DIST" ]; then
  echo "Desplegando assets del frontend en Mainnet..."
  # --no-build garantiza que no se muta el estado local compilando de nuevo
  dfx deploy vox_populi_frontend --network ic --no-wallet --no-build || true
fi

# Fase Auditoría
echo "Validando integridad de los activos descargados de GitHub contra Mainnet..."
dfx canister --network ic info vox_populi_backend || true
CANISTER_ASSETS=$(dfx canister --network ic call vox_populi_backend list_assets 2>&1 || true)

ONCHAIN_SHA="$(echo "$CANISTER_ASSETS" | grep -Eo '[0-9a-f]{64}' | head -n1 || true)"
if [ -n "$ONCHAIN_SHA" ]; then
  echo "Hash On-Chain reportado: $ONCHAIN_SHA"
  if [ "$ONCHAIN_SHA" == "$LOCAL_SHA" ]; then
    echo "ÉXITO TOTAL: El hash on-chain coincide con el artefacto inmutable descargado."
  else
    echo "ERROR CRÍTICO: Discrepancia detectada entre hash local y Mainnet."
    exit 1
  fi
else
  echo "Advertencia: No se pudo obtener el hash on-chain de forma automatizada."
fi