#!/usr/bin/env bash
set -euo pipefail

if command -v icp >/dev/null 2>&1; then
  CLI_TOOL="icp"
elif command -v dfx >/dev/null 2>&1; then
  CLI_TOOL="dfx"
else
  echo "Error: no se encontró ni 'icp' ni 'dfx' en PATH." >&2
  exit 2
fi

if [ "$CLI_TOOL" = "icp" ]; then
  export DO_NOT_TRACK=1
fi

BACKEND_CANISTER_ID=$(jq -r '.vox_populi_backend.ic // empty' ./canister_ids.json 2>/dev/null || true)
if [ -z "$BACKEND_CANISTER_ID" ]; then
  echo "Error: no se pudo resolver vox_populi_backend.ic desde canister_ids.json" >&2
  exit 2
fi

set_identity() {
  local identity_name="$1"
  if [ "$CLI_TOOL" = "icp" ]; then
    icp identity default "$identity_name" >/dev/null
  else
    dfx identity use "$identity_name" >/dev/null
  fi
}

install_backend() {
  local mode="$1"
  local extra_yes="${2:-0}"
  if [ "$CLI_TOOL" = "icp" ]; then
    if [ "$extra_yes" = "1" ]; then
      icp canister install "$BACKEND_CANISTER_ID" --network ic --mode "$mode" --wasm "$BACKEND_WASM" --yes
    else
      icp canister install "$BACKEND_CANISTER_ID" --network ic --mode "$mode" --wasm "$BACKEND_WASM"
    fi
  else
    if [ "$extra_yes" = "1" ]; then
      dfx canister --network ic install vox_populi_backend --mode "$mode" --wasm "$BACKEND_WASM" --yes
    else
      dfx canister --network ic install vox_populi_backend --mode "$mode" --wasm "$BACKEND_WASM"
    fi
  fi
}

show_backend_status() {
  if [ "$CLI_TOOL" = "icp" ]; then
    icp canister status "$BACKEND_CANISTER_ID" --network ic || true
  else
    dfx canister --network ic info vox_populi_backend || true
  fi
}

if [ "$#" -ge 1 ]; then
  BACKEND_WASM="$1"
else
  if [ -f "./audit_artifacts/backend.wasm" ]; then
    BACKEND_WASM="./audit_artifacts/backend.wasm"
  elif [ -f "./audit_artifacts/backend-wasm/backend.wasm" ]; then
    BACKEND_WASM="./audit_artifacts/backend-wasm/backend.wasm"
  else
    echo "Uso: $0 <RUTA_BACKEND_WASM>" >&2
    echo "Sugerencia: ejecuta antes ./audit/build.sh <TAG> para descargar artefactos." >&2
    exit 2
  fi
fi

# Trap para restaurar identidad a anonymous independientemente del resultado
function restore_identity {
  echo "[deploy] Identidad restaurada a anonymous"
  set +e
  set_identity anonymous >/dev/null 2>&1 || true
}
trap restore_identity EXIT INT TERM

echo "[deploy] Cambiando identidad a prod_deployer para el despliegue"
set_identity prod_deployer

if [ ! -f "$BACKEND_WASM" ]; then
  echo "[deploy] Error: archivo wasm no encontrado en: $BACKEND_WASM" >&2
  exit 6
fi

echo "[deploy] Instalando canister con el archivo wasm: $BACKEND_WASM"

echo "[deploy] Instalando canister 'vox_populi_backend' con el wasm descargado"
set +e
INSTALL_OUTPUT=$(install_backend upgrade 0 2>&1)
RC=$?
set -e
if [ $RC -ne 0 ]; then
  echo "Advertencia: el comando de instalación devolvió el código $RC."
  echo "$INSTALL_OUTPUT"
  # Detectar error de persistencia (IC0504) interactivo
  if echo "$INSTALL_OUTPUT" | grep -q -E "IC0504|Missing upgrade option"; then
    echo
    echo "La actualización falló por una restricción de persistencia (IC0504)."
    echo "Si elige 'reinstall' se perderá el estado almacenado."
    
    if [ "${AUTO_CONFIRM_REINSTALL:-0}" = "1" ]; then
      yn="y"
      echo "AUTO_CONFIRM_REINSTALL=1: confirmación automática de reinstall"
    else
      while true; do
        read -r -p "¿Deseas proceder con 'reinstall' y perder el estado? [y/N]: " yn
        case "$yn" in
          [Yy]*|[Nn]*|"") break ;;
          *) echo "Respuesta no válida — responde y (sí) o n (no)." ;;
        esac
      done
    fi

    if echo "${yn:-n}" | grep -qi "^[Yy]"; then
      echo "Ejecutando reinstall (se perderá el estado)..."
      set +e
      if [ "${AUTO_CONFIRM_REINSTALL:-0}" = "1" ]; then
        install_backend reinstall 1
      else
        install_backend reinstall 0
      fi
      RC2=$?
      set -e
      if [ $RC2 -ne 0 ]; then
        echo "Reinstall falló con código $RC2. Abortando." >&2
        exit $RC2
      fi
    else
      echo "Abortando despliegue por elección del usuario." >&2
      exit 1
    fi
  else
    echo "Intentando despliegue alternativo..."
    if command -v dfx >/dev/null 2>&1; then
      dfx deploy --network ic --no-wallet || true
    else
      echo "No se ejecuta fallback de despliegue alternativo: dfx no está disponible." >&2
    fi
  fi
fi

echo "[deploy] Consulta posterior al despliegue en Mainnet"
show_backend_status

echo "[deploy] Despliegue finalizado."
echo "[deploy] Siguiente paso recomendado: ./audit/verify.sh <TAG>"
