#!/usr/bin/env bash
set -euo pipefail

export GH_PAGER=cat

if [ -z "${1:-}" ]; then
  echo "Error: Debe proporcionar un Tag como argumento."
  echo "Uso: $0 v1.2.3"
  exit 1
fi

TAG="$1"
echo "Entorno: DFX 0.32.0, Node 20.11.1, Debian Bullseye"

# Fase Git
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$CURRENT_BRANCH" != "main" ]; then
  echo "Error: La rama actual no es 'main'. Abortando por seguridad."
  exit 1
fi

if [ -n "$(git status --porcelain)" ]; then
  echo "Error: El repositorio no está limpio. Realice commit o stash de los cambios."
  exit 1
fi

echo "Creando tag $TAG y publicándolo en GitHub para iniciar el pipeline de release"
git tag -a "$TAG" -m "Release Trusted Build $TAG"
git push origin "$TAG"

COMMIT=$(git rev-parse HEAD)
echo "Esperando a que GitHub Actions registre la ejecución para el commit $COMMIT..."

# Fase Polling
RUN_ID=""
for i in {1..30}; do
  RUN_ID=$(gh run list --json databaseId,headBranch,headSha,event --jq "[.[] | select(.headBranch == \"$TAG\" and .event == \"push\") | .databaseId][0]")
  if [ -n "$RUN_ID" ] && [ "$RUN_ID" != "null" ]; then
    break
  fi
  sleep 5
done

if [ -z "$RUN_ID" ] || [ "$RUN_ID" == "null" ]; then
  echo "Error: No se detectó la ejecución en GitHub Actions."
  exit 1
fi

gh run watch "$RUN_ID"

# Fase Descarga
echo "Descargando artefactos del release..."
rm -rf ./audit_artifacts
mkdir -p ./audit_artifacts

DOWNLOAD_OK=0
for i in {1..12}; do
  if gh release download "$TAG" --dir ./audit_artifacts --pattern "backend.wasm" --pattern "frontend-dist.tgz"; then
    DOWNLOAD_OK=1
    break
  fi
  echo "Intento $i: los assets del release aún no están disponibles; se reintentará en 5 segundos"
  sleep 5
done

if [ "$DOWNLOAD_OK" -ne 1 ]; then
  echo "Error: no se pudieron descargar los assets del release para $TAG." >&2
  exit 5
fi

mkdir -p ./audit_artifacts/backend-wasm ./audit_artifacts/frontend-dist
mv -f ./audit_artifacts/backend.wasm ./audit_artifacts/backend-wasm/backend.wasm
tar -xzf ./audit_artifacts/frontend-dist.tgz -C ./audit_artifacts/frontend-dist
rm -f ./audit_artifacts/frontend-dist.tgz

BACKEND_WASM=$(find ./audit_artifacts -type f -name "backend.wasm" | head -n 1 || true)
FRONTEND_INDEX=$(find ./audit_artifacts -type f -path "*/frontend-dist/index.html" | head -n 1 || true)

if [ -z "$BACKEND_WASM" ]; then
  echo "Error: no se encontró backend.wasm en los artefactos descargados." >&2
  echo "Contenido descargado:" >&2
  find ./audit_artifacts -maxdepth 3 -type f >&2 || true
  exit 6
fi

if [ -z "$FRONTEND_INDEX" ]; then
  echo "Error: no se encontró frontend-dist/index.html en los artefactos descargados." >&2
  echo "Contenido descargado:" >&2
  find ./audit_artifacts -maxdepth 3 -type f >&2 || true
  exit 7
fi

echo "Artefacto backend encontrado: $BACKEND_WASM"
echo "Artefacto frontend encontrado: $FRONTEND_INDEX"

echo "Validando integridad de los activos descargados de GitHub..."
find ./audit_artifacts -type f -exec sha256sum {} +