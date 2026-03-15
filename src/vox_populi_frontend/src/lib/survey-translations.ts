import type { Locale } from "./i18n"

export interface SurveyTranslationSet {
  surveys: Record<string, { title: string; description: string }>
  questions: Record<number, { text: string; options: string[] }>
}

export const surveyTranslations: Record<Locale, SurveyTranslationSet> = {
  es: {
    surveys: {
      "ai-uoc-2024": {
        title: "Uso de la IA en la UOC",
        description: "Encuesta sobre el uso de herramientas de IA generativa en el entorno académico de la UOC"
      },
      "sostenibilidad": {
        title: "Sostenibilidad",
        description: "Iniciativas de sostenibilidad y medio ambiente en el campus virtual"
      },
      "transporte": {
        title: "Transporte Campus",
        description: "Opciones de movilidad y transporte para eventos presenciales"
      },
      "presupuestos": {
        title: "Presupuestos Participativos",
        description: "Decide cómo invertir parte del presupuesto universitario"
      }
    },
    questions: {
      1: {
        text: "¿Qué herramienta de IA generativa utilizas con mayor frecuencia en tus estudios?",
        options: ["ChatGPT", "Gemini", "Claude", "Copilot", "Ninguna", "Otra"]
      },
      2: {
        text: "¿En qué fase de tus actividades académicas recurres principalmente a la IA?",
        options: ["Búsqueda inicial de información", "Comprender conceptos complejos", "Preparación de PECs/entregas", "Revisión de borradores", "Generar código"]
      },
      3: {
        text: "¿Cuántas horas semanales estimas que ahorras en tareas mecánicas gracias a la IA?",
        options: ["Menos de 1h", "1-3h", "4-7h", "Más de 7h"]
      },
      4: {
        text: "Del 1 al 5, ¿cuánto consideras que la IA ha mejorado la calidad final de tus entregas?",
        options: ["1 - Nada", "2 - Poco", "3 - Moderado", "4 - Bastante", "5 - Mucho"]
      },
      5: {
        text: "¿Qué uso consideras más ético para un estudiante?",
        options: ["Tutor personal para dudas", "Apoyo en redacción y estructura", "Generador total de contenido", "No debería usarse"]
      },
      6: {
        text: "¿Sientes que el uso de IA reduce tu esfuerzo de aprendizaje real?",
        options: ["Sí, dependo demasiado de ella", "No, aprendo más rápido con ella", "No influye en mi aprendizaje"]
      },
      7: {
        text: "¿Cómo describirías la actitud de tus profesores respecto al uso de estas herramientas?",
        options: ["Fomentan su uso activamente", "Permiten con ciertos límites", "Prohíben su uso", "No se han pronunciado"]
      },
      8: {
        text: "¿Te genera desconfianza tener que identificarte con tu cuenta de la UOC (Google OIDC) para participar?",
        options: ["Sí, me genera desconfianza", "No, me parece bien", "Me es indiferente"]
      },
      9: {
        text: "¿Te sientes más seguro al saber que el sistema genera un ID anónimo en ICP y no guarda tu email?",
        options: ["Sí, es fundamental para mí", "Me da igual", "No me fío del sistema de todos modos"]
      },
      10: {
        text: "¿Confías en la inmutabilidad de tu voto (que nadie pueda borrarlo) al estar en una red Blockchain?",
        options: ["Confío plenamente", "Tengo dudas técnicas", "No confío en absoluto"]
      },
      11: {
        text: "¿Consideras que la tecnología Blockchain es necesaria para garantizar la transparencia en procesos de votación?",
        options: ["Sí, es necesaria", "No, hay otras alternativas", "No conozco la tecnología"]
      },
      12: {
        text: "¿Preferirías usar esta plataforma basada en ICP antes que Google Forms para encuestas institucionales sensibles?",
        options: ["Sí, prefiero ICP", "No, prefiero Google Forms", "Me es indiferente"]
      }
    }
  },
  en: {
    surveys: {
      "ai-uoc-2024": {
        title: "AI Usage at UOC",
        description: "Survey on the use of generative AI tools in the UOC academic environment"
      },
      "sostenibilidad": {
        title: "Sustainability",
        description: "Sustainability and environmental initiatives on the virtual campus"
      },
      "transporte": {
        title: "Campus Transport",
        description: "Mobility and transport options for in-person events"
      },
      "presupuestos": {
        title: "Participatory Budgets",
        description: "Decide how to invest part of the university budget"
      }
    },
    questions: {
      1: {
        text: "Which generative AI tool do you use most frequently in your studies?",
        options: ["ChatGPT", "Gemini", "Claude", "Copilot", "None", "Other"]
      },
      2: {
        text: "In which phase of your academic activities do you mainly use AI?",
        options: ["Initial information search", "Understanding complex concepts", "Preparing assignments/submissions", "Draft review", "Code generation"]
      },
      3: {
        text: "How many hours per week do you estimate you save on mechanical tasks thanks to AI?",
        options: ["Less than 1h", "1-3h", "4-7h", "More than 7h"]
      },
      4: {
        text: "From 1 to 5, how much do you think AI has improved the final quality of your submissions?",
        options: ["1 - Not at all", "2 - A little", "3 - Moderate", "4 - Quite a bit", "5 - A lot"]
      },
      5: {
        text: "What use do you consider most ethical for a student?",
        options: ["Personal tutor for questions", "Support in writing and structure", "Total content generator", "Should not be used"]
      },
      6: {
        text: "Do you feel that using AI reduces your real learning effort?",
        options: ["Yes, I depend too much on it", "No, I learn faster with it", "It doesn't affect my learning"]
      },
      7: {
        text: "How would you describe your professors' attitude towards using these tools?",
        options: ["They actively encourage its use", "They allow it with certain limits", "They prohibit its use", "They haven't expressed an opinion"]
      },
      8: {
        text: "Does it make you distrust having to identify yourself with your UOC account (Google OIDC) to participate?",
        options: ["Yes, it makes me distrust", "No, it seems fine", "I'm indifferent"]
      },
      9: {
        text: "Do you feel more secure knowing that the system generates an anonymous ID on ICP and doesn't store your email?",
        options: ["Yes, it's essential for me", "I don't care", "I don't trust the system anyway"]
      },
      10: {
        text: "Do you trust the immutability of your vote (that no one can delete it) being on a Blockchain network?",
        options: ["I fully trust", "I have technical doubts", "I don't trust at all"]
      },
      11: {
        text: "Do you think Blockchain technology is necessary to guarantee transparency in voting processes?",
        options: ["Yes, it's necessary", "No, there are other alternatives", "I don't know the technology"]
      },
      12: {
        text: "Would you prefer to use this ICP-based platform over Google Forms for sensitive institutional surveys?",
        options: ["Yes, I prefer ICP", "No, I prefer Google Forms", "I'm indifferent"]
      }
    }
  },
  ca: {
    surveys: {
      "ai-uoc-2024": {
        title: "Ús de la IA a la UOC",
        description: "Enquesta sobre l'ús d'eines d'IA generativa a l'entorn acadèmic de la UOC"
      },
      "sostenibilidad": {
        title: "Sostenibilitat",
        description: "Iniciatives de sostenibilitat i medi ambient al campus virtual"
      },
      "transporte": {
        title: "Transport Campus",
        description: "Opcions de mobilitat i transport per a esdeveniments presencials"
      },
      "presupuestos": {
        title: "Pressupostos Participatius",
        description: "Decideix com invertir part del pressupost universitari"
      }
    },
    questions: {
      1: {
        text: "Quina eina d'IA generativa utilitzes amb més freqüència als teus estudis?",
        options: ["ChatGPT", "Gemini", "Claude", "Copilot", "Cap", "Altra"]
      },
      2: {
        text: "En quina fase de les teves activitats acadèmiques recorres principalment a la IA?",
        options: ["Cerca inicial d'informació", "Comprendre conceptes complexos", "Preparació de PACs/lliuraments", "Revisió d'esborranys", "Generar codi"]
      },
      3: {
        text: "Quantes hores setmanals estimes que estalvies en tasques mecàniques gràcies a la IA?",
        options: ["Menys d'1h", "1-3h", "4-7h", "Més de 7h"]
      },
      4: {
        text: "De l'1 al 5, quant consideres que la IA ha millorat la qualitat final dels teus lliuraments?",
        options: ["1 - Gens", "2 - Poc", "3 - Moderat", "4 - Bastant", "5 - Molt"]
      },
      5: {
        text: "Quin ús consideres més ètic per a un estudiant?",
        options: ["Tutor personal per a dubtes", "Suport en redacció i estructura", "Generador total de contingut", "No s'hauria d'utilitzar"]
      },
      6: {
        text: "Sents que l'ús d'IA redueix el teu esforç d'aprenentatge real?",
        options: ["Sí, en depenc massa", "No, aprenc més ràpid amb ella", "No influeix en el meu aprenentatge"]
      },
      7: {
        text: "Com descriuries l'actitud dels teus professors respecte a l'ús d'aquestes eines?",
        options: ["Fomenten el seu ús activament", "Permeten amb certs límits", "Prohibeixen el seu ús", "No s'han pronunciat"]
      },
      8: {
        text: "Et genera desconfiança haver d'identificar-te amb el teu compte de la UOC (Google OIDC) per participar?",
        options: ["Sí, em genera desconfiança", "No, em sembla bé", "M'és indiferent"]
      },
      9: {
        text: "Et sents més segur en saber que el sistema genera un ID anònim a ICP i no guarda el teu email?",
        options: ["Sí, és fonamental per a mi", "M'és igual", "No em fio del sistema de totes maneres"]
      },
      10: {
        text: "Confies en la immutabilitat del teu vot (que ningú pugui esborrar-lo) en estar en una xarxa Blockchain?",
        options: ["Confio plenament", "Tinc dubtes tècnics", "No confio en absolut"]
      },
      11: {
        text: "Consideres que la tecnologia Blockchain és necessària per garantir la transparència en processos de votació?",
        options: ["Sí, és necessària", "No, hi ha altres alternatives", "No conec la tecnologia"]
      },
      12: {
        text: "Preferiries utilitzar aquesta plataforma basada en ICP abans que Google Forms per a enquestes institucionals sensibles?",
        options: ["Sí, prefereixo ICP", "No, prefereixo Google Forms", "M'és indiferent"]
      }
    }
  }
}
