// ============================================================================
// CONFIGURACIÓN DE ENCUESTAS - PILOTO UOC
// ============================================================================
// 
// Este archivo contiene la CONFIGURACIÓN de encuestas y preguntas:
// - Qué encuestas existen y su estado
// - Lógica de saltos condicionales entre preguntas
//
// Los TEXTOS traducidos de encuestas están en /lib/survey-translations.ts
// Los DATOS del canister están en /lib/survey-data.ts
// Las funciones que combinan todo están en /lib/survey-helpers.ts
//
// ============================================================================

// ============================================================================
// CONFIGURACIÓN DE ENCUESTAS DISPONIBLES
// ============================================================================

export interface SurveyConfig {
  id: string
  status: "active" | "upcoming" | "closed"
  votes?: number
  deadline?: string
}

export const surveysConfig: SurveyConfig[] = [
  { 
    id: "ai-uoc-2024", 
    status: "active", 
    votes: 1247, 
    deadline: "15 Abril 2024" 
  },
  { 
    id: "sostenibilidad", 
    status: "upcoming" 
  },
  { 
    id: "transporte", 
    status: "upcoming" 
  },
  { 
    id: "presupuestos", 
    status: "upcoming" 
  }
]

// ============================================================================
// CONFIGURACIÓN DE PREGUNTAS - ENCUESTA "USO DE LA IA EN LA UOC"
// ============================================================================
// 
// Cada pregunta tiene:
// - id: Número de pregunta (1-12)
// - optionsCount: Cuántas opciones tiene la pregunta
// - skipTo: (opcional) Si se activa el salto, ir a esta pregunta
// - skipTriggerIndex: (opcional) Índice de la opción que activa el salto (0-based)
//
// EJEMPLO DE SALTO CONDICIONAL:
// La pregunta 1 tiene skipTo: 8 y skipTriggerIndex: 4
// Esto significa: si el usuario selecciona la opción índice 4 ("Ninguna"),
// el sistema saltará directamente a la pregunta 8.
//
// ============================================================================

export interface QuestionConfig {
  id: number
  optionsCount: number
  skipTo?: number           // ID de la pregunta destino del salto
  skipTriggerIndex?: number // Índice (0-based) de la opción que activa el salto
}

// Configuración de las 12 preguntas
export const questionsConfig: QuestionConfig[] = [
  // P1: ¿Qué herramienta de IA generativa utilizas?
  // Opciones: ChatGPT, Gemini, Claude, Copilot, Ninguna, Otra
  // Si selecciona "Ninguna" (índice 4), salta a P8
  { 
    id: 1, 
    optionsCount: 6,
    skipTo: 8, 
    skipTriggerIndex: 4 
  },
  
  // P2: ¿En qué fase de tus actividades académicas recurres a la IA?
  { id: 2, optionsCount: 5 },
  
  // P3: ¿Cuántas horas semanales ahorras gracias a la IA?
  { id: 3, optionsCount: 4 },
  
  // P4: Del 1 al 5, ¿cuánto ha mejorado la calidad de tus entregas?
  { id: 4, optionsCount: 5 },
  
  // P5: ¿Qué uso consideras más ético para un estudiante?
  { id: 5, optionsCount: 4 },
  
  // P6: ¿Sientes que el uso de IA reduce tu esfuerzo de aprendizaje?
  { id: 6, optionsCount: 3 },
  
  // P7: ¿Cómo describirías la actitud de tus profesores?
  { id: 7, optionsCount: 4 },
  
  // P8: ¿Te genera desconfianza identificarte con Google OIDC?
  { id: 8, optionsCount: 3 },
  
  // P9: ¿Te sientes más seguro con el ID anónimo en ICP?
  { id: 9, optionsCount: 3 },
  
  // P10: ¿Confías en la inmutabilidad del voto en blockchain?
  { id: 10, optionsCount: 3 },
  
  // P11: ¿Consideras que blockchain es necesaria para transparencia?
  { id: 11, optionsCount: 3 },
  
  // P12: ¿Preferirías ICP antes que Google Forms?
  { id: 12, optionsCount: 3 }
]


