# Vox Populi

Sistema de votacion descentralizado sobre Internet Computer (ICP), con backend en Motoko y frontend web.

Repositorio oficial: https://github.com/dboillos/vox_populi

## Caracteristicas tecnicas

- Persistencia ortogonal con `persistent actor` y estado estable.
- Arquitectura modular separada por responsabilidades (`types`, `validation`, `aggregations`).
- Insercion de votos optimizada en O(1) con `List.List`.
- Indice en memoria (con espejo estable) para duplicados por `(surveyId, voterId)` en O(1).
- Cache en memoria por encuesta para consultas agregadas sin refiltrar todo el historico.
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
5. Si la validacion es correcta, el backend devuelve email validado y `voterId` pseudonimo.
6. El voto se registra con `voterId` (no con email).

### Mejora de privacidad implementada (v4)

- Version inicial: `voterId` derivado como hash de email en frontend.
- Version actual (piloto TFM): `voterId` opaco aleatorio, asignado por backend y persistido en un registro de identidad estable.
- El `salt_secreto_backend` se mantiene para endurecer semillas/fallbacks internos.

Propiedad de privacidad obtenida:

- No existe una funcion publica determinista `email -> voterId`; el pseudonimo se asigna una vez y se reutiliza.
- En blockchain se persiste `voterId` pseudonimo y no el email.
- Si se exfiltra un subconjunto de votos on-chain, no se puede verificar offline una lista de emails contra esos `voterId`.

Notas tecnicas:

- El registro interno de identidad se indexa por email normalizado validado por OIDC y guarda solo `voterId` opaco.
- La comprobacion de voto duplicado se hace por indice en backend `(surveyId, voterId)`.

### Escalabilidad de consultas y no duplicidad

Mejoras aplicadas:

- Indice de duplicados en memoria `voteLookup` con reconstruccion desde `voteLookupEntries` (estable) tras upgrade.
- Cache por encuesta `surveyVotesCache` para resolver agregaciones y respuestas crudas sin recorrer `storedVotes` completo.
- Actualizacion incremental de ambos indices al registrar un voto valido.

Complejidades relevantes:

- `submitVote`:
	 - validacion de payload: O(n respuestas)
	 - chequeo duplicado: O(1) promedio
	 - persistencia e indices: O(1) promedio
- `hasUserVoted`: O(1) promedio.
- `getAggregatedResults`: O(m), con m=votos de la encuesta (ya no del total global).
- `getRawResponses`: O(m), con m=votos de la encuesta.

### Archivos clave

- Frontend login: `src/vox_populi_frontend/src/lib/login.ts`
- Servicio frontend-canister: `src/vox_populi_frontend/src/lib/canister-service.ts`
- API backend de validacion: `src/vox_populi_backend/main.mo` (`validateGoogleIdToken`)
- Servicio de autenticacion OIDC: `src/vox_populi_backend/auth/auth_service.mo`
- Registro de identidad pseudonima estable: `src/vox_populi_backend/auth/identity_registry_service.mo`
- Flujo de validacion OIDC (claims/tokeninfo): `src/vox_populi_backend/auth/auth_flow.mo`
- Helpers de autenticacion/identidad: `src/vox_populi_backend/auth/auth_helpers.mo`
- Parser de claims tokeninfo: `src/vox_populi_backend/auth/tokeninfo_parser.mo`
- Gestion del salt seudonimo: `src/vox_populi_backend/auth/salt_manager.mo`
- Runtime de indices/cache de voto: `src/vox_populi_backend/vote/vote_runtime_service.mo`
- Servicio de votacion y resultados: `src/vox_populi_backend/vote/voting_service.mo`
- Politicas de voto (validacion y duplicados): `src/vox_populi_backend/vote/vote_policy.mo`
- Consultas de votos en orden de insercion: `src/vox_populi_backend/vote/vote_queries.mo`
- Agregaciones y estadistica: `src/vox_populi_backend/vote/aggregations.mo`
- Servicio de auditoria: `src/vox_populi_backend/audit/audit_service.mo`
- Utilidades de auditoria (formato hash): `src/vox_populi_backend/audit/audit_helpers.mo`
- Tipos HTTP para outcalls IC: `src/vox_populi_backend/infrastructure/ic_http_types.mo`
- Tipos compartidos: `src/vox_populi_backend/shared/types.mo`
- Configuracion de encuesta compartida: `src/vox_populi_backend/shared/survey_config.mo`

### Nota metodologica para TFM

Esta implementacion valida el token con Google en tiempo real via `tokeninfo` (validacion delegada en proveedor de identidad). Es una arquitectura valida para prototipo academico y despliegue controlado. Como trabajo futuro, se puede incorporar verificacion criptografica local de firma JWT (JWKS) dentro de la capa de backend/verificador dedicado.

## Prevencion de voto duplicado (TFM)

### Regla de negocio

Un mismo votante anonimo (`voterId`) no puede emitir mas de un voto en la misma encuesta (`surveyId`).

### Punto de control obligatorio

La restriccion se aplica en backend dentro de `submitVote`, usando un indice runtime de duplicados `(surveyId, voterId) -> voteId` (O(1) promedio) y manteniendo un espejo estable para upgrades.

### Fragmento de control

```motoko
switch (voteLookup.get(voteLookupKey(surveyId, resolvedVoterId))) {
	case (?duplicateVoteId) {
		return {
			success = false;
			message = "Este usuario ya ha votado en esta encuesta";
			voteId = ?("vote-" # Nat.toText(duplicateVoteId));
		};
	};
	case null {};
};
```

### Razon de seguridad

La validacion en frontend es solo UX. La garantia de no duplicidad se hace en backend para que no pueda saltarse modificando cliente o peticiones HTTP.

## Estructura principal

```text
src/vox_populi_backend/
|- main.mo
|- shared/
|  |- types.mo
|  |- survey_config.mo
|  `- validation.mo
|- audit/
|  |- audit_helpers.mo
|  `- audit_service.mo
|- auth/
|  |- auth_flow.mo
|  |- auth_helpers.mo
|  |- identity_registry_service.mo
|  |- auth_service.mo
|  |- salt_manager.mo
|  `- tokeninfo_parser.mo
|- infrastructure/
|  `- ic_http_types.mo
`- vote/
	|- aggregations.mo
	|- vote_policy.mo
	|- vote_queries.mo
	|- vote_runtime_service.mo
	`- voting_service.mo
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
