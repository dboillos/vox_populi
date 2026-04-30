#!/usr/bin/env bash
set -euo pipefail

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
  echo "[deploy] Identidad restaurada a anonymous por seguridad"
  set +e
  dfx identity use anonymous >/dev/null 2>&1 || true
}
trap restore_identity EXIT INT TERM

echo "[deploy] Cambiando identidad a prod_deployer para proceder al despliegue..."
dfx identity use prod_deployer

if [ ! -f "$BACKEND_WASM" ]; then
  echo "[deploy] Error: archivo wasm no encontrado en: $BACKEND_WASM" >&2
  exit 6
fi

echo "[deploy] Instalando canister usando wasm: $BACKEND_WASM"

echo "[deploy] Instalando canister 'vox_populi_backend' con el .wasm descargado..."
set +e
INSTALL_OUTPUT=$(dfx canister --network ic install vox_populi_backend --mode upgrade --wasm "$BACKEND_WASM" 2>&1)
RC=$?
set -e
if [ $RC -ne 0 ]; then
  echo "Advertencia: comando de install devolvió código $RC."
  echo "$INSTALL_OUTPUT"
  # Detectar error de persistencia (IC0504) interactivo
  if echo "$INSTALL_OUTPUT" | grep -q -E "IC0504|Missing upgrade option"; then
    echo
    echo "El upgrade falló por una restricción de persistencia (IC0504)."
    echo "Si eliges 'reinstall' se perderá todo el estado almacenado."
    
    if [ "${AUTO_CONFIRM_REINSTALL:-0}" = "1" ]; then
      yn="y"
      echo "AUTO_CONFIRM_REINSTALL=1: autoconfirmando reinstall"
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
      echo "Ejecutando reinstall (SE PERDERÁ EL ESTADO)..."
      set +e
      if [ "${AUTO_CONFIRM_REINSTALL:-0}" = "1" ]; then
        dfx canister --network ic install vox_populi_backend --mode reinstall --yes --wasm "$BACKEND_WASM"
      else
        dfx canister --network ic install vox_populi_backend --mode reinstall --wasm "$BACKEND_WASM"
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
    echo "Intentando deploy alternativo..."
    dfx deploy --network ic --no-wallet || true
  fi
fi

echo "[deploy] Fase de auditoría post-despliegue: consultando Mainnet..."
dfx canister --network ic info vox_populi_backend || true

echo "[deploy] Despliegue finalizado."
echo "[deploy] Siguiente paso recomendado: ./audit/verify.sh <TAG>"
