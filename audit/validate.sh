#!/usr/bin/env bash
# validate.sh - Validación rápida de sintaxis y estructura

set -euo pipefail

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Validación del Sistema de Despliegue Determinista ICP         ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

ERRORS=0

# Función para reportar errores
fail() {
  echo "❌ $1"
  ((ERRORS++))
}

pass() {
  echo "✅ $1"
}

# 1. Verificar estructura de archivos
echo "🔍 Verificando estructura de archivos..."
test -f audit/Dockerfile.build && pass "audit/Dockerfile.build existe" || fail "audit/Dockerfile.build no existe"
test -f audit/trigger_build.sh && pass "audit/trigger_build.sh existe" || fail "audit/trigger_build.sh no existe"
test -f audit/deploy.sh && pass "audit/deploy.sh existe" || fail "audit/deploy.sh no existe"
test -f audit/verify_integrity.sh && pass "audit/verify_integrity.sh existe" || fail "audit/verify_integrity.sh no existe"
test -f audit/README.md && pass "audit/README.md existe" || fail "audit/README.md no existe"
test -f audit/MANIFEST.md && pass "audit/MANIFEST.md existe" || fail "audit/MANIFEST.md no existe"
test -f .github/workflows/trusted-release-pipeline.yml && pass ".github/workflows/trusted-release-pipeline.yml existe" || fail ".github/workflows/trusted-release-pipeline.yml no existe"

echo ""
echo "🔍 Verificando permisos ejecutables..."
test -x audit/trigger_build.sh && pass "trigger_build.sh es ejecutable" || fail "trigger_build.sh no es ejecutable"
test -x audit/deploy.sh && pass "deploy.sh es ejecutable" || fail "deploy.sh no es ejecutable"
test -x audit/verify_integrity.sh && pass "verify_integrity.sh es ejecutable" || fail "verify_integrity.sh no es ejecutable"

echo ""
echo "🔍 Validando sintaxis Bash..."

# Validar trigger_build.sh
if bash -n audit/trigger_build.sh 2>/dev/null; then
  pass "trigger_build.sh: sintaxis Bash correcta"
else
  fail "trigger_build.sh: error de sintaxis Bash"
fi

# Validar deploy.sh
if bash -n audit/deploy.sh 2>/dev/null; then
  pass "deploy.sh: sintaxis Bash correcta"
else
  fail "deploy.sh: error de sintaxis Bash"
fi

# Validar verify_integrity.sh
if bash -n audit/verify_integrity.sh 2>/dev/null; then
  pass "verify_integrity.sh: sintaxis Bash correcta"
else
  fail "verify_integrity.sh: error de sintaxis Bash"
fi

echo ""
echo "🔍 Validando contenido crítico..."

# Verificar presencia de set -e
grep -q "^set -e" audit/trigger_build.sh && pass "trigger_build.sh contiene set -e" || fail "trigger_build.sh no contiene set -e"
grep -q "^set -e" audit/deploy.sh && pass "deploy.sh contiene set -e" || fail "deploy.sh no contiene set -e"
grep -q "^set -e" audit/verify_integrity.sh && pass "verify_integrity.sh contiene set -e" || fail "verify_integrity.sh no contiene set -e"

# Verificar Dockerfile
grep -q "dfinity/sdk:0.32.0" audit/Dockerfile.build && pass "Dockerfile.build especifica dfinity/sdk:0.32.0" || fail "Dockerfile.build no especifica versión correcta"
grep -q "NODE_VERSION=20.11.1" audit/Dockerfile.build && pass "Dockerfile.build especifica Node.js 20.11.1" || fail "Dockerfile.build no especifica Node.js 20.11.1"
grep -q "SOURCE_DATE_EPOCH" audit/Dockerfile.build && pass "Dockerfile.build implementa SOURCE_DATE_EPOCH" || fail "Dockerfile.build no implementa determinismo"

# Verificar workflow
grep -q "v\*" .github/workflows/trusted-release-pipeline.yml && pass "Workflow dispara en tags v*" || fail "Workflow no dispara correctamente"
grep -q "docker build -f audit/Dockerfile.build" .github/workflows/trusted-release-pipeline.yml && pass "Workflow usa audit/Dockerfile.build" || fail "Workflow usa ruta incorrecta"
grep -q "upload-artifact" .github/workflows/trusted-release-pipeline.yml && pass "Workflow publica artefactos" || fail "Workflow no publica artefactos"

echo ""
echo "🔍 Validando contenido de seguridad..."

# Verificar trap en deploy.sh
grep -q "trap secure_teardown" audit/deploy.sh && pass "deploy.sh implementa trap para restore" || fail "deploy.sh no tiene trap"

# Verificar validaciones git
grep -q "git rev-parse --abbrev-ref HEAD" audit/trigger_build.sh && pass "trigger_build.sh valida rama main" || fail "trigger_build.sh no valida rama"
grep -q "git status --porcelain" audit/trigger_build.sh && pass "trigger_build.sh valida estado limpio" || fail "trigger_build.sh no valida estado limpio"

# Verificar identity manager
grep -q "dfx identity use prod_developer" audit/deploy.sh && pass "deploy.sh cambia a prod_developer" || fail "deploy.sh no usa prod_developer"
grep -q "dfx identity use anonymous" audit/deploy.sh && pass "deploy.sh restaura anonymous" || fail "deploy.sh no restaura anonymous"

echo ""
echo "🔍 Validando documentación..."

grep -q "DFX\|Node.js\|Debian" audit/README.md && pass "README.md contiene especificaciones técnicas" || fail "README.md incomplete"
grep -q "trigger_build.sh\|deploy.sh\|verify_integrity.sh" audit/README.md && pass "README.md documenta scripts" || fail "README.md no documenta scripts"

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
if [ $ERRORS -eq 0 ]; then
  echo "║  ✅ VALIDACIÓN EXITOSA - Sistema listo para despliegue        ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
  exit 0
else
  echo "║  ❌ VALIDACIÓN FALLIDA - $ERRORS errores encontrados         ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
  exit 1
fi
