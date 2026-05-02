import { canisterService } from "@/lib/canister-service"

// Client ID OAuth de Google para este frontend (configurable por entorno).
const GOOGLE_CLIENT_ID = import.meta.env.VITE_GOOGLE_CLIENT_ID || "765842824522-ar0t6cn0uet2qmf9v0lvp0q2p09t24b2.apps.googleusercontent.com"
const GOOGLE_GSI_SRC = "https://accounts.google.com/gsi/client"
const UOC_DOMAIN = "@uoc.edu"
const OIDC_STATE_STORAGE_KEY = "vox_populi_google_oidc_state"

export type LoginErrorCode =
  | "sdk_load_failed"
  | "google_auth_failed"
  | "domain_not_allowed"
  | "backend_validation_failed"

export class LoginError extends Error {
  code: LoginErrorCode

  constructor(code: LoginErrorCode, message: string) {
    super(message)
    this.code = code
    this.name = "LoginError"
  }
}

export type LoginIdentity = {
  email: string
  voterId: string
  idToken: string
}

type GoogleCredentialResponse = {
  credential?: string
}

type GooglePromptNotification = {
  isNotDisplayed?: () => boolean
  isSkippedMoment?: () => boolean
  getNotDisplayedReason?: () => string
  getSkippedReason?: () => string
}

type GooglePromptMode = {
  useFedCm: boolean
}

declare global {
  interface Window {
    google?: {
      accounts?: {
        id?: {
          initialize: (config: {
            client_id: string
            auto_select?: boolean
            itp_support?: boolean
            use_fedcm_for_prompt?: boolean
            nonce?: string
            callback: (response: GoogleCredentialResponse) => void
          }) => void
          disableAutoSelect: () => void
          cancel?: () => void
          prompt: (callback?: (notification: GooglePromptNotification) => void) => void
        }
      }
    }
  }
}

let sdkLoadPromise: Promise<void> | null = null
let googleLoginAttemptCounter = 0

function loadGoogleSdk(): Promise<void> {
  if (typeof window === "undefined") {
    return Promise.reject(new LoginError("sdk_load_failed", "Google SDK no disponible fuera del navegador"))
  }

  if (window.google?.accounts?.id) {
    return Promise.resolve()
  }

  if (sdkLoadPromise) {
    return sdkLoadPromise
  }

  // Evita cargar múltiples veces el SDK si hay varios intentos de login.
  sdkLoadPromise = new Promise((resolve, reject) => {
    const existing = document.querySelector<HTMLScriptElement>(`script[src=\"${GOOGLE_GSI_SRC}\"]`)
    if (existing) {
      if (window.google?.accounts?.id) {
        resolve()
        return
      }

      existing.addEventListener("load", () => resolve(), { once: true })
      existing.addEventListener(
        "error",
        () => reject(new LoginError("sdk_load_failed", "No se pudo cargar Google Identity Services")),
        { once: true },
      )

      const startedAt = Date.now()
      const maxWaitMs = 10000
      const poll = () => {
        if (window.google?.accounts?.id) {
          resolve()
          return
        }

        if (Date.now() - startedAt > maxWaitMs) {
          reject(new LoginError("sdk_load_failed", "Timeout al inicializar Google Identity Services"))
          return
        }

        window.setTimeout(poll, 50)
      }

      poll()
      return
    }

    const script = document.createElement("script")
    script.src = GOOGLE_GSI_SRC
    script.async = true
    script.defer = true
    script.onload = () => resolve()
    script.onerror = () => reject(new LoginError("sdk_load_failed", "No se pudo cargar Google Identity Services"))
    document.head.appendChild(script)
  })

  return sdkLoadPromise
}

export async function preloadGoogleSdk(): Promise<void> {
  try {
    await loadGoogleSdk()
  } catch {
    // No interrumpir la UX por precarga: el flujo principal reintentará y mostrará error si falla.
  }
}

function normalizeEmail(email: string): string {
  return email.trim().toLowerCase()
}

function isIosBrowser(): boolean {
  if (typeof navigator === "undefined") {
    return false
  }

  return /iPad|iPhone|iPod/i.test(navigator.userAgent)
}

function normalizeGooglePromptReason(reason: string): string {
  return reason
    .trim()
    .replace(/suprpressed_by_user/gi, "suppressed_by_user")
}

function isSuppressedByUserError(error: unknown): boolean {
  const message = normalizeGooglePromptReason(String(error ?? ""))
  return message.includes("suppressed_by_user")
}

function generateOpaqueId(prefix: string): string {
  const random = typeof crypto !== "undefined" && "randomUUID" in crypto
    ? crypto.randomUUID()
    : `${Date.now()}-${Math.random().toString(16).slice(2)}`

  return `${prefix}-${random}`
}

function startGoogleOidcRedirect(): never {
  if (typeof window === "undefined") {
    throw new LoginError("google_auth_failed", "No se pudo iniciar redirección OIDC")
  }

  const state = generateOpaqueId("state")
  const nonce = generateOpaqueId("nonce")
  const redirectUri = `${window.location.origin}${window.location.pathname}${window.location.search}`

  sessionStorage.setItem(OIDC_STATE_STORAGE_KEY, state)

  const params = new URLSearchParams({
    client_id: GOOGLE_CLIENT_ID,
    response_type: "id_token",
    scope: "openid email profile",
    redirect_uri: redirectUri,
    state,
    nonce,
    prompt: "select_account",
  })

  window.location.assign(`https://accounts.google.com/o/oauth2/v2/auth?${params.toString()}`)
  throw new LoginError("google_auth_failed", "Redirigiendo a Google...")
}

function consumeOidcRedirectIdToken(): string | null {
  if (typeof window === "undefined") {
    return null
  }

  const hash = window.location.hash
  if (!hash || !hash.includes("id_token=")) {
    return null
  }

  const params = new URLSearchParams(hash.startsWith("#") ? hash.slice(1) : hash)
  const idToken = params.get("id_token")
  const state = params.get("state")
  const storedState = sessionStorage.getItem(OIDC_STATE_STORAGE_KEY)

  if (!idToken || !state || !storedState || state !== storedState) {
    return null
  }

  sessionStorage.removeItem(OIDC_STATE_STORAGE_KEY)
  window.history.replaceState({}, document.title, `${window.location.pathname}${window.location.search}`)
  return idToken
}

function resetGooglePromptState() {
  const googleId = window.google?.accounts?.id
  if (!googleId) {
    return
  }

  googleId.cancel?.()
  googleId.disableAutoSelect()
}

function nextGoogleLoginAttemptId(): number {
  googleLoginAttemptCounter += 1
  return googleLoginAttemptCounter
}

function buildGoogleNonce(attemptId: number): string {
  return `vox-login-${Date.now()}-${attemptId}`
}

function isAllowedDomain(email: string): boolean {
  return normalizeEmail(email).endsWith(UOC_DOMAIN)
}

function formatBackendLoginError(error: unknown): LoginError {
  const message = String(error ?? "")
  const isLocalRuntime = import.meta.env.DFX_NETWORK === "local"
  const localHost = import.meta.env.VITE_IC_HOST || "http://localhost:4943"

  if (
    message.includes("Failed to fetch") ||
    message.includes("fetch failed") ||
    message.includes("NetworkError") ||
    message.includes("canister_not_found") ||
    message.includes("replica") ||
    message.includes("Connection refused")
  ) {
    if (isLocalRuntime) {
      return new LoginError(
        "backend_validation_failed",
        `No se pudo contactar con el backend local en ${localHost}. Inicia la réplica y despliega los canisters con dfx/icp antes de probar el login.`,
      )
    }

    return new LoginError(
      "backend_validation_failed",
      "No se pudo contactar con el backend de autenticación. Inténtalo de nuevo en unos segundos.",
    )
  }

  return new LoginError("backend_validation_failed", message || "Falló la validación del login en backend")
}

function requestGoogleIdTokenWithMode(mode: GooglePromptMode, attemptId: number): Promise<string> {
  return new Promise((resolve, reject) => {
    const googleId = window.google?.accounts?.id
    if (!googleId) {
      reject(new LoginError("google_auth_failed", "Google Identity no está inicializado"))
      return
    }

    resetGooglePromptState()

    let settled = false
    let timeoutId: number | null = null
    // Garantiza que resolvemos/rechazamos una sola vez aunque lleguen varios callbacks.
    const finish = (result: () => void) => {
      if (settled) {
        return
      }

      settled = true
      if (timeoutId !== null) {
        window.clearTimeout(timeoutId)
      }
      result()
    }

    googleId.initialize({
      client_id: GOOGLE_CLIENT_ID,
      auto_select: false,
      itp_support: true,
      use_fedcm_for_prompt: mode.useFedCm,
      nonce: buildGoogleNonce(attemptId),
      // callback de Google con el id_token JWT (credential).
      callback: (response) => {
        if (!response.credential) {
          finish(() => reject(new LoginError("google_auth_failed", "Google no devolvió id_token")))
          return
        }

        finish(() => resolve(response.credential!))
      },
    })

    // Delay breve para dejar que cancel()/disableAutoSelect limpien el estado previo.
    window.setTimeout(() => {
      googleId.prompt((notification) => {
        // Captura casos típicos de bloqueo por popup/políticas del navegador.
        if (notification.isNotDisplayed?.() || notification.isSkippedMoment?.()) {
          const rawReason = notification.getNotDisplayedReason?.() || notification.getSkippedReason?.() || "motivo desconocido"
          const reason = normalizeGooglePromptReason(rawReason)
          resetGooglePromptState()
          finish(() => reject(new LoginError("google_auth_failed", `No se pudo abrir el selector de Google (${reason})`)))
        }
      })
    }, 60)

    // Timeout defensivo para no dejar la promesa pendiente indefinidamente.
    timeoutId = window.setTimeout(() => {
      resetGooglePromptState()
      finish(() => reject(new LoginError("google_auth_failed", "Timeout al esperar respuesta de Google")))
    }, 30000)
  })
}

async function requestGoogleIdToken(): Promise<string> {
  // En iOS, FedCM todavía da más falsos positivos de `suppressed_by_user`.
  // Iniciamos sin FedCM y, si hace falta, reintentamos con el modo alternativo.
  const firstMode: GooglePromptMode = { useFedCm: !isIosBrowser() }
  const fallbackMode: GooglePromptMode = { useFedCm: !firstMode.useFedCm }

  const attemptId = nextGoogleLoginAttemptId()

  try {
    return await requestGoogleIdTokenWithMode(firstMode, attemptId)
  } catch (error) {
    const message = error instanceof LoginError ? error.message : String(error ?? "")
    const reason = normalizeGooglePromptReason(message)

    if (!reason.includes("suppressed_by_user")) {
      throw error
    }

    try {
      return await requestGoogleIdTokenWithMode(fallbackMode, attemptId + 1)
    } catch (fallbackError) {
      if (isSuppressedByUserError(fallbackError)) {
        startGoogleOidcRedirect()
      }

      throw fallbackError
    }
  }
}

function normalizeIdToken(rawToken: string): string {
  const trimmed = rawToken.trim()

  if (trimmed.split(".").length === 3) {
    return trimmed
  }

  try {
    const parsed = JSON.parse(trimmed) as Record<string, unknown>

    if (typeof parsed.id_token === "string" && parsed.id_token.split(".").length === 3) {
      return parsed.id_token
    }

    if (typeof parsed.token === "string") {
      const nested = parsed.token.trim()
      if (nested.split(".").length === 3) {
        return nested
      }

      if (nested.startsWith("{")) {
        const nestedParsed = JSON.parse(nested) as Record<string, unknown>
        if (typeof nestedParsed.id_token === "string" && nestedParsed.id_token.split(".").length === 3) {
          return nestedParsed.id_token
        }
      }
    }
  } catch {
    // Si no es JSON válido, devolvemos el token tal cual y la validación siguiente lo rechazará.
  }

  return trimmed
}

export async function loginWithGoogle(): Promise<LoginIdentity> {
  // Este método SOLO autentica identidad institucional.
  // No escribe votos ni genera aún el identificador de voto.
  const redirectedIdToken = consumeOidcRedirectIdToken()

  if (!redirectedIdToken) {
    await loadGoogleSdk()
  }

  // 1) Obtener id_token firmado por Google en cliente.
  const rawToken = redirectedIdToken ?? await requestGoogleIdToken()
  const idToken = normalizeIdToken(rawToken)
  if (idToken.split(".").length !== 3) {
    throw new LoginError("google_auth_failed", "Formato de id_token inválido")
  }
  // 2) Delegar validación de seguridad al backend/canister.
  let validation
  try {
    validation = await canisterService.validateGoogleIdToken(idToken, GOOGLE_CLIENT_ID)
  } catch (error) {
    throw formatBackendLoginError(error)
  }

  if (!validation.isValid || !validation.email || !validation.voterId) {
    if (validation.reason.includes("dominio")) {
      throw new LoginError("domain_not_allowed", validation.reason)
    }

    throw new LoginError("backend_validation_failed", validation.reason)
  }

  const normalizedEmail = normalizeEmail(validation.email)
  // Doble check defensivo en frontend por UX; la validación fuerte ya ocurre en backend.
  if (!isAllowedDomain(normalizedEmail)) {
    throw new LoginError("domain_not_allowed", "El dominio del correo no pertenece a UOC")
  }

  // Modelo de anonimato :
  // - Aquí devolvemos email validado para mantener sesión de usuario.
  // - En el momento de votar, se usa el voterId pseudónimo emitido por backend
  //   tras validar el id_token de Google.
  // - El backend/blockchain persiste voterId, no el email.
  // - El voterId publicado no deriva del email en frontend.

  return {
    email: normalizedEmail,
    voterId: validation.voterId,
    idToken,
  }
}
