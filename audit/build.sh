#!/usr/bin/env bash
set -e

if [ -z "${1:-}" ]; then
  echo "Error: Debe proporcionar un Tag como argumento."
  echo "Uso: $0 v1.2.3"
  exit 1
fi

TAG="$1"
echo "Entorno fijado: DFX 0.32.0, Node 20.11.1, Debian Bullseye..."

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

echo "Creando Tag $TAG y ejecutando push a GitHub para desencadenar el Pipeline de Confianza..."
git tag -a "$TAG" -m "Release Trusted Build $TAG"
git push origin "$TAG"

COMMIT=$(git rev-parse HEAD)
echo "Esperando a que GitHub Actions registre la ejecución para el commit $COMMIT..."

# Fase Polling
RUN_ID=""
for i in {1..30}; do
  RUN_ID=$(gh run list --json databaseId,headSha,event --jq "[.[] | select(.headSha == \"$COMMIT\") | .databaseId][0]")
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
echo "Descargando artefactos de forma 100% automatizada..."
rm -rf ./audit_artifacts
mkdir -p ./audit_artifacts
gh run download "$RUN_ID" --dir ./audit_artifacts

echo "Validando integridad de los activos descargados de GitHub..."
find ./audit_artifacts -type f -exec sha256sum {} +