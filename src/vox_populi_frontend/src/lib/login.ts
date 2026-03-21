import { canisterService } from "@/lib/canister-service"

// Client ID OAuth de Google para este frontend (configurable por entorno).
const GOOGLE_CLIENT_ID = import.meta.env.VITE_GOOGLE_CLIENT_ID || "765842824522-ar0t6cn0uet2qmf9v0lvp0q2p09t24b2.apps.googleusercontent.com"
const GOOGLE_GSI_SRC = "https://accounts.google.com/gsi/client"
const UOC_DOMAIN = "@uoc.edu"

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
}

declare global {
  interface Window {
    google?: {
      accounts?: {
        id?: {
          initialize: (config: {
            client_id: string
            callback: (response: GoogleCredentialResponse) => void
          }) => void
          prompt: (callback?: (notification: GooglePromptNotification) => void) => void
        }
      }
    }
  }
}

let sdkLoadPromise: Promise<void> | null = null

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
      existing.addEventListener("load", () => resolve(), { once: true })
      existing.addEventListener(
        "error",
        () => reject(new LoginError("sdk_load_failed", "No se pudo cargar Google Identity Services")),
        { once: true },
      )
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

function normalizeEmail(email: string): string {
  return email.trim().toLowerCase()
}

function isAllowedDomain(email: string): boolean {
  return normalizeEmail(email).endsWith(UOC_DOMAIN)
}

function requestGoogleIdToken(): Promise<string> {
  return new Promise((resolve, reject) => {
    const googleId = window.google?.accounts?.id
    if (!googleId) {
      reject(new LoginError("google_auth_failed", "Google Identity no está inicializado"))
      return
    }

    let settled = false
    // Garantiza que resolvemos/rechazamos una sola vez aunque lleguen varios callbacks.
    const finish = (result: () => void) => {
      if (settled) {
        return
      }

      settled = true
      result()
    }

    googleId.initialize({
      client_id: GOOGLE_CLIENT_ID,
      // callback de Google con el id_token JWT (credential).
      callback: (response) => {
        if (!response.credential) {
          finish(() => reject(new LoginError("google_auth_failed", "Google no devolvió id_token")))
          return
        }

        finish(() => resolve(response.credential!))
      },
    })

    googleId.prompt((notification) => {
      // Captura casos típicos de bloqueo por popup/políticas del navegador.
      if (notification.isNotDisplayed?.() || notification.isSkippedMoment?.()) {
        finish(() => reject(new LoginError("google_auth_failed", "No se pudo completar el popup de Google")))
      }
    })

    // Timeout defensivo para no dejar la promesa pendiente indefinidamente.
    setTimeout(() => {
      finish(() => reject(new LoginError("google_auth_failed", "Timeout al esperar respuesta de Google")))
    }, 12000)
  })
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
  await loadGoogleSdk()

  // 1) Obtener id_token firmado por Google en cliente.
  const rawToken = await requestGoogleIdToken()
  const idToken = normalizeIdToken(rawToken)
  if (idToken.split(".").length !== 3) {
    throw new LoginError("google_auth_failed", "Formato de id_token inválido")
  }
  // 2) Delegar validación de seguridad al backend/canister.
  const validation = await canisterService.validateGoogleIdToken(idToken, GOOGLE_CLIENT_ID)

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
