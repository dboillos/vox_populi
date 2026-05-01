# Documentación del Sistema de Auditoría y Despliegue Determinista

## Tabla de Contenidos

1. [Introducción](#introducción)
2. [Flujo de Trabajo General](#flujo-de-trabajo-general)
3. [build.sh](#buildsh)
4. [deploy.sh](#deploysh)
5. [verify.sh](#verifysh)
6. [validate.sh](#validatesh)
7. [Dockerfile.build](#dockerfilebuild)
8. [GitHub Actions Workflow](#github-actions-workflow)
9. [Especificaciones Técnicas](#especificaciones-técnicas)
10. [Casos de Uso y Ejemplos](#casos-de-uso-y-ejemplos)

---

## Introducción

Este sistema proporciona un conjunto automatizado de herramientas para construir, desplegar y verificar canisters en Internet Computer (ICP) Mainnet con garantías de:

- **Determinismo**: Las construcciones producen binarios idénticos byte-a-byte
- **Reproducibilidad**: Cualquier auditor externo puede reconstruir y verificar los artefactos
- **Trazabilidad**: Cada despliegue es registrable y auditable
- **Seguridad**: Mecanismos explícitos de confirmación para operaciones destructivas

---

## Flujo de Trabajo General

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. Developer: git tag v1.2.3 && git push origin v1.2.3         │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│ 2. GitHub Actions: trusted-release-pipeline.yml                │
│    - Build: Dockerfile.build (determinista)                    │
│    - Extract: backend.wasm + frontend-dist.tgz                │
│    - Publish: Release assets                                   │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│ 3. Auditor: ./audit/build.sh v1.2.3                            │
│    - Descarga artefactos del release                           │
│    - Verifica integridad de descarga                           │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│ 4. Operator: ./audit/deploy.sh v1.2.3                          │
│    - (Opcional) Uso de --reinstall para reset                 │
│    - Actualiza canisters en ICP Mainnet                       │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│ 5. Auditor: ./audit/verify.sh v1.2.3                           │
│    - Descarga artefactos localmente                            │
│    - Compara hashes: local vs on-chain                         │
│    - Genera reporte de coincidencia                            │
└─────────────────────────────────────────────────────────────────┘
```

---

## build.sh

### Propósito

Script de descarga y validación de artefactos de construcción desde el pipeline de integración continua. Automatiza el proceso de obtener binarios verificables desde el repositorio de releases.

### Flujo de Ejecución

1. **Validación de Precondiciones**
   - Verifica que se proporcione un tag de versión (ej: `v1.2.3`)
   - Valida que la rama actual sea `main`
   - Confirma que el repositorio esté limpio (sin cambios pendientes)

2. **Publicación del Tag**
   - Crea un tag anotado con mensaje "Release Trusted Build {TAG}"
   - Envía el tag a `origin` para disparar el workflow de GitHub Actions

3. **Polling del Workflow**
   - Espera hasta 150 segundos (30 intentos × 5 segundos)
   - Detecta el `RUN_ID` de GitHub Actions asociado al tag
   - Observa el progreso del workflow con `gh run watch`

4. **Descarga de Artefactos**
   - Reintentos automáticos (12 intentos) para descargar:
     - `backend.wasm`
     - `frontend-dist.tgz`
   - Descomprime y organiza archivos en `./audit_artifacts/`

5. **Validación Postcarga**
   - Verifica existencia de `backend.wasm`
   - Verifica estructura de `frontend-dist/index.html`
   - Calcula y registra SHA256 de todos los artefactos

### Parámetros

```bash
./audit/build.sh <TAG>
```

- `TAG`: Identificador de versión en formato `vX.Y.Z` (ej: `v1.2.3`)

### Salida

Directorio `./audit_artifacts/` con estructura:
```
audit_artifacts/
├── backend-wasm/
│   └── backend.wasm          # Wasm compilado del backend
├── frontend-dist/
│   ├── index.html
│   ├── assets/
│   │   ├── index-*.css
│   │   └── index-*.js
│   ├── favicon.ico
│   └── logo2.svg
└── sha256.log               # Hashes de validación
```

### Códigos de Salida

- `0`: Éxito
- `1`: El argumento TAG no se proporcionó
- `2`: No en rama `main` o repositorio sucio
- `5`: Falló la descarga de artefactos después de reintentos
- `6`: `backend.wasm` no encontrado en descargas
- `7`: `frontend-dist/index.html` no encontrado en descargas

### Requisitos Externos

- `git`: Control de versiones
- `gh` (GitHub CLI): Acceso a releases y workflows
- `jq`: Parsing JSON (no usado directamente, pero esperado)
- `tar`: Extracción de archivos

### Consideraciones de Seguridad

- Rechaza ejecución si hay cambios locales no comprometidos
- Requiere rama `main` para garantizar cadena de custodia
- Descarga solo desde releases oficiales (inmutables)
- Valida integridad con SHA256 postcarga

---

## deploy.sh

### Propósito

Script de despliegue de canisters a ICP Mainnet. Maneja sincronización de assets del frontend, actualización del backend, y proporciona opciones para reinicio completo del canister (eliminando estado previo).

### Arquitectura de Parámetros

```bash
# Modo 1: Descargar release y desplegar
./audit/deploy.sh v1.2.3
./audit/deploy.sh --tag v1.2.3

# Modo 2: Desplegar desde archivos locales
./audit/deploy.sh ./backend.wasm ./dist/

# Modo 3: Reinicio completo (opcional)
./audit/deploy.sh --reinstall v1.2.3
./audit/deploy.sh --tag v1.2.3 --reinstall
./audit/deploy.sh --reinstall ./backend.wasm ./dist/
```

### Flujo de Ejecución

#### Fase 1: Resolución de Artefactos

- Si se proporciona un tag de versión (ej: `v1.2.3`), descarga desde GitHub Releases
- De lo contrario, busca archivos locales en:
  - `./audit_artifacts/backend.wasm`
  - `./audit_artifacts/backend-wasm/backend.wasm`
  - `./audit_artifacts/frontend-dist/`
  - `./src/vox_populi_frontend/dist/`

#### Fase 2: Selección de CLI

Evalúa disponibilidad de herramientas en el orden:
1. `icp` (CLI moderna de Internet Computer) - preferida
2. `dfx` (herramienta legacy de DFINITY) - fallback

Detecta automáticamente qué CLI soporta la identidad `prod_deployer`.

#### Fase 3: Cambio de Identidad

- Intenta seleccionar la identidad `DEPLOY_IDENTITY` (por defecto: `prod_deployer`)
- Soporta variable de entorno: `export DEPLOY_IDENTITY=otra_identidad`

#### Fase 4: Instalación del Backend

**Comportamiento sin --reinstall (por defecto):**
- Intenta modo `upgrade` (preserva estado)
- Si falla con IC0504 (restricción de persistencia):
  - Notifica al usuario: "Requiere --reinstall para perder estado"
  - Aborta para proteger datos

**Comportamiento con --reinstall:**
- Salta directamente a modo `reinstall`
- Requiere confirmación explícita: usuario debe escribir "REINSTALL"
- Elimina completamente el estado anterior
- Útil para despliegues iniciales o resets intencionales

#### Fase 5: Sincronización de Assets del Frontend

- Descarga lista actual de assets en mainnet
- Compara con archivos locales (file-by-file)
- Genera argumentos DIDL con:
  - Encoding identity (siempre)
  - Encoding gzip (sobreescribe versiones stale)
  - Hashes SHA256 para integridad
- Ejecuta store para nuevos/actualizados
- Ejecuta delete para assets que ya no existen

#### Fase 6: Limpieza y Reporte

- Restaura identidad a `anonymous`
- Limpia archivos temporales
- Imprime resumen de cambios (assets upsert/delete)

### Variables de Entorno

```bash
DEPLOY_IDENTITY      # Identidad a usar (default: prod_deployer)
```

### Opciones de Línea de Comandos

| Opción | Comportamiento |
|--------|----------------|
| `--tag TAG` | Descargar release `TAG` |
| `--reinstall` | Eliminar estado del backend |
| `--tag-and-reinstall TAG` | Combinar ambos (menos usado) |
| Sin opciones | Buscar archivos locales en `./audit_artifacts/` |

### Códigos de Salida

- `0`: Despliegue exitoso
- `1`: Falla en configuración (identidad no encontrada)
- `2`: Archivo wasm o directorio frontend no encontrado
- `3`: Parámetro no reconocido
- `4+`: Errores de instalación en canister

### Confirmación de Reinstall

```
⚠️  ATENCIÓN: Se ejecutará REINSTALL y se perderá TODO el estado almacenado en el backend

Escribe 'REINSTALL' para confirmar (sin comillas): 
```

**Nota**: Requiere exactamente la cadena "REINSTALL" (sensible a mayúsculas).

### Requisitos Externos

- `icp` CLI (v0.2+) o `dfx` (v0.31+)
- `jq`: Parsing de `canister_ids.json`
- `tar`: Extracción de frontend-dist
- `python3`: Generación de argumentos DID (inline)

### Consideraciones Operacionales

- **Idempotencia Parcial**: El frontend es idempotente (sincronización exacta), pero el backend no
- **Reversibilidad**: Un `--reinstall` es destructivo e irreversible
- **Costos en Cycles**: Sincronización de frontend puede ser costosa si hay muchos assets nuevos
- **Tiempos**: Operaciones de backend típicamente tardan 30-60 segundos

---

## verify.sh

### Propósito

Script de auditoría forense que valida que los artefactos desplegados en mainnet coinciden exactamente con los publicados en el release de GitHub. Proporciona evidencia de integridad criptográfica.

### Flujo de Ejecución

#### Fase 1: Descarga de Artefactos Forenses

- Descarga desde GitHub Releases:
  - `backend.wasm`
  - `frontend-dist.tgz`
- Organiza en `./audit_forensic_artifacts/`

#### Fase 2: Comparación del Backend

- Calcula SHA256 local del `backend.wasm` descargado
- Obtiene `module_hash` on-chain vía `canister status`
- Compara ambos valores
- Reporta: `COINCIDEN` o `DIFIEREN`

#### Fase 3: Comparación de Assets del Frontend

- Obtiene lista de assets on-chain vía `list()` method
- Extrae cada asset y calcula SHA256 local
- Compara con hash on-chain
- Reporta estado por archivo:
  - `COINCIDE`: Hashes coinciden
  - `NO_COINCIDE`: Hash diferente (posible corrupción)
  - `FALTA_EN_MAINNET`: Archivo no está en mainnet

#### Fase 4: Reporte Final

```
ESTADO                HASH_LOCAL                                        ARCHIVO
COINCIDE              b8500bfc0f80892f0e37c8908cc6d9777049045eb...    assets/index.css
```

### Parámetros

```bash
./audit/verify.sh <TAG>
```

- `TAG`: Identificador de versión (ej: `v1.2.3`)

### Salida Esperada

**Óptima**:
```
Backend: COINCIDE
Frontend: 5 archivos, 5 coincidencias, 0 diferencias, 0 faltantes
```

**Sospechosa**:
```
Backend: DIFIEREN (posible compromiso o versión incorrecta)
Frontend: 1 NO_COINCIDE, 1 FALTA_EN_MAINNET
```

### Códigos de Salida

- `0`: Verificación exitosa (todos coinciden)
- `1`: No se proporciona TAG
- `2`: Canister IDs no resolubles desde `canister_ids.json`
- `10`: Descargas fallidas
- `20`: Backend no coincide
- `30`: Algún asset frontend no coincide

### Requisitos Externos

- `gh` (GitHub CLI): Descargar artefactos
- `icp` o `dfx`: Llamadas al canister `list()` y `canister status`
- `tar`: Extracción de frontend
- `sha256sum`: Cálculo de hashes

### Interpretación de Resultados

| Escenario | Implicación |
|-----------|-------------|
| Backend COINCIDE, Frontend todo COINCIDE | ✅ Sistema íntegro |
| Backend COINCIDE, Frontend con NO_COINCIDE | ⚠️ Posible ataque de assets |
| Backend DIFIERE | 🔴 Posible compromiso crítico |
| Assets FALTA_EN_MAINNET | 🟡 Despliegue incompleto |

---

## validate.sh

### Propósito

Script de validación preliminar que verifica la integridad estructural del sistema de auditoría antes de ejecutar operaciones críticas.

### Validaciones Realizadas

1. **Estructura de Archivos**
   - Existencia de todos los scripts: `build.sh`, `deploy.sh`, `verify.sh`
   - Existencia de `Dockerfile.build`
   - Existencia de archivos de documentación

2. **Permisos Ejecutables**
   - `build.sh`, `deploy.sh`, `verify.sh` tienen bit ejecutable

3. **Sintaxis Bash**
   - Validación con `bash -n` para cada script
   - Detección de errores de sintaxis

4. **Dependencias Externas**
   - `git`, `gh`, `docker`, `jq`, `icp`/`dfx`
   - Verifica presencia en `$PATH`

5. **Integridad de Configuración**
   - Lectura correcta de `canister_ids.json`
   - Resolución de canister IDs

### Parámetros

Sin parámetros:

```bash
./audit/validate.sh
```

### Salida

Informe visual con indicadores:
- ✅ `pass`: Validación exitosa
- ❌ `fail`: Validación fallida
- 🔍 Secciones de validación

Ejemplo:
```
✅ Estructura de archivos: OK
❌ Docker disponible: FALLÓ
✅ Sintaxis Bash: OK
```

### Códigos de Salida

- `0`: Todas las validaciones pasaron
- `1+`: Cantidad de fallos

### Uso Recomendado

Ejecutar antes de despliegues:

```bash
./audit/validate.sh && ./audit/deploy.sh v1.2.3
```

---

## Dockerfile.build

### Propósito

Especificación de contenedor Docker para construcción determinista del backend. Garantiza que compilaciones en diferentes máquinas produzcan binarios idénticos.

### Mecanismos de Determinismo

#### 1. SOURCE_DATE_EPOCH

```dockerfile
ENV SOURCE_DATE_EPOCH=1704067200
```

Fija el timestamp de compilación a una fecha fija (2024-01-01). Impide que metadatos de tiempo se incluyan en el binario.

#### 2. Node.js Descargado Explícitamente

```dockerfile
RUN curl -sL https://nodejs.org/dist/v20.11.1/node-v20.11.1-linux-x64.tar.xz | \
    tar -xJ -C /usr/local
```

Evita variaciones de paquetes de distribución.

#### 3. DFX Pinned

```dockerfile
RUN curl -fsSL https://sdk.dfinity.org/install.sh | sh
# (instala versión 0.32.0 configurada en dfx.json)
```

#### 4. Flags de Compilación Deterministas

```dockerfile
RUN dfx build --network ic backend && \
    wasm-opt -Oz --strip-debug -o optimized.wasm backend.wasm
```

- `-Oz`: Máxima optimización de tamaño
- `--strip-debug`: Elimina símbolos de debug
- `--network ic`: Compilación específica para mainnet

#### 5. Normalización de Timestamps

```dockerfile
RUN find /workspace -type f -exec touch -d @${SOURCE_DATE_EPOCH} {} \;
```

Iguala timestamps de todos los archivos fuente.

### Salida

```
/out/backend.wasm              # Binario Wasm optimizado
/out/dist/                     # Frontend pre-compilado (Vite)
```

### Reproducibilidad

Para verificar determinismo:

```bash
# Primera compilación
docker build -f audit/Dockerfile.build -t build1 .
docker create build1 | xargs docker cp -q {}:/out - | tar xz

# Segunda compilación
docker build -f audit/Dockerfile.build -t build2 .
docker create build2 | xargs docker cp -q {}:/out - | tar xz

# Comparar
sha256sum backend.wasm*  # Deben ser idénticos
```

---

## GitHub Actions Workflow

### Archivo

`.github/workflows/trusted-release-pipeline.yml`

### Trigger

Push de tags con patrón `v*`:

```bash
git tag v1.2.3
git push origin v1.2.3
```

Esto dispara automáticamente el workflow.

### Pasos del Workflow

1. **Checkout**: Descarga código del tag
2. **Build**: Ejecuta `docker build -f audit/Dockerfile.build`
3. **Extract**: Copia `/out/backend.wasm` y `/out/dist/` del contenedor
4. **Log Hashes**: Imprime SHA256 de artefactos (visible en logs públicos)
5. **Publish**: Carga assets a GitHub Releases

### Logs Públicos

Los logs son accesibles públicamente en:
```
https://github.com/{owner}/{repo}/actions/runs/{run_id}
```

Contienen hashes SHA256 para auditoría externa.

### Artefactos Generados

En cada release se publican:
- `backend.wasm`: Binario Wasm del backend
- `frontend-dist.tgz`: Frontend empaquetado

Descargables vía:

```bash
gh release download v1.2.3 --pattern "backend.wasm"
```

---

## Especificaciones Técnicas

### Versiones Pinned

| Componente | Versión | Justificación |
|------------|---------|---------------|
| Node.js | 20.11.1 LTS | Estabilidad, compatible con DFX 0.32.0 |
| DFX | 0.32.0 | Última versión stable con soporte completo |
| Ubuntu | 24.04 | Binarios DFX compilados para esta versión |
| icp CLI | ≥ 0.2 | CLI moderna, recomendada |

### Canister IDs (Mainnet)

```json
{
  "vox_populi_backend": { "ic": "46im3-biaaa-aaaaj-qqwra-cai" },
  "vox_populi_frontend": { "ic": "4zjkp-mqaaa-aaaaj-qqwrq-cai" }
}
```

### Hashes de Assets (v1.2.106)

Se mantienen en `src/vox_populi_frontend/src/lib/i18n.ts`:

```javascript
export const FRONTEND_ASSETS_MAINNET = [
  { file: "index.html", hash: "a485f1f458f1cef..." },
  { file: "assets/index-b8500bfc.css", hash: "b8500bfc0f80892f..." },
  // ...
]
```

---

## Casos de Uso y Ejemplos

### Caso 1: Despliegue Estándar (Upgrade)

```bash
# 1. Developer: crear release
git tag v1.2.3
git push origin v1.2.3

# 2. Esperar ~5 min a que GitHub Actions complete

# 3. Auditor: verificar artefactos
./audit/build.sh v1.2.3

# 4. Operator: desplegar
./audit/deploy.sh v1.2.3

# 5. Auditor: verificar integridad on-chain
./audit/verify.sh v1.2.3
# Resultado esperado: "COINCIDEN"
```

### Caso 2: Reset Completo (Reinicio)

```bash
# Cuando se requiere eliminar estado anterior
./audit/deploy.sh --reinstall v1.2.3

# En el prompt:
# Escribe 'REINSTALL' para confirmar: REINSTALL

# Resultado: Backend completamente reiniciado
```

### Caso 3: Auditoría Externa

Cualquiera puede verificar:

```bash
# 1. Clonar repositorio
git clone https://github.com/.../vox_populi.git
cd vox_populi
git checkout v1.2.3

# 2. Descargar y compilar localmente
./audit/build.sh v1.2.3

# 3. Verificar on-chain
./audit/verify.sh v1.2.3

# Output: comparación de hashes local vs mainnet
```

### Caso 4: Despliegue desde Archivos Locales

Para desarrollo local (no para producción):

```bash
npm run build  # Construir frontend localmente

./audit/deploy.sh \
  ./audit_artifacts/backend.wasm \
  ./src/vox_populi_frontend/dist/
```

### Caso 5: Validación Previa

```bash
# Antes de cualquier operación crítica
./audit/validate.sh

# Si pasa:
./audit/deploy.sh v1.2.3
```

---

## Notas de Implementación

### Idempotencia

- **Frontend**: Totalmente idempotente (sincronización exacta)
- **Backend**: No idempotente en upgrade mode (requiere lógica de migración)

### Seguridad

- Rechaza cambios no comprometidos
- Requiere rama `main` para builds
- Exige confirmación explícita para reinstall
- Registra todas las operaciones

### Performance

- Build: ~3 minutos (GitHub Actions)
- Deploy backend: ~30-60 segundos
- Sync frontend: ~5-30 segundos (según cantidad de assets)
- Verify: ~2-5 minutos

### Troubleshooting

| Problema | Solución |
|----------|----------|
| "IC0504 - Upgrade requires canister state" | Usar `--reinstall` |
| "No se detectó ejecución en GitHub Actions" | Verificar permisos de push; retries automáticos |
| "backend.wasm no encontrado" | Revisar que el build completó en Actions; verificar releases |
| "Deploy identity not found" | Crear identidad: `icp identity new prod_deployer` |
| "Assets NO_COINCIDE en verify.sh" | Redesplegar frontend; revisar encoding |

---

## Referencias Documentación

- Internet Computer SDK: https://sdk.dfinity.org
- icp CLI: https://github.com/dfinity/ic
- GitHub Actions: https://github.com/features/actions
- Docker: https://docs.docker.com/

