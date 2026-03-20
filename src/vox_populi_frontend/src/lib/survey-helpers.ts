// ============================================================================
// FUNCIONES HELPER - Combinan configuración + traducciones
// ============================================================================
// 
// Estas funciones unen:
// - survey-config.ts (estructura de preguntas/encuestas)
// - survey-mock.ts (datos mock para desarrollo)
// - survey-translations.ts (textos de encuestas y preguntas)
// - i18n.ts (textos generales de UI)
//
// En producción, los datos mock se reemplazan por canister-service.ts
//
// ============================================================================

import type { AggregatedResults } from './canister-service'
import { questionsConfig, surveysConfig } from './survey-config'
import { translations, Locale } from './i18n'
import { surveyTranslations } from './survey-translations'

function hasDeadlinePassed(deadlineIso: string): boolean {
  const parts = deadlineIso.split("-")
  if (parts.length !== 3) {
    return false
  }

  const year = Number(parts[0])
  const month = Number(parts[1])
  const day = Number(parts[2])

  if (!Number.isFinite(year) || !Number.isFinite(month) || !Number.isFinite(day)) {
    return false
  }

  // Se considera activa durante todo el dia indicado en deadlineIso.
  const deadlineEnd = new Date(year, month - 1, day, 23, 59, 59, 999)
  return Date.now() > deadlineEnd.getTime()
}

/**
 * Combina la configuración de preguntas con los textos traducidos
 * - questionsConfig: define IDs y lógica de saltos
 * - survey-translations: proporciona textos en el idioma seleccionado
 */
export function getTranslatedQuestions(locale: Locale) {
  const questionTexts = surveyTranslations[locale].questions
  
  return questionsConfig.map(config => {
    const texts = questionTexts[config.id]
    return {
      id: config.id,
      text: texts.text,
      options: texts.options,
      skipTo: config.skipTo,
      skipTrigger: config.skipTriggerIndex !== undefined 
        ? texts.options[config.skipTriggerIndex] 
        : undefined
    }
  })
}

export function getQuestionOptionsByLocale(locale: Locale) {
  const questionTexts = surveyTranslations[locale].questions

  return questionsConfig.reduce<Record<number, string[]>>((accumulator, config) => {
    accumulator[config.id] = questionTexts[config.id].options
    return accumulator
  }, {})
}

/**
 * Combina la configuración de encuestas con los textos traducidos
 */
export function getTranslatedSurveys(locale: Locale) {
  const surveyTexts = surveyTranslations[locale].surveys
  
  return surveysConfig.map(config => ({
    status: config.status === "active" && config.deadlineIso && hasDeadlinePassed(config.deadlineIso)
      ? "closed"
      : config.status,
    id: config.id,
    title: surveyTexts[config.id].title,
    description: surveyTexts[config.id].description,
    votes: config.votes,
    deadline: config.deadline
  }))
}

/**
 * Traduce las etiquetas de los gráficos de resultados
 */
export function getTranslatedResultsData(locale: Locale, results: AggregatedResults) {
  const t = translations[locale]
  const toolOptions = surveyTranslations[locale].questions[1].options
  
  const radarKeyToLabel: Record<string, string> = {
    quality: t.radar.quality,
    ethics: t.radar.ethics,
    effort: t.radar.effort,
    savings: t.radar.savings
  }
  
  const securityKeyToLabel: Record<string, string> = {
    uocId: t.securityCategories.uocId,
    anonymousId: t.securityCategories.anonymousId,
    immutability: t.securityCategories.immutability
  }
  
  return {
    toolDistribution: results.toolDistribution.map(item => ({
      name: toolOptions[item.optionIndex] ?? `Opción ${item.optionIndex + 1}`,
      value: item.value,
    })),
    impactRadar: results.impactRadar.map(item => ({
      ...item,
      axis: radarKeyToLabel[item.axis] || item.axis
    })),
    securityMatrix: results.securityMatrix.map(item => ({
      ...item,
      category: securityKeyToLabel[item.category] || item.category
    }))
  }
}
