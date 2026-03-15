import { Principal } from "@icp-sdk/core/principal"
import { createActor, canisterId as generatedCanisterId } from "../../../declarations/vox_populi_backend"

export interface AnswerSelection {
  questionId: number
  optionIndex: number
}

export interface VotePayload {
  surveyId: string
  voterId: string
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

interface BackendVoteResponse {
  success: boolean
  message: string
  voteId: [] | [string]
}

interface BackendActor {
  submitVote: (surveyId: string, voterId: string, answers: Array<{ questionId: bigint; optionIndex: bigint }>, timestamp: bigint) => Promise<BackendVoteResponse>
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
}

const CANISTER_ID = generatedCanisterId || import.meta.env.CANISTER_ID_VOX_POPULI_BACKEND || ""

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
      const actor = createActor(CANISTER_ID, {
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

function bigintToNumber(value: bigint): number {
  return Number(value)
}

function toBackendAnswers(answers: AnswerSelection[]) {
  return answers.map((answer) => ({
    questionId: BigInt(answer.questionId),
    optionIndex: BigInt(answer.optionIndex),
  }))
}

export async function deriveAnonymousId(email: string): Promise<string> {
  const normalizedEmail = email.trim().toLowerCase()
  const data = new TextEncoder().encode(normalizedEmail)
  const digest = await crypto.subtle.digest("SHA-256", data)
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("")
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
        payload.voterId,
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

  async hasUserVoted(surveyId: string, anonymousId: string): Promise<boolean> {
    return withTrustRetry(async () => {
      const actor = await getBackendActor()
      return actor.hasUserVoted(surveyId, anonymousId)
    })
  },
}