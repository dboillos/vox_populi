# Vox Populi

Sistema de votacion descentralizado sobre Internet Computer (ICP), con backend en Motoko y frontend web.

Repositorio oficial: https://github.com/dboillos/vox_populi

## Caracteristicas tecnicas

- Persistencia ortogonal con `persistent actor` y estado estable.
- Arquitectura modular separada por responsabilidades (`types`, `validation`, `aggregations`).
- Insercion de votos optimizada en O(1) con `List.List`.
- Timestamp de red (`Time.now()`) para evitar manipulacion de reloj cliente.
- Login institucional con Google OIDC y validacion de `id_token` en backend.
- Regla de integridad: no se permiten votos duplicados por `(surveyId, voterId)`.

## Autenticacion OIDC (TFM)

### Objetivo

Garantizar que solo miembros de la comunidad UOC puedan votar, sin almacenar el email en blockchain.

### Flujo implementado

1. El frontend inicia Google Identity Services y solicita un `id_token` JWT.
2. El frontend envia `id_token` al backend junto con `expectedAudience` (OAuth Client ID).
3. El backend consulta `https://oauth2.googleapis.com/tokeninfo?id_token=...` mediante HTTPS outcall.
4. El backend valida los campos de seguridad:
	 - `aud` coincide con el client ID esperado.
	 - `iss` es Google (`accounts.google.com` o `https://accounts.google.com`).
	 - `exp` no esta caducado.
	 - `email_verified` es `true`.
	 - `email` pertenece a `@uoc.edu`.
5. Si la validacion es correcta, el frontend recibe email validado y genera `anonymousId` con SHA-256.
6. El voto se registra con `anonymousId` (no con email).

### Archivos clave

- Frontend login: `src/vox_populi_frontend/src/lib/login.ts`
- Servicio frontend-canister: `src/vox_populi_frontend/src/lib/canister-service.ts`
- API backend de validacion: `src/vox_populi_backend/main.mo` (`validateGoogleIdToken`)
- Tipos compartidos: `src/vox_populi_backend/types.mo`

### Nota metodologica para TFM

Esta implementacion valida el token con Google en tiempo real via `tokeninfo` (validacion delegada en proveedor de identidad). Es una arquitectura valida para prototipo academico y despliegue controlado. Como trabajo futuro, se puede incorporar verificacion criptografica local de firma JWT (JWKS) dentro de la capa de backend/verificador dedicado.

## Prevencion de voto duplicado (TFM)

### Regla de negocio

Un mismo votante anonimo (`voterId`) no puede emitir mas de un voto en la misma encuesta (`surveyId`).

### Punto de control obligatorio

La restriccion se aplica en backend dentro de `submitVote`, recorriendo `storedVotes` y bloqueando cuando encuentra una coincidencia exacta de `(surveyId, voterId)`.

### Fragmento de control

```motoko
for (vote in List.toIter(storedVotes)) {
	if (vote.surveyId == surveyId and vote.voterId == resolvedVoterId) {
		return {
			success = false;
			message = "Este usuario ya ha votado en esta encuesta";
			voteId = ?("vote-" # Nat.toText(vote.voteId));
		};
	};
};
```

### Razon de seguridad

La validacion en frontend es solo UX. La garantia de no duplicidad se hace en backend para que no pueda saltarse modificando cliente o peticiones HTTP.

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
