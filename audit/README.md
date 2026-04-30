# Sistema de Despliegue Determinista en ICP

## Descripción General

Sistema 100% automatizado y determinista para desplegar canisters en Internet Computer (ICP) Mainnet con garantías de integridad absoluta, reproducibilidad y auditoría forense.

### Especificaciones Técnicas Fijas

- **DFX**: 0.32.0
- **Node.js**: 20.11.1 LTS
- **Sistema Base**: Ubuntu 24.04 (imagen compatible con el binario oficial de DFX 0.32.0)
- **Backend**: Motoko
- **Frontend**: React + Vite
- **Herramientas**: DFX, Docker, GitHub CLI (`gh`)

---

## Componentes

### 1. **Dockerfile.build**
Contenedor Docker determinista que:
- Fija `SOURCE_DATE_EPOCH` para reproducibilidad total
- Instala Node.js 20.11.1 explícitamente desde binario oficial
- Ejecuta `dfx build --network ic backend` con compilación determinista
- Aplica `wasm-opt -Oz --strip-debug` para eliminar metadatos
- Normalizador de timestamps en archivos fuente
- Salida: `/out/backend.wasm` y `/out/dist/` (bits idénticos en cada construcción)

**Uso local:**
```bash
docker build -f audit/Dockerfile.build -t trusted-build .
CONTAINER_ID=$(docker create trusted-build)
docker cp "$CONTAINER_ID":/out/backend.wasm ./backend.wasm
docker cp "$CONTAINER_ID":/out/dist ./dist
docker rm -v "$CONTAINER_ID"
```

### 2. **.github/workflows/trusted-release-pipeline.yml**
Workflow de GitHub Actions que:
- **Trigger**: Push de tags `v*` (ej: `v1.2.3`) en rama `main`
- **Build**: Usa `audit/Dockerfile.build`
- **Extrae**: `backend.wasm` y `dist/` del contenedor
- **Verifica**: Calcula y registra SHA256 del Wasm
- **Publica**: Assets en el Release del tag (accesibles vía `gh release download`)

### 3. **build.sh** y **deploy.sh**
Scripts automatizados para construcción remota y despliegue en Mainnet. Separados para garantizar un control paso a paso.

```bash
./audit/build.sh v1.2.3
./audit/deploy.sh
```

**Fases ejecutadas automáticamente:**

| Fase | Acción |
|------|--------|
| **Validación Git** | Verifica rama `main` y estado limpio |
| **Tagging** | Crea tag y hace push a GitHub |
| **Polling Actions** | Espera ejecución de workflow con `gh run watch` |
| **Descarga** | Obtiene artefactos a `./audit_artifacts/` |
| **Identity Manager** | Cambia a `prod_deployer` antes de desplegar |
| **Despliegue** | Instala Wasm en Mainnet (SIN ejecutar `dfx build` localmente) |
| **Auditoría Post** | Consulta estado del canister desplegado |
| **Limpieza** | Restaura identidad a `anonymous` (trap en EXIT) |

**Ejemplo:**
```bash
./audit/build.sh v1.0.0
./audit/deploy.sh
```

Output:
```
Entorno fijado: DFX 0.32.0, Node 20.11.1, Imagen base: Ubuntu 24.04...
Comprobando branch actual y estado del repositorio...
Creando tag v1.0.0 y empujando a GitHub...
Buscando ejecución de GitHub Actions...
Se ha identificado la ejecución de Actions: 12345678. Esperando a que termine...
Descargando artefactos de GitHub Actions a ./audit_artifacts...
Cambiando identidad a prod_deployer para proceder al despliegue...
Instalando canister 'backend' con el .wasm descargado...
Fase de auditoría post-despliegue: consultando Mainnet...
Despliegue finalizado.
Identidad restaurada a anonymous por seguridad
```

### 4. **verify.sh**
Script de auditoría forense independiente:

```bash
./audit/verify.sh v1.2.3
```

**Función:**
- Descarga backend.wasm desde los assets del release correspondiente al tag
- Calcula SHA256 locales de todos los archivos
- Consulta la Mainnet via `dfx canister call backend list_assets`
- Compara hashes against on-chain values
- Genera reporte forense ignorando cachés (`.map`, `.DS_Store`)

---

## Flujo de Despliegue Completo

### Paso 1: Preparar el código
```bash
# Asegurar que todo está committeado en main
git status  # Debe estar limpio
git log --oneline -1  # Mostrar último commit
```

### Paso 2: Crear el tag y descargar artefactos
```bash
./audit/build.sh v1.2.3
```

El script automáticamente:
1. Crea el tag `v1.2.3`
2. Espera la ejecución de GitHub Actions
3. Descarga artefactos

### Paso 3: Desplegar en Mainnet
```bash
./audit/deploy.sh
```

El script automáticamente:
1. Usa el Wasm descargado en `./audit_artifacts/`
2. Cambia identidad a `prod_deployer`
3. Despliega el Wasm en Mainnet
4. Restaura `anonymous`

### Paso 4: Auditoría Independiente (opcional)
```bash
./audit/verify.sh v1.2.3
```

Genera reporte forense completo.

### Paso 5: Verificación Manual on-chain
```bash
dfx canister --network ic info backend
dfx canister --network ic call backend list_assets 2>&1 | grep -Eo '[0-9a-f]{64}'
```

---

## Configuración Previa

### Requerimientos
- `curl`, `git`, `docker` instalados
- GitHub CLI (`gh`) configurado y autenticado:
  ```bash
  gh auth login
  ```
- DFX instalado y canister `backend` creado (`dfx.json`)
- Identidad `prod_deployer` configurada:
  ```bash
  dfx identity new prod_deployer  # Si no existe
  dfx identity list  # Verificar que está presente
  ```

### Setup (única vez)
```bash
cd /Users/david/Desktop/ICP/vox_populi

# Crear el workflow (si no se creó aún)
bash audit/setup-workflow.sh

# Hacer ejecutables los scripts
chmod +x audit/build.sh audit/deploy.sh audit/verify.sh

# Commit del workflow a Git
git add .github/workflows/trusted-release-pipeline.yml
git commit -m "Add trusted release CD pipeline"
git push origin main
```

---

## Variables de Entorno

Estos valores están **fijados en el Dockerfile.build** para determinismo:

```dockerfile
ARG BUILD_EPOCH=1630454400           # Fecha reproducible
ENV SOURCE_DATE_EPOCH=${BUILD_EPOCH}  # Fija timestamps
ENV TZ=UTC
ENV LANG=C.UTF-8
ARG NODE_VERSION=20.11.1             # Node.js exacto
```

No requieren configuración manual.

---

## Troubleshooting

### Error: "no se localizó la ejecución de GitHub Actions"
- **Causa**: El workflow tardó más de 5 minutos o no se ejecutó.
- **Solución**: Verificar que `.github/workflows/trusted-release-pipeline.yml` existe en el repositorio.
  ```bash
  git ls-files | grep workflows
  ```

### Error: "backend.wasm no encontrado"
- **Causa**: El contenedor Docker falló en la compilación.
- **Solución**: Ejecutar Dockerfile localmente para ver logs:
  ```bash
  docker build -f audit/Dockerfile.build -t trusted-build . 2>&1 | tail -50
  ```

### Error: "la rama actual no es main"
- **Solución**: Cambiar a main:
  ```bash
  git checkout main
  git pull origin main
  ```

### Error: "identity prod_deployer no existe"
- **Solución**: Crear la identidad:
  ```bash
  dfx identity new prod_deployer
  dfx identity use prod_deployer  # Verificar que funciona
  dfx identity use anonymous       # Volver a anonymous
  ```

---

## Ejemplo de Ejecución Completa

```bash
# 1. Preparar código
cd /Users/david/Desktop/ICP/vox_populi
git status  # Debe estar limpio

# 2. Trigger de build remoto y descarga de artefactos
./audit/build.sh v1.0.0

# 3. Deploy del Wasm descargado
./audit/deploy.sh

# 4. Verificar on-chain
dfx canister --network ic info backend

# 5. Auditoría independiente
./audit/verify.sh v1.0.0
```

---

## Archivos del Sistema

```
vox_populi/
├── .github/
│   └── workflows/
│       └── trusted-release-pipeline.yml   # 🔄 GitHub Actions workflow
├── audit/
│   ├── Dockerfile.build                   # 🐳 Construcción determinista
│   ├── build.sh                          # 🏷️ Trigger + descarga de artefactos
│   ├── deploy.sh                         # 🚀 Deploy en Mainnet
│   ├── verify.sh                         # 🔍 Auditoría forense
│   └── setup-workflow.sh                 # 🛠️ Setup inicial (uso único)
├── src/
├── dfx.json
└── package.json
```

---

## Seguridad & Auditoría

### Garantías de Determinismo

✅ **Dockerfile.build**:
- Timestamps fijados (`SOURCE_DATE_EPOCH`)
- Arquitectura soportada (amd64, arm64)
- Node.js descargado desde oficial nodejs.org
- Compilación sin variables de entorno inestables
- WASM stripped de debug info

✅ **deploy.sh**:
- Validación de rama antes de proceder
- Estado limpio de git obligatorio
- Identity trap para restaurar `anonymous` en casos de error
- Despliegue controlado con fallback para `IC0504`

✅ **verify.sh**:
- Comparación forense ignorando cachés
- Descarga artefactos desde fuente de verdad (GitHub)
- Cotejación con valores on-chain

---

## Notas Finales

- **NO** se ejecuta `dfx build` localmente durante el despliegue; se usa el Wasm de GitHub Actions.
- **Identity management**: El script automáticamente gestiona `prod_deployer` y restaura `anonymous`.
- **Logs**: Todos los scripts producen salida extremadamente verbosa en español.
- **Reproducibilidad**: Cada build produce bytes idénticos gracias a `SOURCE_DATE_EPOCH` y wasm-opt.

---

## Soporte

Para depuración detallada, ejecuta con `set -x`:
```bash
(set -x; ./audit/build.sh v1.0.0)
(set -x; ./audit/deploy.sh)
```

Para verificar el hash del Dockerfile:
```bash
sha256sum audit/Dockerfile.build
```
