#!/usr/bin/env bash
set -euo pipefail

fail_with_context() {
  local exit_code="$1"
  local line_no="$2"
  local failed_cmd="$3"
  echo "[deploy] Error en línea ${line_no}: comando fallido: ${failed_cmd}" >&2
  exit "$exit_code"
}

require_command() {
  local cmd="$1"
  local why="$2"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "[deploy] Error: comando requerido no encontrado: '$cmd' ($why)." >&2
    exit 2
  fi
}

trap 'fail_with_context $? ${LINENO} "${BASH_COMMAND}"' ERR

print_separator() {
  printf '============================================================\n'
}

print_section() {
  print_separator
  printf '%s\n' "$1"
  print_separator
}

print_info() {
  printf '[deploy] %s\n' "$1"
}

print_ok() {
  printf '[ok] %s\n' "$1"
}

print_warn() {
  printf '[warn] %s\n' "$1"
}

print_kv() {
  printf '%-20s %s\n' "$1" "$2"
}

has_icp=0
has_dfx=0
if command -v icp >/dev/null 2>&1; then
  has_icp=1
fi
if command -v dfx >/dev/null 2>&1; then
  has_dfx=1
fi

if [ "$has_icp" -ne 1 ] && [ "$has_dfx" -ne 1 ]; then
  echo "Error: no se encontró ni 'icp' ni 'dfx' en PATH." >&2
  exit 2
fi

identity_exists_icp() {
  local identity_name="$1"
  icp identity list 2>/dev/null | sed -E 's/^\*//' | awk '{print $1}' | grep -Fxq "$identity_name"
}

identity_exists_dfx() {
  local identity_name="$1"
  dfx identity list 2>/dev/null | sed 's/\*$//' | awk '{print $1}' | grep -Fxq "$identity_name"
}

DEPLOY_IDENTITY="${DEPLOY_IDENTITY:-prod_deployer}"

if [ "$has_icp" -eq 1 ] && identity_exists_icp "$DEPLOY_IDENTITY"; then
  CLI_TOOL="icp"
elif [ "$has_dfx" -eq 1 ] && identity_exists_dfx "$DEPLOY_IDENTITY"; then
  CLI_TOOL="dfx"
elif [ "$has_icp" -eq 1 ]; then
  CLI_TOOL="icp"
else
  CLI_TOOL="dfx"
fi

require_command jq "lectura y edición segura de canister_ids.json y dfx.json"
require_command tar "extracción de frontend-dist.tgz"

if [ "$CLI_TOOL" = "icp" ]; then
  export DO_NOT_TRACK=1
fi

BACKEND_CANISTER_ID=$(jq -r '.vox_populi_backend.ic // empty' ./canister_ids.json 2>/dev/null || true)
if [ -z "$BACKEND_CANISTER_ID" ]; then
  echo "Error: no se pudo resolver vox_populi_backend.ic desde canister_ids.json" >&2
  exit 2
fi

FRONTEND_CANISTER_ID=$(jq -r '.vox_populi_frontend.ic // empty' ./canister_ids.json 2>/dev/null || true)
if [ -z "$FRONTEND_CANISTER_ID" ]; then
  echo "Error: no se pudo resolver vox_populi_frontend.ic desde canister_ids.json" >&2
  exit 2
fi

DEPLOY_ARTIFACTS_TMP=""
FRONTEND_SYNC_LOG=""
FRONTEND_SYNC_COUNTS=""

set_identity() {
  local identity_name="$1"
  if [ "$CLI_TOOL" = "icp" ]; then
    icp identity default "$identity_name" >/dev/null 2>&1
  else
    dfx identity use "$identity_name" >/dev/null 2>&1
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

get_canister_status_json() {
  local canister_id="$1"
  if [ "$CLI_TOOL" = "icp" ]; then
    icp canister status "$canister_id" --network ic --json 2>/dev/null || true
  else
    local text
    text=$(dfx canister --network ic status "$canister_id" 2>/dev/null || true)
    python3 - <<'PY' "$text"
import json
import re
import sys

text = sys.argv[1]

def pick(pattern):
    m = re.search(pattern, text, re.MULTILINE)
    return m.group(1) if m else ""

data = {
    "status": pick(r"Status:\s*([^\n]+)"),
    "module_hash": pick(r"Module hash:\s*(0x[0-9a-f]+)"),
}
print(json.dumps(data))
PY
  fi
}

print_canister_summary() {
  local label="$1"
  local canister_id="$2"
  local status_json
  local canister_status
  local module_hash

  status_json=$(get_canister_status_json "$canister_id")
  canister_status=$(printf '%s' "$status_json" | jq -r '.status // "desconocido"')
  module_hash=$(printf '%s' "$status_json" | jq -r '.module_hash // "-"')

  print_kv "$label id:" "$canister_id"
  print_kv "$label estado:" "$canister_status"
  print_kv "$label hash:" "$module_hash"
}

restore_temp_artifacts() {
  if [ -n "$DEPLOY_ARTIFACTS_TMP" ] && [ -d "$DEPLOY_ARTIFACTS_TMP" ]; then
    rm -rf "$DEPLOY_ARTIFACTS_TMP"
    DEPLOY_ARTIFACTS_TMP=""
  fi
}

asset_canister_call() {
  local method="$1"
  local argument_file="$2"
  if command -v icp >/dev/null 2>&1; then
    icp canister call "$FRONTEND_CANISTER_ID" "$method" \
      --args-file "$argument_file" \
      --network ic \
      --identity "$DEPLOY_IDENTITY" >/dev/null
  else
    require_command dfx "llamadas de actualización al asset canister"
    dfx canister --network ic call \
      --identity "$DEPLOY_IDENTITY" \
      --candid src/declarations/vox_populi_frontend/vox_populi_frontend.did \
      "$FRONTEND_CANISTER_ID" "$method" \
      --argument-file "$argument_file" >/dev/null
  fi
}

list_frontend_keys_raw() {
  if command -v icp >/dev/null 2>&1; then
    icp canister call "$FRONTEND_CANISTER_ID" list '(record { start = null; length = null })' \
      --query --network ic
  else
    require_command dfx "lectura del asset canister"
    dfx canister --network ic call --query \
      --candid src/declarations/vox_populi_frontend/vox_populi_frontend.did \
      "$FRONTEND_CANISTER_ID" list '(record { start = null; length = null })'
  fi
}

sync_frontend_assets_direct() {
  local dist_dir="$1"
  local tmp_dir
  tmp_dir=$(mktemp -d)
  FRONTEND_SYNC_LOG="$tmp_dir/frontend-sync.log"
  FRONTEND_SYNC_COUNTS="$tmp_dir/frontend-sync-counts.json"

  python3 - <<'PY' "$dist_dir" "$tmp_dir"
import hashlib
import mimetypes
import subprocess
import sys
from pathlib import Path
import re

dist_dir = Path(sys.argv[1])
tmp_dir = Path(sys.argv[2])

raw = subprocess.check_output([
    'icp', 'canister', 'call', '4zjkp-mqaaa-aaaaj-qqwrq-cai', 'list',
    '(record { start = null; length = null })',
    '--query', '--network', 'ic'
], text=True)

onchain_keys = set(re.findall(r'key\s*=\s*"([^"]+)";', raw))
desired_keys = []

def escape_blob(data: bytes) -> str:
    return ''.join(f'\\{byte:02x}' for byte in data)

import gzip as gzip_mod

for file_path in sorted(p for p in dist_dir.rglob('*') if p.is_file()):
    if file_path.name in {'.DS_Store', '.ic-assets.json5'} or file_path.name.endswith('.map'):
        continue
    rel = file_path.relative_to(dist_dir).as_posix()
    key = '/' + rel
    desired_keys.append(key)
    content = file_path.read_bytes()
    sha = hashlib.sha256(content).digest()
    content_type = mimetypes.guess_type(file_path.name)[0] or 'application/octet-stream'

    # Encoding identity (siempre)
    arg_identity = (
        f'(record {{ key = "{key}"; '
        f'content_type = "{content_type}"; '
        f'content_encoding = "identity"; '
        f'content = blob "{escape_blob(content)}"; '
        f'sha256 = opt blob "{escape_blob(sha)}"; }})\n'
    )
    slot = len(desired_keys)
    (tmp_dir / f'store_{slot:04d}i.didarg').write_text(arg_identity, encoding='utf-8')
    (tmp_dir / f'store_{slot:04d}i.key').write_text(key + '\n', encoding='utf-8')

    # Encoding gzip (sobrescribe cualquier versión gzip previa en el canister)
    gz_content = gzip_mod.compress(content, compresslevel=9, mtime=0)
    gz_sha = hashlib.sha256(gz_content).digest()
    arg_gzip = (
        f'(record {{ key = "{key}"; '
        f'content_type = "{content_type}"; '
        f'content_encoding = "gzip"; '
        f'content = blob "{escape_blob(gz_content)}"; '
        f'sha256 = opt blob "{escape_blob(gz_sha)}"; }})\n'
    )
    (tmp_dir / f'store_{slot:04d}g.didarg').write_text(arg_gzip, encoding='utf-8')
    (tmp_dir / f'store_{slot:04d}g.key').write_text(key + ' (gzip)\n', encoding='utf-8')

stale_keys = sorted(onchain_keys - set(desired_keys))
for index, key in enumerate(stale_keys, start=1):
    arg = f'(record {{ key = "{key}" }})\n'
    (tmp_dir / f'delete_{index:04d}.didarg').write_text(arg, encoding='utf-8')
    (tmp_dir / f'delete_{index:04d}.key').write_text(key + '\n', encoding='utf-8')

(tmp_dir / 'counts.json').write_text(
    '{"store": %d, "delete": %d}\n' % (len(desired_keys), len(stale_keys)),
    encoding='utf-8',
)
PY

  while IFS= read -r arg_file; do
    asset_canister_call store "$arg_file"
    local key_file="${arg_file%.didarg}.key"
    key_label="$(cat "$key_file" | tr -d '\n')"
    # Solo registrar la línea UPSERT para el encoding identity (no duplicar el log)
    if [[ "$arg_file" == *i.didarg ]]; then
      printf 'UPSERT\t%s\n' "${key_label% (gzip)}" >> "$FRONTEND_SYNC_LOG"
    fi
  done < <(find "$tmp_dir" -name 'store_*.didarg' | LC_ALL=C sort)

  while IFS= read -r arg_file; do
    asset_canister_call delete_asset "$arg_file"
    local key_file="${arg_file%.didarg}.key"
    printf 'DELETE\t%s\n' "$(cat "$key_file")" >> "$FRONTEND_SYNC_LOG"
  done < <(find "$tmp_dir" -name 'delete_*.didarg' | LC_ALL=C sort)

  mv "$tmp_dir/counts.json" "$FRONTEND_SYNC_COUNTS"
}

download_release_artifacts() {
  local tag="$1"
  require_command gh "descarga de artefactos del release por tag"
  DEPLOY_ARTIFACTS_TMP=$(mktemp -d)

  gh release download "$tag" \
    --dir "$DEPLOY_ARTIFACTS_TMP" \
    --pattern "backend.wasm" \
    --pattern "frontend-dist.tgz"

  if [ ! -f "$DEPLOY_ARTIFACTS_TMP/backend.wasm" ]; then
    echo "[deploy] Error: backend.wasm no se encontró en el release $tag." >&2
    return 1
  fi
  if [ ! -f "$DEPLOY_ARTIFACTS_TMP/frontend-dist.tgz" ]; then
    echo "[deploy] Error: frontend-dist.tgz no se encontró en el release $tag." >&2
    return 1
  fi

  mkdir -p "$DEPLOY_ARTIFACTS_TMP/frontend-dist"
  tar -xzf "$DEPLOY_ARTIFACTS_TMP/frontend-dist.tgz" -C "$DEPLOY_ARTIFACTS_TMP/frontend-dist"
  rm -f "$DEPLOY_ARTIFACTS_TMP/frontend-dist.tgz"

  BACKEND_WASM="$DEPLOY_ARTIFACTS_TMP/backend.wasm"
  FRONTEND_DIST="$DEPLOY_ARTIFACTS_TMP/frontend-dist"
}

BACKEND_WASM=""
FRONTEND_DIST=""

if [ "$#" -ge 2 ] && [ "$1" = "--tag" ]; then
  RELEASE_TAG="$2"
  echo "[deploy] Descargando artefactos del release: $RELEASE_TAG"
  download_release_artifacts "$RELEASE_TAG"
elif [ "$#" -ge 1 ] && [[ "$1" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  RELEASE_TAG="$1"
  echo "[deploy] Descargando artefactos del release: $RELEASE_TAG"
  download_release_artifacts "$RELEASE_TAG"
else
  if [ "$#" -ge 1 ]; then
    BACKEND_WASM="$1"
  else
    if [ -f "./audit_artifacts/backend.wasm" ]; then
      BACKEND_WASM="./audit_artifacts/backend.wasm"
    elif [ -f "./audit_artifacts/backend-wasm/backend.wasm" ]; then
      BACKEND_WASM="./audit_artifacts/backend-wasm/backend.wasm"
    else
      echo "Uso: $0 [--tag TAG] [RUTA_BACKEND_WASM [RUTA_FRONTEND_DIST]]" >&2
      echo "Sugerencia: ejecuta antes ./audit/build.sh <TAG> para descargar artefactos." >&2
      exit 2
    fi
  fi

  if [ "$#" -ge 2 ]; then
    FRONTEND_DIST="$2"
  else
    if [ -d "./audit_artifacts/frontend-dist" ]; then
      FRONTEND_DIST="./audit_artifacts/frontend-dist"
    elif [ -d "./src/vox_populi_frontend/dist" ]; then
      FRONTEND_DIST="./src/vox_populi_frontend/dist"
    else
      echo "Uso: $0 [--tag TAG] [RUTA_BACKEND_WASM [RUTA_FRONTEND_DIST]]" >&2
      echo "Sugerencia: ejecuta antes ./audit/build.sh <TAG> para descargar artefactos." >&2
      exit 2
    fi
  fi
fi

# Trap para restaurar identidad a anonymous independientemente del resultado
function restore_identity {
  restore_temp_artifacts
  if [ -n "$FRONTEND_SYNC_LOG" ] && [ -f "$FRONTEND_SYNC_LOG" ]; then
    rm -f "$FRONTEND_SYNC_LOG"
  fi
  if [ -n "$FRONTEND_SYNC_COUNTS" ] && [ -f "$FRONTEND_SYNC_COUNTS" ]; then
    rm -f "$FRONTEND_SYNC_COUNTS"
  fi
  set +e
  set_identity anonymous >/dev/null 2>&1 || true
  print_info "Identidad restaurada a anonymous"
}
trap restore_identity EXIT INT TERM

print_section "Despliegue a Mainnet"
print_kv "CLI:" "$CLI_TOOL"
print_kv "Identidad:" "$DEPLOY_IDENTITY"
if [ -n "${RELEASE_TAG:-}" ]; then
  print_kv "Release:" "$RELEASE_TAG"
fi

print_info "Cambiando identidad a $DEPLOY_IDENTITY para el despliegue"
set +e
set_identity "$DEPLOY_IDENTITY"
IDENTITY_RC=$?
set -e
if [ $IDENTITY_RC -ne 0 ]; then
  echo "[deploy] Error: no se pudo seleccionar la identidad '$DEPLOY_IDENTITY' con '$CLI_TOOL'." >&2
  if [ "$CLI_TOOL" = "icp" ] && [ "$has_dfx" -eq 1 ] && identity_exists_dfx "$DEPLOY_IDENTITY"; then
    echo "[deploy] Reintentando con dfx porque la identidad existe allí." >&2
    CLI_TOOL="dfx"
    set_identity "$DEPLOY_IDENTITY"
  else
    echo "[deploy] Sugerencia: exporta DEPLOY_IDENTITY=<identidad_valida> o crea/importa '$DEPLOY_IDENTITY'." >&2
    exit 1
  fi
fi

if [ ! -f "$BACKEND_WASM" ]; then
  echo "[deploy] Error: archivo wasm no encontrado en: $BACKEND_WASM" >&2
  exit 6
fi

if [ ! -d "$FRONTEND_DIST" ]; then
  echo "[deploy] Error: carpeta frontend-dist no encontrada en: $FRONTEND_DIST" >&2
  exit 7
fi

print_section "1) Backend"
print_kv "Wasm:" "$BACKEND_WASM"
print_info "Instalando vox_populi_backend"
set +e
INSTALL_OUTPUT=$(install_backend upgrade 0 2>&1)
RC=$?
set -e
if [ $RC -ne 0 ]; then
  print_warn "La instalación del backend devolvió el código $RC."
  printf '%s\n' "$INSTALL_OUTPUT"
  # Detectar error de persistencia (IC0504) interactivo
  if echo "$INSTALL_OUTPUT" | grep -q -E "IC0504|Missing upgrade option"; then
    echo
    echo "La actualización falló por una restricción de persistencia (IC0504)."
    echo "Si elige 'reinstall' se perderá el estado almacenado."
    
    if [ ! -t 0 ]; then
      echo "No hay terminal interactiva para confirmar 'reinstall'. Abortando para proteger el estado." >&2
      exit 1
    fi

    while true; do
      read -r -p "¿Deseas proceder con 'reinstall' y perder el estado? [y/N]: " yn
      case "$yn" in
        [Yy]*|[Nn]*|"") break ;;
        *) echo "Respuesta no válida. Responde y (sí) o n (no)." ;;
      esac
    done

    if echo "${yn:-n}" | grep -qi "^[Yy]"; then
      echo "Ejecutando reinstall (se perderá el estado)..."
      set +e
      install_backend reinstall 0
      RC2=$?
      set -e
      if [ $RC2 -ne 0 ]; then
        echo "Reinstall falló con código $RC2. Abortando." >&2
        exit $RC2
      fi
      print_ok "Backend reinstalado correctamente"
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
if [ $RC -eq 0 ]; then
  print_ok "Backend desplegado correctamente"
fi

print_section "2) Frontend"
print_kv "Dist:" "$FRONTEND_DIST"
print_info "Sincronizando assets exactos al canister frontend"
sync_frontend_assets_direct "$FRONTEND_DIST"
print_ok "Frontend sincronizado correctamente"

print_section "3) Resumen"
print_canister_summary "Backend" "$BACKEND_CANISTER_ID"
print_canister_summary "Frontend" "$FRONTEND_CANISTER_ID"

if [ -n "$FRONTEND_SYNC_COUNTS" ] && [ -f "$FRONTEND_SYNC_COUNTS" ]; then
  print_kv "Assets upsert:" "$(jq -r '.store' "$FRONTEND_SYNC_COUNTS")"
  print_kv "Assets delete:" "$(jq -r '.delete' "$FRONTEND_SYNC_COUNTS")"
fi

if [ -n "$FRONTEND_SYNC_LOG" ] && [ -f "$FRONTEND_SYNC_LOG" ]; then
  print_separator
  printf '%-10s %s\n' "ACCION" "ASSET"
  print_separator
  while IFS=$'\t' read -r action asset_key; do
    printf '%-10s %s\n' "$action" "$asset_key"
  done < "$FRONTEND_SYNC_LOG"
fi

print_separator
print_ok "Despliegue finalizado"
print_info "Siguiente paso recomendado: ./audit/verify.sh <TAG>"
