# Sistema de Despliegue Determinista en ICP

## Descripción General

Sistema 100% automatizado y determinista para desplegar canisters en Internet Computer (ICP) Mainnet con garantías de integridad absoluta, reproducibilidad y auditoría forense.

### Especificaciones Técnicas Fijas

- **DFX**: 0.32.0
- **Node.js**: 20.11.1 LTS
- **Sistema Base**: Debian Bullseye (imagen `dfinity/sdk:0.32.0`)
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
- **Publica**: Artefactos en GitHub (accesibles vía `gh run download`)

### 3. **build_and_deploy.sh**
Script full-auto de despliegue en Mainnet:

```bash
./audit/build_and_deploy.sh v1.2.3
```

**Fases ejecutadas automáticamente:**

| Fase | Acción |
|------|--------|
| **Validación Git** | Verifica rama `main` y estado limpio |
| **Tagging** | Crea tag y hace push a GitHub |
| **Polling Actions** | Espera ejecución de workflow con `gh run watch` |
| **Descarga** | Obtiene artefactos a `./audit_artifacts/` |
| **Identity Manager** | Cambia a `prod_developer` antes de desplegar |
| **Despliegue** | Instala Wasm en Mainnet (SIN ejecutar `dfx build` localmente) |
| **Auditoría Post** | Consulta canister y compara SHA256 |
| **Limpieza** | Restaura identidad a `anonymous` (trap en EXIT) |

**Ejemplo:**
```bash
./audit/build_and_deploy.sh v1.0.0
```

Output:
```
Entorno fijado: DFX 0.32.0, Node 20.11.1, Imagen base: Debian Bullseye...
Comprobando branch actual y estado del repositorio...
Creando tag v1.0.0 y empujando a GitHub...
Buscando ejecución de GitHub Actions...
Se ha identificado la ejecución de Actions: 12345678. Esperando a que termine...
Descargando artefactos de GitHub Actions a ./audit_artifacts...
Cambiando identidad a prod_developer para proceder al despliegue...
Instalando canister 'backend' con el .wasm descargado...
Fase de auditoría post-despliegue: consultando Mainnet y comparando hashes...
Verificación exitosa: el SHA256 del wasm en GitHub coincide con el registrado on-chain.
Identidad restaurada a anonymous por seguridad
```

### 4. **verify_integrity.sh**
Script de auditoría forense independiente:

```bash
./audit/verify_integrity.sh v1.2.3
```

**Función:**
- Descarga artefactos de GitHub Actions correspondientes al tag
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

### Paso 2: Crear el tag y desplegar
```bash
./audit/build_and_deploy.sh v1.2.3
```

El script automáticamente:
1. Crea el tag `v1.2.3`
2. Espera la ejecución de GitHub Actions
3. Descarga artefactos
4. Cambia identidad a `prod_developer`
5. Despliega el Wasm en Mainnet
6. Audita integridad
7. Restaura `anonymous`

### Paso 3: Auditoría Independiente (opcional)
```bash
./audit/verify_integrity.sh v1.2.3
```

Genera reporte forense completo.

### Paso 4: Verificación Manual on-chain
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
- Identidad `prod_developer` configurada:
  ```bash
  dfx identity new prod_developer  # Si no existe
  dfx identity list  # Verificar que está presente
  ```

### Setup (única vez)
```bash
cd /Users/david/Desktop/ICP/vox_populi

# Crear el workflow (si no se creó aún)
bash audit/setup-workflow.sh

# Hacer ejecutables los scripts
chmod +x audit/build_and_deploy.sh audit/verify_integrity.sh

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

### Error: "identity prod_developer no existe"
- **Solución**: Crear la identidad:
  ```bash
  dfx identity new prod_developer
  dfx identity use prod_developer  # Verificar que funciona
  dfx identity use anonymous       # Volver a anonymous
  ```

---

## Ejemplo de Ejecución Completa

```bash
# 1. Preparar código
cd /Users/david/Desktop/ICP/vox_populi
git status  # Debe estar limpio

# 2. Desplegar con tag v1.0.0
./audit/build_and_deploy.sh v1.0.0

# 3. Esperar hasta que termine (incluye polling automático)

# 4. Verificar on-chain
dfx canister --network ic info backend

# 5. Auditoría independiente
./audit/verify_integrity.sh v1.0.0
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
│   ├── build_and_deploy.sh               # 🚀 Despliegue full-auto
│   ├── verify_integrity.sh               # 🔍 Auditoría forense
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

✅ **build_and_deploy.sh**:
- Validación de rama antes de proceder
- Estado limpio de git obligatorio
- Identity trap para restaurar `anonymous` en casos de error
- Auditoría SHA256 post-despliegue

✅ **verify_integrity.sh**:
- Comparación forense ignorando cachés
- Descarga artefactos desde fuente de verdad (GitHub)
- Cotejación con valores on-chain

---

## Notas Finales

- **NO** se ejecuta `dfx build` localmente durante el despliegue; se usa el Wasm de GitHub Actions.
- **Identity management**: El script automáticamente gestiona `prod_developer` y restaura `anonymous`.
- **Logs**: Todos los scripts producen salida extremadamente verbosa en español.
- **Reproducibilidad**: Cada build produce bytes idénticos gracias a `SOURCE_DATE_EPOCH` y wasm-opt.

---

## Soporte

Para depuración detallada, ejecuta con `set -x`:
```bash
(set -x; ./audit/build_and_deploy.sh v1.0.0)
```

Para verificar el hash del Dockerfile:
```bash
sha256sum audit/Dockerfile.build
```
