#!/usr/bin/env bash
set -euo pipefail

export GH_PAGER=cat

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

print_separator() {
  echo "============================================================"
}

print_section() {
  print_separator
  echo "$1"
  print_separator
}

if [ -z "${1:-}" ]; then
  echo "Error: Debe proporcionar un Tag como argumento. Ejemplo: $0 v1.2.3"
  exit 1
fi

TAG="$1"
echo "Entorno: ICP CLI/DFX, Node 20.11.1, Debian Bullseye"
echo "Inicio de verificación para la versión $TAG"

BACKEND_CANISTER_ID=$(jq -r '.vox_populi_backend.ic // empty' ./canister_ids.json 2>/dev/null || true)
FRONTEND_CANISTER_ID=$(jq -r '.vox_populi_frontend.ic // empty' ./canister_ids.json 2>/dev/null || true)

if [ -z "$BACKEND_CANISTER_ID" ] || [ -z "$FRONTEND_CANISTER_ID" ]; then
  echo "Error: no se pudieron resolver canister IDs desde canister_ids.json" >&2
  exit 2
fi

print_section "1) Descarga de artefactos forenses"
echo "Release objetivo: $TAG"
rm -rf ./audit_forensic_artifacts
mkdir -p ./audit_forensic_artifacts
gh release download "$TAG" --dir ./audit_forensic_artifacts --pattern "backend.wasm" --pattern "frontend-dist.tgz"

if [ -f "./audit_forensic_artifacts/frontend-dist.tgz" ]; then
  mkdir -p ./audit_forensic_artifacts/frontend-dist
  tar -xzf ./audit_forensic_artifacts/frontend-dist.tgz -C ./audit_forensic_artifacts/frontend-dist
  rm -f ./audit_forensic_artifacts/frontend-dist.tgz
else
  echo "Error: frontend-dist.tgz no se pudo recuperar del release." >&2
  exit 1
fi

BACKEND_WASM=$(find ./audit_forensic_artifacts -name "backend.wasm" | head -n 1)
if [ -z "$BACKEND_WASM" ]; then
  echo "Error: backend.wasm no se pudo recuperar."
  exit 1
fi

FRONTEND_DIST="./audit_forensic_artifacts/frontend-dist"
if [ ! -d "$FRONTEND_DIST" ]; then
  echo "Error: no se pudo extraer frontend-dist." >&2
  exit 1
fi

LOCAL_SHA=$(sha256sum "$BACKEND_WASM" | awk '{print $1}')

if [ "$CLI_TOOL" = "icp" ]; then
  CANISTER_INFO=$(icp canister status "$BACKEND_CANISTER_ID" --network ic --json 2>&1 || true)
  ONCHAIN_SHA=$(echo "$CANISTER_INFO" | jq -r '.module_hash // empty' | sed 's/^0x//')
else
  CANISTER_INFO=$(dfx canister --network ic info vox_populi_backend 2>&1 || true)
  ONCHAIN_SHA=$(echo "$CANISTER_INFO" | sed -n 's/.*Module hash: 0x\([0-9a-f]\{64\}\).*/\1/p' | head -n 1)
fi

if [ -z "$ONCHAIN_SHA" ]; then
  echo "Error: no se pudo extraer el hash on-chain del backend." >&2
  echo "$CANISTER_INFO" >&2
  exit 2
fi

print_section "2) Comparación de backend (local y on-chain)"
echo "Hash local   : $LOCAL_SHA"
echo "Hash on-chain: $ONCHAIN_SHA"

if [ "$ONCHAIN_SHA" = "$LOCAL_SHA" ]; then
  echo "Resultado    : COINCIDEN"
else
  echo "Resultado    : NO COINCIDEN" >&2
  print_separator
  echo "Error de verificación: el hash local y el hash on-chain no coinciden." >&2
  print_separator
  exit 1
fi

print_section "3) Hash por archivo del frontend"

FRONTEND_FILE_COUNT=0
FRONTEND_MATCH_COUNT=0
FRONTEND_MISMATCH_COUNT=0
FRONTEND_MISSING_COUNT=0

if ! command -v python3 >/dev/null 2>&1; then
  echo "Error: python3 es requerido para procesar metadatos on-chain del frontend." >&2
  exit 3
fi

ONCHAIN_FRONTEND_RAW=$(mktemp)
ONCHAIN_FRONTEND_MAP=$(mktemp)

if [ "$CLI_TOOL" = "icp" ]; then
  icp canister call "$FRONTEND_CANISTER_ID" list '(record { start = null; length = null })' \
    --query --network ic > "$ONCHAIN_FRONTEND_RAW"
else
  dfx canister --network ic call --query \
    --candid src/declarations/vox_populi_frontend/vox_populi_frontend.did \
    vox_populi_frontend list '(record { start = null; length = null })' > "$ONCHAIN_FRONTEND_RAW"
fi

python3 - "$ONCHAIN_FRONTEND_RAW" > "$ONCHAIN_FRONTEND_MAP" << 'PY'
import re
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    text = fh.read()

text = text.replace("\r\n", "\n")

key_re = re.compile(r'key\s*=\s*"([^"]+)";')
sha_re = re.compile(r'sha256\s*=\s*opt\s+blob\s+"([^"]+)";')
enc_re = re.compile(r'content_encoding\s*=\s*"([^"]+)";')
hex_re = re.compile(r'\\([0-9a-fA-F]{2})')

current_key = None
current_sha_blob = None
map_out = {}

for line in text.splitlines():
    m_key = key_re.search(line)
    if m_key:
      current_key = m_key.group(1)

    m_sha = sha_re.search(line)
    if m_sha:
      current_sha_blob = m_sha.group(1)

    m_enc = enc_re.search(line)
    if m_enc and current_key:
      enc = m_enc.group(1)
      if enc == "identity" and current_sha_blob:
        hex_bytes = "".join(hex_re.findall(current_sha_blob))
        if len(hex_bytes) == 64:
          map_out[current_key] = hex_bytes.lower()
      current_sha_blob = None

for key in sorted(map_out.keys()):
    print(f"{key}\t{map_out[key]}")
PY

echo "Canister frontend: $FRONTEND_CANISTER_ID"
echo "Fuente on-chain : método list() del asset canister (encoding=identity)"
print_separator
printf "%-20s  %-64s  %-64s  %s\n" "ESTADO" "HASH_LOCAL" "HASH_MAINNET" "ARCHIVO"
print_separator
while IFS= read -r rel_path; do
  local_sha=$(sha256sum "$FRONTEND_DIST/$rel_path" | awk '{print $1}')
  asset_path="${rel_path#./}"
  canister_key="/$asset_path"
  mainnet_sha=$(awk -F '\t' -v k="$canister_key" '$1 == k { print $2; exit }' "$ONCHAIN_FRONTEND_MAP")

  if [ -z "$mainnet_sha" ]; then
    mainnet_sha="-"
    status="FALTA_EN_MAINNET"
    FRONTEND_MISSING_COUNT=$((FRONTEND_MISSING_COUNT + 1))
  elif [ "$local_sha" = "$mainnet_sha" ]; then
    status="COINCIDE"
    FRONTEND_MATCH_COUNT=$((FRONTEND_MATCH_COUNT + 1))
  else
    status="NO_COINCIDE"
    FRONTEND_MISMATCH_COUNT=$((FRONTEND_MISMATCH_COUNT + 1))
  fi

  printf "%-20s  %-64s  %-64s  %s\n" "$status" "$local_sha" "$mainnet_sha" "$asset_path"
  FRONTEND_FILE_COUNT=$((FRONTEND_FILE_COUNT + 1))
done < <(cd "$FRONTEND_DIST" && find . -type f ! -name '*.map' ! -name '.DS_Store' ! -name '.ic-assets.json5' | LC_ALL=C sort)

rm -f "$ONCHAIN_FRONTEND_RAW" "$ONCHAIN_FRONTEND_MAP"

if [ "$FRONTEND_FILE_COUNT" -eq 0 ]; then
  echo "Advertencia: no se encontraron archivos de frontend para calcular hash." >&2
else
  print_separator
  echo "Total de archivos frontend procesados: $FRONTEND_FILE_COUNT"
  echo "Coincidencias                     : $FRONTEND_MATCH_COUNT"
  echo "Diferencias                       : $FRONTEND_MISMATCH_COUNT"
  echo "Faltantes en mainnet              : $FRONTEND_MISSING_COUNT"
fi

echo "Identidad restaurada a anonymous"
if [ "$CLI_TOOL" = "icp" ]; then
  icp identity default anonymous >/dev/null 2>&1 || true
else
  dfx identity use anonymous >/dev/null 2>&1 || true
fi
print_separator
if [ "$FRONTEND_MISMATCH_COUNT" -eq 0 ] && [ "$FRONTEND_MISSING_COUNT" -eq 0 ]; then
  echo "Verificación finalizada correctamente."
else
  echo "Verificación finalizada con discrepancias en frontend." >&2
  exit 1
fi
