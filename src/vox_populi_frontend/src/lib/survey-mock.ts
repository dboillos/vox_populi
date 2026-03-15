// ============================================================================
// DATOS MOCK - SOLO PARA DESARROLLO/DEMO
// ============================================================================
// 
// Este archivo contiene SOLO datos inventados para probar la interfaz.
// En producción, estos datos vendrán del canister a través de canister-service.ts
//
// ============================================================================

// ============================================================================
// DATOS DE AUDITORÍA
// ============================================================================

export const auditData = {
  canisterId: "rrkah-fqaaa-aaaaa-aaaaq-cai",
  wasmModuleHash: "a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u1v2w3x4y5z6a7b8c9d0e1f2",
  cyclesBalance: "4.52T",
  codeVersion: "1.2.3"
}

// ============================================================================
// RESULTADOS AGREGADOS
// ============================================================================

export const mockResultsData = {
  totalVotes: 1247,
  blockchainTrustPercentage: 72,
  averageHoursSaved: 3.4,
  
  // Distribución de herramientas IA (Pregunta 1)
  toolDistribution: [
    { name: "ChatGPT", value: 42 },
    { name: "Gemini", value: 18 },
    { name: "Claude", value: 15 },
    { name: "Copilot", value: 12 },
    { name: "Ninguna", value: 8 },
    { name: "Otra", value: 5 }
  ],
  
  // Uso por fase académica (Pregunta 2)
  usageByPhase: [
    { phase: "Búsqueda inicial", ChatGPT: 35, Gemini: 20, Claude: 18, Copilot: 8 },
    { phase: "Conceptos", ChatGPT: 40, Gemini: 25, Claude: 22, Copilot: 5 },
    { phase: "PECs", ChatGPT: 45, Gemini: 15, Claude: 12, Copilot: 10 },
    { phase: "Revisión", ChatGPT: 38, Gemini: 18, Claude: 20, Copilot: 8 },
    { phase: "Código", ChatGPT: 30, Gemini: 10, Claude: 15, Copilot: 45 }
  ],
  
  // Impacto IA - Radar (Preguntas 3-6)
  impactRadar: [
    { axis: "quality", value: 3.8, fullMark: 5 },
    { axis: "ethics", value: 3.2, fullMark: 5 },
    { axis: "effort", value: 2.8, fullMark: 5 },
    { axis: "savings", value: 4.1, fullMark: 5 }
  ],
  
  // Matriz de seguridad (Preguntas 8-10)
  securityMatrix: [
    { category: "uocId", confia: 45, neutral: 35, desconfia: 20 },
    { category: "anonymousId", confia: 68, neutral: 22, desconfia: 10 },
    { category: "immutability", confia: 72, neutral: 18, desconfia: 10 }
  ],
  
  // Preferencia ICP vs Google Forms (Pregunta 12)
  icpPreference: 64
}

// ============================================================================
// RESPUESTAS CRUDAS PARA CSV
// ============================================================================

export const mockRawResponses = Array.from({ length: 50 }, (_, i) => ({
  numero: i + 1,
  p1: ["ChatGPT", "Gemini", "Claude", "Copilot", "Ninguna", "Otra"][Math.floor(Math.random() * 6)],
  p2: ["Búsqueda inicial", "Conceptos", "PECs", "Revisión", "Código"][Math.floor(Math.random() * 5)],
  p3: ["Menos de 1h", "1-3h", "4-7h", "Más de 7h"][Math.floor(Math.random() * 4)],
  p4: [1, 2, 3, 4, 5][Math.floor(Math.random() * 5)],
  p5: ["Tutor personal", "Apoyo redacción", "Generador total", "No usarse"][Math.floor(Math.random() * 4)],
  p6: ["Sí, dependo", "No, aprendo más", "No influye"][Math.floor(Math.random() * 3)],
  p7: ["Fomentan", "Permiten con límites", "Prohíben", "No pronunciado"][Math.floor(Math.random() * 4)],
  p8: ["Sí, desconfianza", "No, me parece bien", "Indiferente"][Math.floor(Math.random() * 3)],
  p9: ["Sí, fundamental", "Me da igual", "No me fío"][Math.floor(Math.random() * 3)],
  p10: ["Confío plenamente", "Dudas técnicas", "No confío"][Math.floor(Math.random() * 3)],
  p11: ["Sí, necesaria", "No, hay alternativas", "No conozco"][Math.floor(Math.random() * 3)],
  p12: ["Prefiero ICP", "Prefiero Google Forms", "Indiferente"][Math.floor(Math.random() * 3)]
}))
