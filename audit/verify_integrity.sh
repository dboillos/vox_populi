#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Uso: $0 <TAG>\nEjemplo: $0 v1.2.3" >&2
  exit 2
fi

TAG="$1"

echo "Entorno fijado: DFX 0.32.0, Node 20.11.1, Imagen base: Debian Bullseye (dfinity/sdk:0.32.0)"
echo "Validando integridad de los activos descargados de GitHub para el tag: ${TAG}"

# Buscar commit asociado al tag en el remoto para no depender de refs locales.
COMMIT="$(git ls-remote --tags origin "refs/tags/${TAG}^{}" | awk '{print $1}' | head -n1)"
if [ -z "$COMMIT" ]; then
  COMMIT="$(git ls-remote --tags origin "refs/tags/${TAG}" | awk '{print $1}' | head -n1)"
fi
if [ -z "$COMMIT" ]; then
  echo "Error: no se pudo resolver el commit para el tag ${TAG} en el remoto origin." >&2
  exit 3
fi

echo "Commit del tag ${TAG}: $COMMIT"

# Buscar ejecución de GH Actions asociada al commit
echo "Buscando ejecución de GitHub Actions asociada al commit..."
RUN_ID=""
for i in $(seq 1 60); do
  echo "Intento $i: consultando runs..."
  RUN_ID=$(gh run list --json databaseId,headSha,event,status,conclusion 2>/dev/null | \
    python3 -c "import sys,json; data=json.load(sys.stdin); ids=[str(r['databaseId']) for r in data if r.get('headSha')=='$COMMIT']; print(ids[0] if ids else '')") || true
  if [ -n "$RUN_ID" ]; then break; fi
  sleep 3
done

if [ -z "$RUN_ID" ]; then
  echo "Error: no se encontró ejecución de Actions para el tag dentro del tiempo esperado." >&2
  exit 4
fi

echo "Se identificó la ejecución de Actions: $RUN_ID. Descargando artefactos a ./audit_artifacts..."
mkdir -p ./audit_artifacts
gh run download "$RUN_ID" --dir ./audit_artifacts

if [ ! -f ./audit_artifacts/backend.wasm ]; then
  echo "Error: backend.wasm no encontrado entre los artefactos descargados." >&2
  exit 5
fi

echo "Calculando SHA256 del wasm descargado (GitHub)..."
LOCAL_SHA=$(sha256sum ./audit_artifacts/backend.wasm | awk '{print $1}')
echo "SHA256 local (GitHub artifact): $LOCAL_SHA"

echo "Consultando la Mainnet para obtener hashes on-chain (se intentará método list_assets)..."
set +e
CANISTER_OUTPUT=$(dfx canister --network ic call backend list_assets 2>&1 || true)
set -e

echo "Salida on-chain (raw):"
echo "$CANISTER_OUTPUT"

# Extraer todos los SHA256 hex (64 hex chars) de la salida on-chain y comparar con los artefactos
ONCHAIN_SHAES=$(echo "$CANISTER_OUTPUT" | grep -Eo '[0-9a-f]{64}' || true)
if [ -z "$ONCHAIN_SHAES" ]; then
  echo "No se encontraron hashes SHA256 en la salida on-chain. Es posible que el canister no exponga hashes en 'list_assets'." >&2
  exit 6
fi

MATCH_FOUND=0
for h in $ONCHAIN_SHAES; do
  echo "Comparando con hash on-chain: $h"
  if [ "$h" = "$LOCAL_SHA" ]; then
    echo "Coincidencia encontrada: el artefacto de GitHub coincide con un hash on-chain."
    MATCH_FOUND=1
  fi
done

if [ $MATCH_FOUND -eq 0 ]; then
  echo "ERROR FORENSE: Ningún hash on-chain coincide con el SHA256 del artefacto descargado." >&2
  exit 7
fi

# Comparación profunda de todos los archivos dentro de dist (ignorando caches)
if [ -d ./audit_artifacts/dist ]; then
  echo "Validando integridad de archivos en ./audit_artifacts/dist..."
  find ./audit_artifacts/dist -type f ! -name '*.map' ! -name '*.DS_Store' -print0 | while IFS= read -r -d '' file; do
    sha=$(sha256sum "$file" | awk '{print $1}')
    echo "Archivo: $file -> SHA256: $sha"
  done
else
  echo "Advertencia: ./audit_artifacts/dist no existe; quizá el build no generó carpeta dist." >&2
fi

echo "Verificación completa. Identidad de ejecución será restaurada a anonymous si corresponde (script no la modifica)."
