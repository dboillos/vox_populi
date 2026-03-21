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

## Medidas de seguridad implementadas

### Objetivo

Garantizar voto institucional verificable y resistente a manipulacion de cliente, preservando anonimato de la identidad en blockchain.

### 1) Autenticacion OIDC validada en backend

1. El frontend obtiene `id_token` con Google Identity Services.
2. El backend valida el token mediante `tokeninfo` de Google.
3. Se validan claims de seguridad obligatorias:
	- `aud` coincide con el cliente OAuth esperado.
	- `iss` pertenece a Google.
	- `exp` no esta caducado.
	- `email_verified` es `true`.
	- el dominio permitido es `@uoc.edu`.

### 2) Escritura de voto protegida

1. `submitVote` exige `idToken` y no acepta identidad de voto elegida por cliente.
2. El backend deriva la identidad efectiva (`voterId`) tras validacion OIDC.
3. Solo se persiste voto cuando la autenticacion es valida.

Propiedad conseguida:

- La identidad de voto la decide el backend, no el navegador.

### 3) Prevencion de voto duplicado

Regla de negocio:

- Un mismo `voterId` no puede votar dos veces en la misma encuesta (`surveyId`).

Implementacion:

- Indice de duplicados en memoria O(1) promedio con espejo estable para upgrades.
- Rechazo funcional cuando ya existe voto previo para `(surveyId, voterId)`.

### 4) Privacidad de identidad

1. El email no se persiste en blockchain como identidad de voto.
2. Se usa `voterId` pseudonimo opaco, asignado por backend y persistido en registro estable.
3. No existe endpoint publico determinista `email -> voterId`.

Explicacion criptografica (hash + salt):

- En un esquema de seudonimizacion por derivacion, se concatena el email con un `salt` secreto del backend y se aplica una funcion hash criptografica.
- El resultado (`voterId`) es de una sola via: se puede calcular desde `email + salt`, pero no es reversible para recuperar el email original.
- Con `salt` secreto se evita la comparacion directa entre sistemas y se dificulta el uso de tablas precalculadas.

Matiz importante de seguridad:

- No se afirma imposibilidad matematica absoluta, sino inviabilidad computacional bajo el modelo de amenaza considerado (hash robusto, salt secreto y sin fuga de claves).

Nota de implementacion en este proyecto:

- La estrategia principal es `voterId` opaco no determinista emitido por backend; esto evita exponer una derivacion publica del email y mantiene la separacion entre identidad institucional y voto on-chain.

### 5) Determinismo en HTTPS outcalls

Problema mitigado:

- Diferencias menores en respuestas HTTP externas pueden afectar consenso de subred.

Mitigacion implementada:

1. `transformGoogleTokenInfoResponse` normaliza respuesta de `tokeninfo`.
2. Se eliminan headers volatiles.
3. Se conserva solo JSON canonico con claims necesarias (`aud`, `iss`, `exp`, `email`, `email_verified`).
4. Para errores HTTP, se conserva `status` con cuerpo vacio.

### 6) Gestion de expiracion de token y re-login

1. Si `submitVote` devuelve autenticacion invalida/expirada, el frontend fuerza re-login.
2. Se limpia sesion local, se vuelve a landing y se abre modal de login automaticamente.
3. Se muestra aviso visual de sesion expirada antes de continuar.

### 7) Almacenamiento de sesion en navegador

Politica aplicada:

- El estado de sesion se guarda en `sessionStorage` (no en `localStorage`).

Claves relevantes:

1. `voxpopuli_session` (email, voterId, idToken, expiresAt).
2. `voxpopuli_locale` (idioma activo).
3. `voxpopuli_force_relogin` y `voxpopuli_relogin_reason` (flujo de reautenticacion).

Propiedad conseguida:

- Al cerrar pestana/sesion del navegador, se elimina el estado persistido.

### 8) Transparencia de UX durante escritura

1. El envio de voto muestra modal de progreso por pasos (estado `pending/running/done/error`).
2. Los textos de modales se resuelven por i18n (ES/EN/CA).
3. En error, el usuario recibe motivo explicito y accion de recuperacion.

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

## Prevencion de voto duplicado 

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

## Verificacion desde dashboard de auditoria

Objetivo:

- Comprobar que el codigo que se ejecuta on-chain coincide con el WASM compilado desde una revision concreta del repositorio.

### Datos que muestra el dashboard de auditoria

En la pantalla de auditoria se muestran, por canister (backend/frontend):

1. `Canister ID`.
2. `On-chain module hash`.
3. `Version actual de la app` y referencias de release/commit (si aplica).

Estos campos son la referencia para comparar integridad de despliegue.

### Pasos de comprobacion recomendados

1) Copiar datos on-chain desde dashboard

- Abrir la pantalla de auditoria de la app.
- Copiar `Canister ID` y `On-chain module hash` de backend y frontend.

2) Preparar entorno local

```bash
git --version
dfx --version
```

3) Clonar repositorio y fijar revision auditada

```bash
git clone https://github.com/dboillos/vox_populi.git
cd vox_populi
git checkout <tag-o-commit-a-auditar>
```

4) Compilar y calcular hash local del WASM

```bash
dfx build
shasum -a 256 .dfx/local/canisters/vox_populi_backend/vox_populi_backend.wasm
shasum -a 256 .dfx/local/canisters/vox_populi_frontend/vox_populi_frontend.wasm
```

5) Comparar hash local vs hash on-chain

- Si el SHA-256 local coincide exactamente con `On-chain module hash`, el binario desplegado corresponde a la revision auditada.
- Si no coincide, el canister en ejecucion no corresponde a esa compilacion local.

### Verificacion complementaria por CLI (opcional)

Cuando se dispone de permisos adecuados de controller:

```bash
dfx canister status <canister-id>
```

Sirve para contrastar metadatos on-chain adicionales, pero la comparacion principal para integridad de codigo es el module hash.
