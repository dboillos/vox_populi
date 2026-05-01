import { Principal } from "@icp-sdk/core/principal"
import { Actor, HttpAgent } from "@icp-sdk/core/agent"
import { createActor as createBackendActor, canisterId as generatedCanisterId } from "declarations/vox_populi_backend"
import { idlFactory as frontendIdlFactory } from "../../../declarations/vox_populi_frontend/vox_populi_frontend.did.js"

export interface AnswerSelection {
  questionId: number
  optionIndex: number
}

export interface VotePayload {
  surveyId: string
  idToken: string
  answers: AnswerSelection[]
  timestamp: number
}

export interface VoteResponse {
  success: boolean
  message: string
  voteId?: string
}

export interface ToolDistributionItem {
  optionIndex: number
  value: number
}

export interface AggregatedResults {
  totalVotes: number
  blockchainTrustPercentage: number
  averageHoursSaved: number
  toolDistribution: ToolDistributionItem[]
  impactRadar: Array<{ axis: string; value: number; fullMark: number }>
  securityMatrix: Array<{ category: string; confia: number; neutral: number; desconfia: number }>
  icpPreference: number
}

export interface RawResponse {
  numero: number
  voterId: string
  timestamp: number
  answers: AnswerSelection[]
}

export interface AuditData {
  canisterId: string
  wasmModuleHash: string
  cyclesBalance: string
  codeVersion: string
}

export interface GoogleIdentityClaims {
  email: string
  emailVerified: boolean
  issuer: string
  audience: string
  expiresAtSec: number
}

export interface GoogleTokenValidation {
  isValid: boolean
  email?: string
  voterId?: string
  reason: string
}

export interface FrontendAssetHashEntry {
  file: string
  hash: string
}

interface BackendVoteResponse {
  success: boolean
  message: string
  voteId: [] | [string]
}

interface BackendActor {
  submitVote: (surveyId: string, idToken: string, answers: Array<{ questionId: bigint; optionIndex: bigint }>, timestamp: bigint) => Promise<BackendVoteResponse>
  getAggregatedResults: (surveyId: string) => Promise<{
    totalVotes: bigint
    blockchainTrustPercentage: bigint
    averageHoursSaved: number
    toolDistribution: Array<{ optionIndex: bigint; value: bigint }>
    impactRadar: Array<{ axis: string; value: number; fullMark: bigint }>
    securityMatrix: Array<{ category: string; confia: bigint; neutral: bigint; desconfia: bigint }>
    icpPreference: bigint
  }>
  getRawResponses: (surveyId: string) => Promise<Array<{
    numero: bigint
    voterId: string
    timestamp: bigint
    answers: Array<{ questionId: bigint; optionIndex: bigint }>
  }>>
  getAuditData: () => Promise<AuditData>
  getModuleHash: (canisterId: Principal) => Promise<string>
  hasUserVoted: (surveyId: string, voterId: string) => Promise<boolean>
  validateInstitutionalEmail: (email: string) => Promise<boolean>
  validateGoogleIdentity: (claims: GoogleIdentityClaims, expectedAudience: string) => Promise<boolean>
  validateGoogleIdToken: (idToken: string, expectedAudience: string) => Promise<{
    isValid: boolean
    email: [] | [string]
    voterId: [] | [string]
    reason: string
  }>
}

interface FrontendAssetEncoding {
  modified: bigint
  sha256: [] | [Uint8Array | number[]]
  length: bigint
  content_encoding: string
}

interface FrontendAssetListEntry {
  key: string
  encodings: FrontendAssetEncoding[]
  content_type: string
}

interface FrontendAssetActor {
  list: (args: { start: [] | [bigint]; length: [] | [bigint] }) => Promise<FrontendAssetListEntry[]>
}

interface FrontendAssetActorOptions {
  host?: string
}

const embeddedBackendCanisterId = (
  import.meta.env.CANISTER_ID_VOX_POPULI_BACKEND ||
  import.meta.env.VITE_BACKEND_CANISTER_ID_IC ||
  ""
).trim()

const generatedBackendCanisterId = (generatedCanisterId || "").trim()

// En producción priorizamos el ID embebido por Vite para evitar arrastrar IDs locales
// inyectados por declaraciones generadas en tiempo de build.
const CANISTER_ID = embeddedBackendCanisterId || generatedBackendCanisterId

function resolveLocalHost() {
  return import.meta.env.VITE_IC_HOST || "http://localhost:4943"
}

function isLocalRuntimeHost(hostname: string): boolean {
  return (
    hostname === "localhost" ||
    hostname === "127.0.0.1" ||
    hostname.endsWith(".localhost")
  )
}

const runtimeHost = typeof window !== "undefined" ? window.location.hostname : ""
const IS_LOCAL_RUNTIME = isLocalRuntimeHost(runtimeHost)

const IC_HOST =
  IS_LOCAL_RUNTIME
    ? resolveLocalHost()
    : "https://ic0.app"

let cachedActorPromise: Promise<BackendActor> | null = null
const frontendAssetActorCache = new Map<string, Promise<FrontendAssetActor>>()

function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

function isTrustError(error: unknown): boolean {
  if (!error) {
    return false
  }

  const message = String(error)
  return message.includes("TrustError") || message.includes("Certificate verification failed")
}

async function withTrustRetry<T>(operation: () => Promise<T>): Promise<T> {
  let lastError: unknown = null

  for (let attempt = 1; attempt <= 3; attempt += 1) {
    try {
      return await operation()
    } catch (error) {
      lastError = error

      // Fuerza re-inicializacion del actor para el siguiente intento.
      cachedActorPromise = null

      if (!isTrustError(error) || attempt === 3) {
        break
      }

      // Espera breve para permitir que finalice fetchRootKey en local.
      await sleep(250 * attempt)
    }
  }

  throw lastError
}

async function getBackendActor(): Promise<BackendActor> {
  if (!CANISTER_ID) {
    throw new Error("No se ha encontrado el CANISTER_ID_VOX_POPULI_BACKEND")
  }

  if (!cachedActorPromise) {
    cachedActorPromise = (async () => {
      const actor = createBackendActor(CANISTER_ID, {
        agentOptions: {
          host: IC_HOST,
          // En local la verificacion criptografica de firmas de query puede fallar
          // en recargas directas por condiciones de replica/subnet keys.
          // Mantener en false solo fuera de la red ic.
          verifyQuerySignatures: !IS_LOCAL_RUNTIME,
        },
      })

      return actor as unknown as BackendActor
    })().catch((error) => {
      // Permite reintentar inicializacion en la siguiente llamada si algo fallo.
      cachedActorPromise = null
      throw error
    })
  }

  return cachedActorPromise
}

async function getFrontendAssetActor(frontendCanisterId: string, options: FrontendAssetActorOptions = {}): Promise<FrontendAssetActor> {
  const normalizedCanisterId = frontendCanisterId.trim()
  if (!normalizedCanisterId) {
    throw new Error("No se ha encontrado el CANISTER_ID_VOX_POPULI_FRONTEND")
  }

  const targetHost = (options.host || IC_HOST).trim()
  const cacheKey = `${normalizedCanisterId}@${targetHost}`

  const cached = frontendAssetActorCache.get(cacheKey)
  if (cached) {
    return cached
  }

  const actorPromise = Promise.resolve(
    (() => {
      const agent = new HttpAgent({
        host: targetHost,
        verifyQuerySignatures: !IS_LOCAL_RUNTIME,
      })

      if (targetHost !== "https://ic0.app") {
        void agent.fetchRootKey().catch(() => {
          // En local puede fallar temporalmente durante arranque de réplica.
        })
      }

      return Actor.createActor(frontendIdlFactory as unknown as any, {
        agent,
        canisterId: normalizedCanisterId,
      }) as unknown as FrontendAssetActor
    })(),
  ).catch((error) => {
    frontendAssetActorCache.delete(cacheKey)
    throw error
  })

  frontendAssetActorCache.set(cacheKey, actorPromise)
  return actorPromise
}

function bytesToHex(bytes: Uint8Array | number[]): string {
  return Array.from(bytes)
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("")
}

function bigintToNumber(value: bigint): number {
  return Number(value)
}

function toBackendAnswers(answers: AnswerSelection[]) {
  return answers.map((answer) => ({
    questionId: BigInt(answer.questionId),
    optionIndex: BigInt(answer.optionIndex),
  }))
}

export function buildAnswerSelections(answers: Record<number, string>, optionSets: Record<number, string[]>): AnswerSelection[] {
  return Object.entries(answers)
    .map(([questionId, selectedOption]) => {
      const numericQuestionId = Number(questionId)
      const options = optionSets[numericQuestionId] ?? []
      const optionIndex = options.findIndex((option) => option === selectedOption)

      if (optionIndex === -1) {
        throw new Error(`No se pudo normalizar la respuesta de la pregunta ${numericQuestionId}`)
      }

      return {
        questionId: numericQuestionId,
        optionIndex,
      }
    })
    .sort((left, right) => left.questionId - right.questionId)
}

export const canisterService = {
  async submitVote(payload: VotePayload): Promise<VoteResponse> {
    const result = await withTrustRetry(async () => {
      const actor = await getBackendActor()
      return actor.submitVote(
        payload.surveyId,
        payload.idToken,
        toBackendAnswers(payload.answers),
        BigInt(payload.timestamp),
      )
    })

    return {
      success: result.success,
      message: result.message,
      voteId: result.voteId[0],
    }
  },

  async getAggregatedResults(surveyId: string): Promise<AggregatedResults> {
    const result = await withTrustRetry(async () => {
      const actor = await getBackendActor()
      return actor.getAggregatedResults(surveyId)
    })

    return {
      totalVotes: bigintToNumber(result.totalVotes),
      blockchainTrustPercentage: bigintToNumber(result.blockchainTrustPercentage),
      averageHoursSaved: result.averageHoursSaved,
      toolDistribution: result.toolDistribution.map((item) => ({
        optionIndex: bigintToNumber(item.optionIndex),
        value: bigintToNumber(item.value),
      })),
      impactRadar: result.impactRadar.map((item) => ({
        axis: item.axis,
        value: item.value,
        fullMark: bigintToNumber(item.fullMark),
      })),
      securityMatrix: result.securityMatrix.map((item) => ({
        category: item.category,
        confia: bigintToNumber(item.confia),
        neutral: bigintToNumber(item.neutral),
        desconfia: bigintToNumber(item.desconfia),
      })),
      icpPreference: bigintToNumber(result.icpPreference),
    }
  },

  async getRawResponses(surveyId: string): Promise<RawResponse[]> {
    const responses = await withTrustRetry(async () => {
      const actor = await getBackendActor()
      return actor.getRawResponses(surveyId)
    })

    return responses.map((response) => ({
      numero: bigintToNumber(response.numero),
      voterId: response.voterId,
      timestamp: bigintToNumber(response.timestamp),
      answers: response.answers.map((answer) => ({
        questionId: bigintToNumber(answer.questionId),
        optionIndex: bigintToNumber(answer.optionIndex),
      })),
    }))
  },

  async getAuditData(): Promise<AuditData> {
    return withTrustRetry(async () => {
      const actor = await getBackendActor()
      return actor.getAuditData()
    })
  },

  async getModuleHash(canisterId: Principal): Promise<string> {
    return withTrustRetry(async () => {
      const actor = await getBackendActor()
      return actor.getModuleHash(canisterId)
    })
  },

  async getFrontendAssetHashes(frontendCanisterId: string, options: FrontendAssetActorOptions = {}): Promise<FrontendAssetHashEntry[]> {
    const actor = await getFrontendAssetActor(frontendCanisterId, options)
    const entries = await actor.list({ start: [], length: [] })

    return entries
      .map((entry) => {
        const identityEncoding = entry.encodings.find((encoding) => encoding.content_encoding === "identity")
        if (!identityEncoding || identityEncoding.sha256.length === 0) {
          return null
        }

        return {
          file: entry.key.startsWith("/") ? entry.key.slice(1) : entry.key,
          hash: bytesToHex(identityEncoding.sha256[0]),
        }
      })
      .filter((entry): entry is FrontendAssetHashEntry => entry !== null)
      .sort((left, right) => left.file.localeCompare(right.file))
  },

  async hasUserVoted(surveyId: string, anonymousId: string): Promise<boolean> {
    return withTrustRetry(async () => {
      const actor = await getBackendActor()
      return actor.hasUserVoted(surveyId, anonymousId)
    })
  },

  async validateInstitutionalEmail(email: string): Promise<boolean> {
    return withTrustRetry(async () => {
      const actor = await getBackendActor()
      return actor.validateInstitutionalEmail(email)
    })
  },

  async validateGoogleIdentity(claims: GoogleIdentityClaims, expectedAudience: string): Promise<boolean> {
    return withTrustRetry(async () => {
      const actor = await getBackendActor()
      return actor.validateGoogleIdentity(claims, expectedAudience)
    })
  },

  async validateGoogleIdToken(idToken: string, expectedAudience: string): Promise<GoogleTokenValidation> {
    const result = await withTrustRetry(async () => {
      const actor = await getBackendActor()
      return actor.validateGoogleIdToken(idToken, expectedAudience)
    })

    return {
      isValid: result.isValid,
      email: result.email[0],
      voterId: result.voterId[0],
      reason: result.reason,
    }
  },
}