#!/usr/bin/env bash
# SETUP-WORKFLOW.sh
# Script para crear automáticamente el archivo del workflow en la ubicación correcta

set -euo pipefail

WORKFLOW_PATH=".github/workflows/trusted-release-pipeline.yml"

echo "Creando directorio .github/workflows si no existe..."
mkdir -p ".github/workflows"

echo "Escribiendo contenido del workflow a ${WORKFLOW_PATH}..."

cat > "$WORKFLOW_PATH" << 'WORKFLOW_EOF'
name: Trusted Release Pipeline

on:
  push:
    tags:
      - 'v*'

jobs:
  build-and-publish:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Build usando Dockerfile.build
        run: docker build -f audit/Dockerfile.build -t trusted-build .

      - name: Extraer artefactos
        run: |
          CONTAINER_ID=$(docker create trusted-build)
          docker cp "$CONTAINER_ID":/out/backend.wasm ./backend.wasm || true
          docker cp "$CONTAINER_ID":/out/dist ./dist || true
          docker rm -v "$CONTAINER_ID" || true

      - name: Verificar SHA256 del Wasm
        run: |
          if [ -f backend.wasm ]; then
            echo "SHA256 de backend.wasm:"
            sha256sum backend.wasm
          else
            echo "Error: backend.wasm no encontrado"
            exit 2
          fi

      - name: Publicar artefacto backend.wasm
        uses: actions/upload-artifact@v4
        with:
          name: backend-wasm
          path: backend.wasm

      - name: Publicar artefacto frontend dist
        uses: actions/upload-artifact@v4
        with:
          name: frontend-dist
          path: dist
WORKFLOW_EOF

echo "✓ Workflow creado en ${WORKFLOW_PATH}"
ls -la "$WORKFLOW_PATH"
echo ""
echo "Ahora puede hacer commit y push:"
echo "  git add .github/workflows/trusted-release-pipeline.yml"
echo "  git commit -m 'Add trusted release pipeline workflow'"
echo "  git push origin main"
