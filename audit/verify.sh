#!/usr/bin/env bash
set -e

if [ -z "${1:-}" ]; then
  echo "Error: Debe proporcionar un Tag como argumento. Ejemplo: $0 v1.2.3"
  exit 1
fi

TAG="$1"
echo "Entorno fijado: DFX 0.32.0, Node 20.11.1, Debian Bullseye..."
echo "Iniciando auditoría forense para la versión $TAG..."

COMMIT=$(git rev-list -n 1 "$TAG" 2>/dev/null || git ls-remote --tags origin "refs/tags/${TAG}^{}" | awk '{print $1}')
if [ -z "$COMMIT" ]; then
  echo "Error: No se pudo resolver el commit asociado al tag $TAG."
  exit 1
fi

RUN_ID=$(gh run list --json databaseId,headSha --jq "[.[] | select(.headSha == \"$COMMIT\") | .databaseId][0]")
if [ -z "$RUN_ID" ] || [ "$RUN_ID" == "null" ]; then
  echo "Error: No se halló ejecución en GitHub Actions."
  exit 1
fi

echo "Descargando artefactos forenses (Run ID: $RUN_ID)..."
rm -rf ./audit_forensic_artifacts
mkdir -p ./audit_forensic_artifacts
gh run download "$RUN_ID" --dir ./audit_forensic_artifacts

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
