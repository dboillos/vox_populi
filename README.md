# Vox Populi

Sistema de votacion descentralizado sobre Internet Computer (ICP), con backend en Motoko y frontend web.

Repositorio oficial: https://github.com/dboillos/vox_populi

## Caracteristicas tecnicas

- Persistencia ortogonal con `persistent actor` y estado estable.
- Arquitectura modular separada por responsabilidades (`types`, `validation`, `aggregations`).
- Insercion de votos optimizada en O(1) con `List.List`.
- Timestamp de red (`Time.now()`) para evitar manipulacion de reloj cliente.

## Estructura principal

```text
src/vox_populi_backend/
|- main.mo
|- types.mo
|- validation.mo
`- aggregations.mo
```

## Como verificar

Objetivo: comprobar que el codigo desplegado (hash on-chain) coincide con el binario WASM compilado desde una version concreta del repositorio.

### 1) Preparar entorno

Instala herramientas segun tu sistema operativo:

- Git: https://git-scm.com/downloads
- DFX: https://internetcomputer.org/docs/current/developer-docs/getting-started/install/

Verifica instalacion:

```bash
git --version
dfx --version
```

### 2) Clonar y fijar version exacta

```bash
git clone https://github.com/dboillos/vox_populi.git
cd vox_pop
git checkout <tag-o-commit-a-auditar>
```

### 3) Compilar y calcular hashes locales

```bash
dfx build
shasum -a 256 .dfx/local/canisters/vox_populi_backend/vox_populi_backend.wasm
shasum -a 256 .dfx/local/canisters/vox_populi_frontend/vox_populi_frontend.wasm
```

### 4) Obtener hashes on-chain

Opcion recomendada para usuario final:

- Abrir la pantalla de auditoria de la app y copiar los valores de "On-chain module hash" para backend y frontend.

Opcion CLI (requiere permisos de controller del canister consultado):

```bash
dfx canister status <canister-id>
```

### 5) Comparar

Si los SHA-256 locales coinciden exactamente con los hashes on-chain, el binario desplegado corresponde a esa version del codigo.
