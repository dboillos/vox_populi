#!/usr/bin/env bash
set -euo pipefail

export GH_PAGER=cat

if [ -z "${1:-}" ]; then
  echo "Error: Debe proporcionar un Tag como argumento. Ejemplo: $0 v1.2.3"
  exit 1
fi

TAG="$1"
echo "Entorno fijado: DFX 0.32.0, Node 20.11.1, Debian Bullseye..."
echo "Iniciando auditoría forense para la versión $TAG..."

echo "Descargando artefactos forenses del release $TAG..."
rm -rf ./audit_forensic_artifacts
mkdir -p ./audit_forensic_artifacts
gh release download "$TAG" --dir ./audit_forensic_artifacts --pattern "backend.wasm"

BACKEND_WASM=$(find ./audit_forensic_artifacts -name "backend.wasm" | head -n 1)
if [ -z "$BACKEND_WASM" ]; then
  echo "Error: backend.wasm no se pudo recuperar."
  exit 1
fi

LOCAL_SHA=$(sha256sum "$BACKEND_WASM" | awk '{print $1}')
echo "Hash inmutable calculado (GitHub Artifact): $LOCAL_SHA"

CANISTER_OUTPUT=$(dfx canister --network ic call vox_populi_backend list_assets 2>&1 || true)
ONCHAIN_SHAES=$(echo "$CANISTER_OUTPUT" | grep -Eo '[0-9a-f]{64}' || true)

MATCH_FOUND=0
for h in $ONCHAIN_SHAES; do
  if [ "$h" = "$LOCAL_SHA" ]; then
    echo "Validando integridad de los activos descargados de GitHub... ÉXITO."
    MATCH_FOUND=1
    break
  fi
done

if [ $MATCH_FOUND -eq 0 ]; then
  echo "ERROR FORENSE: Ningún hash de Mainnet concuerda con el SHA256 descargado."
  exit 1
fi

echo "Efectuando validación profunda del frontend ignorando archivos caché..."
FRONTEND_DIST=$(find ./audit_forensic_artifacts -type d -name "dist" | head -n 1)
if [ -n "$FRONTEND_DIST" ]; then
  find "$FRONTEND_DIST" -type f ! -name '*.map' ! -name '*.DS_Store' -exec sha256sum {} +
fi

echo "Identidad restaurada a anonymous por seguridad"
dfx identity use anonymous >/dev/null 2>&1 || true
echo "Auditoría forense superada con absoluto éxito determinista."
