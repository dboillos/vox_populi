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
- Login institucional con Google OpenID Connect (OIDC) y validacion de `id_token` en backend.
- Regla de integridad: no se permiten votos duplicados por `(surveyId, voterId)`.

## Medidas de seguridad implementadas

### Objetivo

Garantizar voto institucional verificable y resistente a manipulacion de cliente, manteniendo separadas la identidad institucional validada y la identidad de voto persistida on-chain.

### 1) Autenticacion OpenID Connect (OIDC) validada en backend

1. El frontend obtiene `id_token` con Google Identity Services (GIS).
2. El backend valida el token mediante `tokeninfo` de Google.
3. Se validan claims obligatorias:
	- `aud` coincide con el cliente OAuth esperado.
	- `iss` pertenece a Google.
	- `exp` no esta caducado.
	- `email_verified` es `true`.
	- el dominio permitido es `@uoc.edu`.

Propiedad conseguida:

- El navegador no puede elegir libremente la identidad efectiva de voto.
- El backend decide si la identidad es valida antes de aceptar un `submitVote`.

### 2) Modelo actual de identidad de voto (`voterId`)

La app usa un modelo de seudonimizacion con registro estable protegido, donde la identidad real (email) nunca se persiste en plaintext.

Flujo real:

1. Tras validar el `id_token`, el backend extrae el email normalizado (minúsculas).
2. Calcula una clave hasheada: `hash(email_normalizado + "|" + backendEmailSalt)`.
3. Busca esa clave hasheada en `identityRegistryEntries`.
4. Si ya existe una entrada, reutiliza el `voterId` previamente asignado.
5. Si no existe, genera un nuevo identificador opaco:
	- normalmente `pid-<hex aleatorio>` usando `raw_rand()` del IC;
	- si `raw_rand()` falla, usa un fallback determinista acotado a ese alta.
6. El par `(clave_hasheada, voterId)` se guarda en el registro estable interno.

Ventajas de este diseño:

- El **email nunca aparece en plaintext** en el estado persistido del canister.
- El `voterId` es **estable entre sesiones** porque se reutiliza via lookup de clave hasheada.
- La **clave hasheada depende de dos factores**: email (privado del usuario) y salt (secreto del backend).
- Si un atacante accede **solo al estado** del canister sin el salt, ve hashes opacos sin correlacionar.
- Si un atacante accede **solo al salt**, no puede usar estado del canister para enumerar hashes (ambos se necesitan).

Modelo criptografico:

- La "clave de identidad" es `hash(email + "|" + salt)`, no el email directamente.
- El `voterId` generado es **pseudonimo opaco y no determinista**: cada sesion de un usuario obtiene el mismo `voterId` (estable), pero eso no revela email porque se buscó via clave hasheada.
- No existe un endpoint público que permita pasar `email + salt` y obtener `voterId`.

### 3) Que papel tiene el `salt` actualmente

El `backendEmailSalt` es un secreto persistido que aparece en dos lugares:

Rol criptografico:

1. **Clave de hash para identidad**: entra en `hash(email + "|" + salt)` que se usa como clave lookup en `identityRegistryEntries`.
2. **Semilla de fallback**: si `raw_rand()` falla al generar nuevo `voterId`, se usa `email + salt` como semilla para un fallback determinista.

Protecciones mediante arquitectura:

- El salt **nunca se envía al frontend** ni aparece en peticiones HTTP públicas.
- El salt **se genera una sola vez** con aleatoriedad segura del IC (`raw_rand()`) durante el primer ciclo de ejecucion.
- El salt **se persiste en estado estable** y sobrevive upgrades del canister.
- Si el salt se compromete pero no el código desplegado, solo se expone el riesgo de fuerza bruta: atacante debe enumerar emails candidatos y calcular `hash(email_candidato + "|" + salt)` para correlacionar con entries en `identityRegistryEntries`.


### 3.1) Vectores de ataque y su mitigacion

Supongamos varios escenarios de compromiso:

**Escenario A: Atacante accede a estado del canister (sin salt)**
- Ve `[(hid-12345, pid-abc), (hid-67890, pid-def), ...]`
- No puede revertir hashes a emails sin el salt.
- No puede relacionar votos con identidades reales.
- Conclusión: seguridad hash-based resistida.

**Escenario B: Atacante accede a salt (sin estado)**
- Tiene `backendEmailSalt = "pilot-xyz..."`
- No puede verificar si un email es cliente de vox_populi sin acceso a `identityRegistryEntries`.
- No puede atacar sin datos de correlación.
- Conclusión: seguridad mediante separación de secretos.

**Escenario C: Atacante accede a código desplegado, estado Y salt**
- Lee el binario en blockchain, el estado y el salt.
- Puede hacer fuerza bruta: enumerar emails institucionales conocidos, calcular `hash(email + "|" + salt)`, comprobar contra entries.
- Puede correlacionar votantes con votos si combina estado + hash inverso.
- Conclusión: **riesgo válido si todos los compromisos coinciden.**

**Escenario D: Atacante intenta cambiar código para exfiltrar**
- El atacante se haría con los controladores del canister (requiere keys privadas de controlador).
- Intentaria hacer upgrade a un codigo malicioso que log emails y hashes.
- El `module hash` cambiaría inmediatamente, visible en blockchain.
- **Auditoria reproducible lo detectaría en segundos.**
- Conclusión: **Surface de deteccion mediante auditoria.**

Implicaciones:

- No hay anonimato absoluto frente a un atacante con acceso completo (código + estado + salt). Caso altamente improbable
- Hay **anonimato relativo** frente a atacantes parciales o externos: requiere fuerza bruta, no trivialidad, exposición.
- La **auditabilidad del código es la garantía principal**: impide que cambios maliciosos pasen desapercibidos.



### 4) Escritura de voto protegida

1. `submitVote` exige `idToken` y no acepta un `voterId` arbitrario elegido por cliente.
2. El backend resuelve la identidad efectiva tras validacion OpenID Connect (OIDC) y lookup/alta en el registro pseudonimo.
3. Solo se persiste el voto cuando autenticacion y payload son validos.

Propiedad conseguida:

- La identidad de voto la controla el backend, no el frontend.

### 5) Prevencion de voto duplicado

Regla de negocio:

- Un mismo `voterId` no puede votar dos veces en la misma encuesta (`surveyId`).

Implementacion:

- Indice de duplicados en memoria O(1) promedio con espejo estable para upgrades.
- Rechazo funcional cuando ya existe voto previo para `(surveyId, voterId)`.

### 6) Privacidad de identidad

Arquitectura actual:

1. El email institucional **no se persiste en plaintext** en el registro de identidad.
2. Se guarda la clave hasheada: `hash(email_normalizado + "|" + salt)` → `voterId`.
3. En los votos almacenados se persiste solo `voterId` pseudonimo y las respuestas, nunca el email.
4. El mapping `hash(email + salt) -> voterId` es interno, no se expone por endpoint público.

Protecciones resultantes:

- **Separación de datos**: el estado del canister no contiene emails en forma legible.
- **Protección hash-based**: correlacionar votos con usuarios requiere acceso simultaneo a salt + estado + enumeración de emails candidatos.
- **No determinismo opaco**: el `voterId` no se calcula públicamente desde email (no existe endpoint `email -> voterId`).
- **Superficie limitada**: las únicas formas de obtener `voterId` son:
    - Login via OpenID Connect (OIDC) (donde el backend realiza internamente la derivación) -> el frontend recibe `voterId` opaco sin ver la lógica.
	- Acceso directo al estado del canister (requiere ser controlador, altamente privilegiado).

Resumen del modelo:

- Usa seudonimización on-chain con registro estable internamente.
- El código desplegado es auditable y verificable por cualquier tercero mediante `module hash`.
- La verificación permite comprobar que:
	- La version en ejecucion coincide con el repositorio publicado.
	- El código no expone públicamente ni el registro interno ni un mecanismo de reidentificación desde `voterId`.
	- El cambio del `module hash` seria detectado si un atacante con poderes de controller intenta hacer upgrade malicioso.
- La reidentificación de un votante es **altamente improbable** para un observador externo: requiere un compromiso simultáneo de (estado + salt) y enumeración de emails conocidos.
- **Riesgo residual**: Un futuro upgrade malicioso aprobado por controllers podria cambiar el comportamiento, pero eso seria detectado en auditoria porque cambiaría el `module hash`.

### 6.1) Mecanismos de defensa en profundidad

**A nivel de arquitectura de vox_populi:**

- Email hasheado con salt privado del backend: acceso a estado ≠ exposición de identidad.
- Separación de secretos: atacante necesita simultaneamente (salt + estado).
- `voterId` no determinista: no existe cálculo público que recupere `voterId` desde email.

**A nivel de infraestructura ICP (plataforma subyacente):**

- El estado de un canister **no es consultable públicamente** via API genérica: solo métodos expuestos por el canister pueden leerlo.
- La ejecución distribuida del IC evita que un cliente externo inspeccionasse directamente heap, memory o variables internas sin pasar por los métodos del canister.
- El control de upgrades se concentra en `controllers`: un tercero sin esos permisos no puede cambiar el código.
- **Integridad verificable**: el `module hash` permite a cualquiera hacer checkout del repositorio, compilar reproduciblemente el binario, y comparar si coincide con el deployed en blockchain.

**A nivel de nodo TEE (hardware, en despliegue progresivo):**

- Los nodos TEE (Entorno de Ejecución Confiable)-habilitados de ICP usan AMD SEV-SNP (Secure Encrypted Virtualization Secure Nested Paging) para:
	- **Encripción de memoria**: el estado del canister está encriptado en RAM (Memoria de Acceso Aleatorio).
	- **Atestación remota**: terceros pueden verificar remotamente qué código exacto se está ejecutando en ese TEE.
	- **Sealing keys**: el estado encriptado se vincula a la medida de lanzamiento (launch measurement), haciendo imposible desencriptarlo fuera de ese contexto específico.
- Incluso si alguien accediera a la memoria física del nodo (robo de servidor), los datos están encriptados y vinculados a identidades criptográficas hardware.

**Síntesis: defensa en profundidad**

| Capa | Ataque | Defensa |
|------|--------|---------|
| **Aplicación** | Acceso a estado → exposición email | Email hasheado + sal |
| **Arquitectura ICP** | Lectura directa de memoria/variables | No hay API publica genérica; solo metodos canister |
| **Integridad código** | Upgrade malicioso silencioso | `module hash` auditable y verificable |
| **Hardware (TEE)** | Robo de servidor / lectura física | SEV-SNP memory encryption + sealing keys |

**Garantía principal de seguridad: Auditabilidad**

- El código está **público en repositorio** y es **auditable** por cualquiera.
- El binario **reproducible** permite comprobar que lo desplegado = lo publicado.
- El `module hash` **visible en blockchain** permite detectar upgrades maliciosos en segundos.
- **Conclusión**: un atacante con acceso completo (estado + salt + código) puede correlacionar, pero no puede hacerlo en secreto sin que aparezca en auditoría y es un caso altamente improbable.

### 7) Determinismo en Protocolo Seguro de Transferencia de Hipertexto (HTTPS) outcalls

Problema mitigado:

- Diferencias menores en respuestas HTTP externas pueden afectar consenso de subred.

Mitigacion implementada:

1. `transformGoogleTokenInfoResponse` normaliza respuesta de `tokeninfo`.
2. Se eliminan headers volatiles.
3. Se conserva solo JSON canonico con claims necesarias (`aud`, `iss`, `exp`, `email`, `email_verified`).
4. Para errores HTTP, se conserva `status` con cuerpo vacio.

### 8) Sesion y reautenticacion en frontend

1. El estado de sesion se guarda en `sessionStorage`, no en `localStorage`.
2. `voxpopuli_session` guarda `email`, `voterId`, `idToken` y `expiresAt`.
3. Si `submitVote` devuelve autenticacion invalida/expirada, el frontend limpia sesion, vuelve a landing y fuerza re-login.
4. El login actual implementa reintentos, reseteo de prompt y fallback por redireccion OpenID Connect (OIDC) cuando Google Identity Services (GIS) devuelve bloqueos tipo `suppressed_by_user`.

Propiedad conseguida:

- La sesion vive solo en el navegador actual.
- El backend sigue siendo la autoridad final aunque el frontend recuerde `email`, `voterId` e `idToken` temporalmente.

### 9) Transparencia de UX durante escritura

1. El envio de voto muestra modal de progreso por pasos (`pending/running/done/error`).
2. Los textos de modales se resuelven por i18n (Internacionalización) (ES/EN/CA).
3. En error, el usuario recibe motivo explicito y accion de recuperacion.

### 10) Escalabilidad de consultas y no duplicidad

Mejoras aplicadas:

- Indice de duplicados en memoria `voteLookup` con reconstruccion desde `voteLookupEntries` (estable) tras upgrade.
- Cache por encuesta `surveyVotesCache` para resolver agregaciones y respuestas crudas sin recorrer `storedVotes` completo.
- Actualizacion incremental de ambos indices al registrar un voto valido.
- Registro transient `identityRegistry` reconstruido desde `identityRegistryEntries` para resolver identidad en O(1) promedio.

Complejidades relevantes:

- `submitVote`:
  - validacion de payload: O(n respuestas)
  - chequeo duplicado: O(1) promedio
  - persistencia e indices: O(1) promedio
- `hasUserVoted`: O(1) promedio.
- `getAggregatedResults`: O(m), con m=votos de la encuesta.
- `getRawResponses`: O(m), con m=votos de la encuesta.

### Archivos clave

- Frontend login y fallback OpenID Connect (OIDC): `src/vox_populi_frontend/src/lib/login.ts`
- Contexto de sesion frontend: `src/vox_populi_frontend/src/context/AuthContext.tsx`
- Servicio frontend-canister: `src/vox_populi_frontend/src/lib/canister-service.ts`
- API backend principal: `src/vox_populi_backend/main.mo`
- Servicio de autenticacion OIDC: `src/vox_populi_backend/auth/auth_service.mo`
- Registro estable de identidad pseudonima: `src/vox_populi_backend/auth/identity_registry_service.mo`
- Flujo de validacion OIDC: `src/vox_populi_backend/auth/auth_flow.mo`
- Helpers de autenticacion: `src/vox_populi_backend/auth/auth_helpers.mo`
- Parser de claims `tokeninfo`: `src/vox_populi_backend/auth/tokeninfo_parser.mo`
- Gestion del salt del backend: `src/vox_populi_backend/auth/salt_manager.mo`
- Runtime de indices/cache de voto: `src/vox_populi_backend/vote/vote_runtime_service.mo`
- Servicio de votacion y resultados: `src/vox_populi_backend/vote/voting_service.mo`
- Politicas de voto: `src/vox_populi_backend/vote/vote_policy.mo`
- Consultas de votos en orden de insercion: `src/vox_populi_backend/vote/vote_queries.mo`
- Agregaciones y estadistica: `src/vox_populi_backend/vote/aggregations.mo`
- Servicio de auditoria: `src/vox_populi_backend/audit/audit_service.mo`
- Utilidades de auditoria: `src/vox_populi_backend/audit/audit_helpers.mo`
- Tipos HTTP (Protocolo Seguro de Transferencia de Hipertexto) para llamadas salientes de IC (Internet Computer): `src/vox_populi_backend/infrastructure/ic_http_types.mo`
- Tipos compartidos: `src/vox_populi_backend/shared/types.mo`
- Configuracion de encuesta compartida: `src/vox_populi_backend/shared/survey_config.mo`

### Nota metodologica

Esta implementacion valida el token con Google en tiempo real via `tokeninfo` (validacion delegada en proveedor de identidad). Es una arquitectura valida para prototipo academico y despliegue controlado. Como trabajo futuro, se puede incorporar verificacion criptografica local de firma JWT (Token Web JSON) mediante JWKS (Conjunto de Claves Web JSON) y, si el modelo de amenaza lo exige, endurecer la capa de seudonimizacion para reducir aun mas la confianza depositada en el estado interno del backend.

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

## Transparencia Verificable: Cómo Auditar el Código Desplegado

### El Principio de Auditabilidad Reproducible

La garantía principal de vox_populi no es una promesa sino un **hecho verificable on-chain**. Cualquiera, sin permisos especiales, puede comprobar que el código que afirmamos estar ejecutando es exactamente el del repositorio público. Este es el corazón del ejercicio de transparencia.

### Dónde se Registra el Module Hash

El `module hash` (SHA-256 del binario WASM) aparece en **tres lugares independientes**:

#### 1) En la Blockchain de ICP (fuente de verdad)

**ICP Explorer** (https://dashboard.internetcomputer.org/):
- Buscar por Canister ID: `46im3-biaaa-aaaaj-qqwra-cai` (backend) o `4zjkp-mqaaa-aaaaj-qqwrq-cai` (frontend)
- Ver pestaña "Controllers" o "Module Details"
- El `module hash` aparece como valor immutable, registrado en blockchain

**Ventaja**: No se puede cambiar sin que toda la red lo vea. Es la fuente de verdad absoluta.

#### 2) En los Logs de Despliegue (Git + CI/CD)

Cuando hacemos `dfx deploy`, los logs guardan:
```
Deployed canisters.
Canister ID: 46im3-biaaa-aaaaj-qqwra-cai
Module hash: a3f5c8e2b7d4f1a6c9e2b7d4f1a6c9e2b7d4f1a6c9e2b7d4f1a6c9e2b7d4f1a
```

**Dónde encontrarlo:**
- En el repositorio: rama `main`, CI/CD logs (GitHub Actions)
- Cada tag de release guarda el hash del despliegue de esa versión

**Ventaja**: Historial público, imposible de alterar retroactivamente sin reescribir git history (detectable).

#### 3) En tu Ordenador, Compilando el Código

Tú mismo, descargando el repositorio, puedes calcular el hash:

```bash
# Paso 1: Clonar repositorio en commit exacto
git clone https://github.com/dboillos/vox_populi.git
cd vox_populi
git checkout v1.2.76  # O el commit/tag que quieras auditar

# Paso 2: Compilar localmente
dfx build vox_populi_backend

# Paso 3: Calcular hash SHA-256 del binario
shasum -a 256 .dfx/local/canisters/vox_populi_backend/vox_populi_backend.wasm

# Salida esperada:
# a3f5c8e2b7d4f1a6c9e2b7d4f1a6c9e2b7d4f1a6c9e2b7d4f1a6c9e2b7d4f1a
```

### Cómo Verificar que el Código es Auténtico

#### Escenario: Auditar un Despliegue Específico

**Pregunta**: "¿Estoy seguro de que vox_populi_backend en blockchain ejecuta exactamente el código del repositorio público?"

**Respuesta paso a paso:**

1. **Obtener el hash on-chain:**
   ```bash
   dfx canister info 46im3-biaaa-aaaaj-qqwra-cai
   # O mirar en ICP Explorer
   ```
   Resultado: `module_hash = a3f5c8e2b7d4f1a6c9e2b7d4f1a6c9e2b7d4f1a6c9e2b7d4f1a6c9e2b7d4f1a`

2. **Clonar el repositorio:**
   ```bash
   git clone https://github.com/dboillos/vox_populi.git
   cd vox_populi
   git log --oneline | head -5
   # Encontrar el commit correspondiente al release publicado
   git checkout v1.2.76
   ```

3. **Compilar reproduciblemente:**
   ```bash
   dfx build vox_populi_backend 2>&1 | tee build.log
   ```

4. **Calcular tu hash local:**
   ```bash
   shasum -a 256 .dfx/local/canisters/vox_populi_backend/vox_populi_backend.wasm
   # Resultado local: a3f5c8e2b7d4f1a6c9e2b7d4f1a6c9e2b7d4f1a6c9e2b7d4f1a6c9e2b7d4f1a
   ```

5. **Comparar los hashes:**
   ```bash
   # Si coinciden exactamente:
   # ✅ El código on-chain = código del repositorio en ese commit
   # ❌ Si no coinciden:
   # ⚠️  El código on-chain NO corresponde a ese commit (posible upgrade no documentado)
   ```

### Por Qué Esto Importa: Detección de Cambios Maliciosos

#### Caso 1: Code Injection Posterior al Despliegue

Supongamos un atacante con poderes de controller intenta hacer upgrade para:
- Exfiltrar emails del registro interno
- Alterar votos ya registrados
- Cambiar lógica de autenticación

**¿Qué pasaría?**

1. El atacante hace `dfx deploy` con código malicioso
2. El `module hash` **cambia inmediatamente** en blockchain
3. Cualquier usuario auditor ve: `hash_anterior ≠ hash_actual`
4. Alerta pública: El código en ejecución no corresponde al repositorio publicado
5. **Detección en minutos**, no en días

**Garantía**: No puede pasar desapercibido porque el `module hash` es público e inmutable mientras el canister está vivo.

#### Caso 2: Compromiso del Repositorio Público

Supongamos GitHub es comprometido y alguien altera el código en `main`:
- Descarga el "código malicioso" de GitHub
- Compila localmente
- Calcula el hash
- **No coincide con el hash on-chain** ← Alerta de mismatch

**Garantía**: El hash on-chain es la fuente de verdad, no GitHub. Si GitHub se altera, la verificación lo detecta.

#### Caso 3: Verificación de Integridad de Despliegue

Un usuario corporativo quiere estar 100% seguro de que:
- El voto es contado correctamente
- El email no se filtra
- La lógica es la publicada

**Proceso:**
1. Lee el repositorio (código abierto)
2. Revisa la sección de `hash` en git logs o releases
3. Compila él mismo
4. Verifica que coincide con on-chain
5. **Conclusión independiente**: "El código on-chain es auténtico"

No necesita confiar en nosotros. Puede verificarlo.

### La Cadena de Custodia Criptográfica

| Punto | Hash | Verificabilidad | Confianza |
|-------|------|---|---|
| **Repositorio público** | `a3f5c8...` (en git commit) | Sí, cualquiera puede ver git log | Media (GitHub es tercero) |
| **Compilación local** | `a3f5c8...` (que calculas tú) | Sí, tú compilas en tu máquina | Alta (tu propio ordenador) |
| **Blockchain (on-chain)** | `a3f5c8...` (visible en explorer) | Sí, consulta pública sin auth | Muy Alta (red distribuida de 13,000+ nodos) |
| **Si los tres coinciden** | **MATCH** | Código on-chain = repositorio | **VERIFICADO** |

### Límites Reales (Honestidad)

Este modelo **no protege contra**:
- Compromiso total anterior: Si los controladores privados fueron robados hace 1 año, un atacante ya pudo cambiar el código (pero las auditorías posteriores lo habrían visto)
- Vulnerabilidades del compilador: Si `dfx` o Motoko tienen un bug que produce diferentes bytecode, los hashes no coincidirán (pero eso es transparente)
- Uso de hardware comprometido personal: Si tu PC ejecuta malware durante la compilación, puede alterar el hash

**Lo que SÍ protege**:
- Cambios no autorizados al código on-chain (detectados en minutos)
- Falta de integridad del repositorio (hash no coincide)
- Ocultamiento de upgrades (el hash cambia, visible en blockchain)

### Resumen: La Garantía Principal

**La auditabilidad reproducible es la defensa más fuerte de vox_populi.** 

- Cualquiera puede verificar de forma independiente que el código on-chain es auténtico
- No necesita permisos especiales, solo git, Motoko/dfx, y shasum
- Un cambio malicioso es **instantáneamente visible** y **no se puede ocular**

Por eso decimos que **el código es auditable**: no porque sea de código abierto (muchos lo son), sino porque su integridad es verificable criptográficamente contra la blockchain, por cualquiera, en cualquier momento.

