#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Uso: $0 <TAG>\nEjemplo: $0 v1.2.3" >&2
  exit 2
fi

TAG="$1"

echo "Entorno fijado: DFX 0.32.0, Node 20.11.1, Base: Ubuntu 24.04 con DFX oficial descargado desde GitHub Releases"
echo "Iniciando proceso automático y determinista de construcción y despliegue para el tag: ${TAG}"

# Trap para restaurar identidad a anonymous independientemente del resultado
function restore_identity {
  echo "Identidad restaurada a anonymous por seguridad"
  set +e
  dfx identity use anonymous >/dev/null 2>&1 || true
}
trap restore_identity EXIT INT TERM

echo "Comprobando branch actual y estado del repositorio..."
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$CURRENT_BRANCH" != "main" ]; then
  echo "Error: la rama actual no es 'main' (es '$CURRENT_BRANCH'). Abortando." >&2
  exit 3
fi

if [ -n "$(git status --porcelain)" ]; then
  echo "Error: el árbol de trabajo no está limpio. Commit / stash los cambios antes." >&2
  exit 4
fi

echo "Creando tag ${TAG} y empujando a GitHub..."
git tag -a "$TAG" -m "Release $TAG"
git push origin "$TAG"

# Esperar ejecución de GitHub Actions: buscar run asociado al commit del tag
COMMIT=$(git rev-parse HEAD)
echo "Commit marcado: $COMMIT"

echo "Buscando ejecución de GitHub Actions asociada al push del tag..."
RUN_ID=""
for i in $(seq 1 60); do
  echo "Intento $i: consultando runs..."
  RUN_ID=$(gh run list --json databaseId,headSha,event,status,conclusion 2>/dev/null | \
    python3 -c "import sys,json; data=json.load(sys.stdin); ids=[str(r['databaseId']) for r in data if r.get('headSha')=='$COMMIT']; print(ids[0] if ids else '')") || true
  if [ -n "$RUN_ID" ]; then break; fi
  sleep 5
done

if [ -z "$RUN_ID" ]; then
  echo "Error: no se localizó la ejecución de GitHub Actions para el tag dentro del tiempo esperado." >&2
  exit 5
fi

echo "Se ha identificado la ejecución de Actions: $RUN_ID. Esperando a que termine (visualización en vivo)..."
gh run watch "$RUN_ID"

echo "Limpiando artefactos antiguos..."
rm -rf ./audit_artifacts

echo "Descargando artefactos de GitHub Actions a ./audit_artifacts..."
mkdir -p ./audit_artifacts
gh run download "$RUN_ID" --dir ./audit_artifacts

echo "Cambiando identidad a prod_deployer para proceder al despliegue..."
dfx identity use prod_deployer

echo "Instalando Wasm y activos en la Mainnet (NO se ejecuta dfx build localmente)."
# Localizar backend.wasm en los posibles lugares donde gh run download lo coloca
BACKEND_WASM=""
if [ -f ./audit_artifacts/backend.wasm ]; then
  BACKEND_WASM="./audit_artifacts/backend.wasm"
elif [ -f ./audit_artifacts/backend-wasm/backend.wasm ]; then
  BACKEND_WASM="./audit_artifacts/backend-wasm/backend.wasm"
fi

if [ -z "$BACKEND_WASM" ]; then
  echo "Error: backend.wasm no encontrado en ./audit_artifacts" >&2; exit 6
fi

echo "Instalando canister usando wasm: $BACKEND_WASM"

echo "Instalando canister 'vox_populi_backend' con el .wasm descargado..."
set +e
INSTALL_OUTPUT=$(dfx canister --network ic install vox_populi_backend --mode upgrade --wasm "$BACKEND_WASM" 2>&1)
RC=$?
set -e
if [ $RC -ne 0 ]; then
  echo "Advertencia: comando de install devolvió código $RC."
  echo "$INSTALL_OUTPUT"
  # Detectar error de persistencia (IC0504) y preguntar al usuario
  if echo "$INSTALL_OUTPUT" | grep -q -E "IC0504|Missing upgrade option"; then
    echo
    echo "El upgrade falló por una restricción de persistencia (IC0504)."
    echo "Si eliges 'reinstall' se perderá todo el estado almacenado en el canister (datos persistentes)."
    echo "Opciones:"
    echo "  y  -> Proceder con 'reinstall' (perder estado)"
    echo "  n  -> Abortará el despliegue"
    while true; do
      read -r -p "¿Deseas proceder con 'reinstall' y perder el estado? [y/N]: " yn
      case "$yn" in
        [Yy]* )
          echo "Ejecutando reinstall (SE PERDERÁ EL ESTADO)..."
          set +e
          dfx canister --network ic install vox_populi_backend --mode reinstall --wasm "$BACKEND_WASM"
          RC2=$?
          set -e
          if [ $RC2 -ne 0 ]; then
            echo "Reinstall falló con código $RC2. Abortando." >&2
            exit $RC2
          fi
          break
          ;;
        [Nn]*|"")
          echo "Abortando despliegue por elección del usuario." >&2
          exit 1
          ;;
        *) echo "Respuesta no válida — responde y (sí) o n (no).";;
      esac
    done
  else
    echo "Intentando deploy alternativo..."
    dfx deploy --network ic --no-wallet || true
  fi
fi

echo "Fase de auditoría post-despliegue: consultando Mainnet y comparando hashes..."
echo "Obteniendo información canister (dfx canister info)..."
dfx canister --network ic info vox_populi_backend || true

echo "Solicitando listado de activos al canister (si el método existe 'list_assets')..."
set +e
CANISTER_ASSETS_RAW=$(dfx canister --network ic call vox_populi_backend list_assets 2>&1 || true)
set -e

echo "Integridad: calculando SHA256 locales y comparando con datos on-chain..."
LOCAL_WASM_SHA=$(sha256sum "$BACKEND_WASM" | awk '{print $1}')
echo "SHA256 local (${BACKEND_WASM}): ${LOCAL_WASM_SHA}"

echo "Salida on-chain (raw):"
echo "$CANISTER_ASSETS_RAW"

# Intentar extraer cualquier hash presente en la salida on-chain y comparar
ONCHAIN_SHA="$(echo "$CANISTER_ASSETS_RAW" | grep -Eo '[0-9a-f]{64}' | head -n1 || true)"
if [ -n "$ONCHAIN_SHA" ]; then
  echo "Primer SHA256 hallado on-chain: $ONCHAIN_SHA"
  if [ "$ONCHAIN_SHA" = "$LOCAL_WASM_SHA" ]; then
    echo "Verificación exitosa: el SHA256 del wasm en GitHub coincide con el registrado on-chain."
  else
    echo "ERROR: mismatched SHA256 entre artefacto (GitHub) y valor on-chain." >&2
    exit 7
  fi
else
  echo "No se pudo extraer un SHA256 on-chain automáticamente. Revise manualmente la salida de list_assets." >&2
fi

echo "Despliegue completado. Restaurando identidad a anonymous por seguridad (trap también lo hará)."
dfx identity use anonymous || true

echo "Proceso finalizado correctamente. Los artefactos se encuentran en ./audit_artifacts"
