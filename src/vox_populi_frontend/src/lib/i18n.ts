// ============================================================================
// SISTEMA DE INTERNACIONALIZACIÓN
// ============================================================================
// Archivo centralizado con todas las traducciones de la aplicación.
// Idiomas disponibles: Castellano (es), English (en), Català (ca)
// ============================================================================

export type Locale = "es" | "en" | "ca"

export const localeNames: Record<Locale, string> = {
  es: "Castellano",
  en: "English",
  ca: "Català"
}

export interface Translations {
  // Header
  header: {
    title: string
    subtitle: string
    poweredBy: string
  }
  
  // Landing
  landing: {
    heroTitle: string
    heroDescription: string
    footerText: string
  }
  
  // Survey Card
  surveyCard: {
    active: string
    upcoming: string
    votes: string
    until: string
    vote: string
    viewResults: string
    audit: string
  }
  
  // Survey Section
  survey: {
    back: string
    questionOf: string
    questionLabel: string
    previous: string
    next: string
    submit: string
  }
  
  // Results Section
  results: {
    title: string
    backToHome: string
    totalVotes: string
    blockchainTrust: string
    avgHoursSaved: string
    toolEcosystem: string
    aiImpact: string
    securityMatrix: string
    digitalSovereignty: string
    preferICP: string
    score: string
    trusts: string
    neutral: string
    distrusts: string
    googleForms: string
    icp: string
    downloadCSV: string
    csvFilename: string
  }
  
  // Audit Section
  audit: {
    title: string
    backToHome: string
    transparencyTitle: string
    transparencyDescription: string
    canisterId: string
    canisterIdDesc: string
    wasmHash: string
    wasmHashDesc: string
    cyclesBalance: string
    cyclesBalanceDesc: string
    codeVersion: string
    codeVersionDesc: string
    verificationLinks: string
    verificationLinksDesc: string
    icDashboard: string
    icDashboardDesc: string
    icScan: string
    icScanDesc: string
    dataNote: string
  }
  
  // Login Modal
  login: {
    secureAccess: string
    loginDescription: string
    continueWithGoogle: string
    privacyNote: string
    privacyNoteParts: {
      before: string
      anonymousIdTerm: string
      after: string
    }
    accessDenied: string
    accessDeniedDescription: string
    domainError: string
    close: string
  }
  
  // Success Modal
  success: {
    voteRegistered: string
    voteDescription: string
    viewResults: string
    backToHome: string
    privacyNote: string
    privacyNoteParts: {
      before: string
      anonymousIdTerm: string
      after: string
    }
  }

  // Vote guard modal
  voteGuard: {
    alreadyVotedTitle: string
    alreadyVotedDescription: string
    viewResults: string
    close: string
  }
  
  // Radar chart axes
  radar: {
    quality: string
    ethics: string
    effort: string
    savings: string
  }
  
  // Security matrix categories
  securityCategories: {
    uocId: string
    anonymousId: string
    immutability: string
  }
  
  // Glosario de términos técnicos para tooltips
  glossary: {
    icp: string
    canister: string
    canisterId: string
    cycles: string
    wasmModule: string
    codeVersion: string
    blockchain: string
    oidc: string
    anonymousId: string
  }
}

export const translations: Record<Locale, Translations> = {
  // ============================================================================
  // CASTELLANO
  // ============================================================================
  es: {
    header: {
      title: "Vox Populi UOC",
      subtitle: "Participación Ciudadana en ICP",
      poweredBy: "Powered by Internet Computer"
    },
    landing: {
      heroTitle: "Tu voz, verificable en Blockchain",
      heroDescription: "Participa en encuestas institucionales con total transparencia. Cada voto es anónimo, inmutable y auditable en la red de Internet Computer.",
      footerText: "Plataforma de votacion descentralizada sobre Internet Computer"
    },
    surveyCard: {
      active: "Activa",
      upcoming: "Próximamente",
      votes: "votos",
      until: "Hasta",
      vote: "Votar",
      viewResults: "Ver Resultados",
      audit: "Auditoría On-chain"
    },
survey: {
      back: "Salir",
      questionOf: "Pregunta {current} de {total}",
      questionLabel: "Pregunta",
      previous: "Anterior",
      next: "Siguiente",
      submit: "Enviar Voto"
    },
    results: {
      title: "Dashboard de Resultados",
      backToHome: "Volver",
      totalVotes: "Votos Totales",
      blockchainTrust: "Confianza Blockchain",
      avgHoursSaved: "Media Horas Ahorradas",
      toolEcosystem: "Ecosistema de Herramientas IA (Pregunta 1)",
      aiImpact: "Impacto de la IA (Preguntas 3-6)",
      securityMatrix: "Matriz de Seguridad (Preguntas 8-10)",
      digitalSovereignty: "Soberanía Digital: ICP vs Tradicional (Pregunta 12)",
      preferICP: "prefieren ICP para encuestas sensibles",
      score: "Puntuación",
      trusts: "Confía",
      neutral: "Neutral",
      distrusts: "Desconfía",
      googleForms: "Google Forms",
      icp: "ICP",
      downloadCSV: "Descargar CSV",
      csvFilename: "resultados_encuesta"
    },
    audit: {
      title: "Auditoría On-chain",
      backToHome: "Volver",
      transparencyTitle: "Transparencia Total",
      transparencyDescription: "Toda la lógica de votación y almacenamiento de datos reside en un canister de Internet Computer. Verifica de forma independiente la integridad del sistema.",
      canisterId: "Canister ID",
      canisterIdDesc: "Identificador único del contrato inteligente en ICP",
      wasmHash: "Wasm Module Hash (SHA-256)",
      wasmHashDesc: "Hash criptográfico del código desplegado",
      cyclesBalance: "Cycles Balance",
      cyclesBalanceDesc: "Créditos computacionales disponibles",
      codeVersion: "Versión del Código",
      codeVersionDesc: "Versión actual del canister desplegado",
      verificationLinks: "Enlaces de Verificación",
      verificationLinksDesc: "Verifica estos datos de forma independiente en exploradores externos",
      icDashboard: "IC Dashboard",
      icDashboardDesc: "Panel oficial de Internet Computer",
      icScan: "ICScan",
      icScanDesc: "Explorador de blockchain ICP",
      dataNote: "Los datos mostrados son un ejemplo. En producción, se obtendrán directamente del canister."
    },
    login: {
      secureAccess: "Acceso Seguro",
      loginDescription: "Identifícate con tu cuenta institucional de la UOC para participar en la encuesta de forma anónima y segura.",
      continueWithGoogle: "Continuar con Google (@uoc.edu)",
      privacyNote: "Tu email solo se usa para verificar tu pertenencia a la UOC. Se generará un ID anónimo en ICP que no puede vincularse a tu identidad.",
      privacyNoteParts: {
        before: "Tu email solo se usa para verificar tu pertenencia a la UOC. Se generará un ",
        anonymousIdTerm: "ID anónimo en ICP",
        after: " que no puede vincularse a tu identidad."
      },
      accessDenied: "Acceso Denegado",
      accessDeniedDescription: "Para participar en esta encuesta necesitas una cuenta institucional @uoc.edu.",
      domainError: "El dominio de tu cuenta de Google no corresponde a la comunidad UOC. Si crees que esto es un error, contacta con soporte técnico.",
      close: "Cerrar"
    },
    success: {
      voteRegistered: "¡Voto Registrado!",
      voteDescription: "Tu voto ha sido registrado de forma anónima e inmutable en la blockchain de Internet Computer.",
      viewResults: "Ver Resultados",
      backToHome: "Volver al Inicio",
      privacyNote: "Tu ID anónimo en ICP garantiza que tu identidad permanece protegida mientras tu voto es verificable públicamente.",
      privacyNoteParts: {
        before: "Tu ",
        anonymousIdTerm: "ID anónimo en ICP",
        after: " garantiza que tu identidad permanece protegida mientras tu voto es verificable públicamente."
      }
    },
    voteGuard: {
      alreadyVotedTitle: "Ya has votado en esta encuesta",
      alreadyVotedDescription: "Tu voto ya fue registrado previamente y no puedes votar de nuevo en la misma encuesta.",
      viewResults: "Ver resultados",
      close: "Cerrar"
    },
    radar: {
      quality: "Calidad (Pregunta 4)",
      ethics: "Ética (Pregunta 5)",
      effort: "Esfuerzo (Pregunta 6)",
      savings: "Ahorro (Pregunta 3)"
    },
    securityCategories: {
      uocId: "Identificación UOC (Pregunta 8)",
      anonymousId: "ID Anónimo ICP (Pregunta 9)",
      immutability: "Inmutabilidad Blockchain (Pregunta 10)"
    },
    glossary: {
      icp: "Internet Computer Protocol (ICP) es una blockchain desarrollada por DFINITY que permite ejecutar aplicaciones descentralizadas a velocidad web, sin servidores tradicionales.",
      canister: "Un canister es un contrato inteligente en ICP que contiene código (WebAssembly) y estado. Funciona como un contenedor que ejecuta la lógica de la aplicación de forma descentralizada.",
      canisterId: "Identificador único y permanente que identifica un canister específico en la red de Internet Computer. Similar a una dirección de contrato en otras blockchains.",
      cycles: "Cycles son la unidad de cómputo en ICP. Funcionan como \"combustible\" para ejecutar código en los canisters. 1 Trillion de cycles equivale aproximadamente a 1 USD.",
      wasmModule: "WebAssembly (Wasm) es el formato de código compilado que ejecutan los canisters. El hash SHA-256 permite verificar que el código desplegado no ha sido alterado.",
      codeVersion: "Número de versión semántico (MAJOR.MINOR.PATCH) que identifica la versión actual del código del canister desplegado.",
      blockchain: "Tecnología de registro distribuido donde los datos se almacenan en bloques enlazados criptográficamente, garantizando inmutabilidad y transparencia.",
      oidc: "OpenID Connect es un protocolo de autenticación que permite verificar la identidad del usuario a través de proveedores como Google, sin compartir contraseñas.",
      anonymousId: "Identificador derivado criptográficamente de tu email que no puede ser revertido. Garantiza que puedas votar una sola vez sin revelar tu identidad."
    }
  },
  
  // ============================================================================
  // ENGLISH
  // ============================================================================
  en: {
    header: {
      title: "Vox Populi UOC",
      subtitle: "Civic Participation on ICP",
      poweredBy: "Powered by Internet Computer"
    },
    landing: {
      heroTitle: "Your voice, verifiable on Blockchain",
      heroDescription: "Participate in institutional surveys with full transparency. Each vote is anonymous, immutable, and auditable on the Internet Computer network.",
      footerText: "Decentralized voting platform on Internet Computer"
    },
    surveyCard: {
      active: "Active",
      upcoming: "Coming Soon",
      votes: "votes",
      until: "Until",
      vote: "Vote",
      viewResults: "View Results",
      audit: "On-chain Audit"
    },
survey: {
      back: "Exit",
      questionOf: "Question {current} of {total}",
      questionLabel: "Question",
      previous: "Previous",
      next: "Next",
      submit: "Submit Vote"
    },
    results: {
      title: "Results Dashboard",
      backToHome: "Back",
      totalVotes: "Total Votes",
      blockchainTrust: "Blockchain Trust",
      avgHoursSaved: "Avg Hours Saved",
      toolEcosystem: "AI Tools Ecosystem (Question 1)",
      aiImpact: "AI Impact (Questions 3-6)",
      securityMatrix: "Security Matrix (Questions 8-10)",
      digitalSovereignty: "Digital Sovereignty: ICP vs Traditional (Question 12)",
      preferICP: "prefer ICP for sensitive surveys",
      score: "Score",
      trusts: "Trusts",
      neutral: "Neutral",
      distrusts: "Distrusts",
      googleForms: "Google Forms",
      icp: "ICP",
      downloadCSV: "Download CSV",
      csvFilename: "survey_results"
    },
    audit: {
      title: "On-chain Audit",
      backToHome: "Back",
      transparencyTitle: "Total Transparency",
      transparencyDescription: "All voting logic and data storage resides in an Internet Computer canister. Independently verify the system's integrity.",
      canisterId: "Canister ID",
      canisterIdDesc: "Unique identifier of the smart contract on ICP",
      wasmHash: "Wasm Module Hash (SHA-256)",
      wasmHashDesc: "Cryptographic hash of the deployed code",
      cyclesBalance: "Cycles Balance",
      cyclesBalanceDesc: "Available computational credits",
      codeVersion: "Code Version",
      codeVersionDesc: "Current version of the deployed canister",
      verificationLinks: "Verification Links",
      verificationLinksDesc: "Verify this data independently on external explorers",
      icDashboard: "IC Dashboard",
      icDashboardDesc: "Official Internet Computer panel",
      icScan: "ICScan",
      icScanDesc: "ICP blockchain explorer",
      dataNote: "The data shown is an example. In production, it will be obtained directly from the canister."
    },
    login: {
      secureAccess: "Secure Access",
      loginDescription: "Sign in with your UOC institutional account to participate in the survey anonymously and securely.",
      continueWithGoogle: "Continue with Google (@uoc.edu)",
      privacyNote: "Your email is only used to verify your UOC membership. An anonymous ID will be generated on ICP that cannot be linked to your identity.",
      privacyNoteParts: {
        before: "Your email is only used to verify your UOC membership. An ",
        anonymousIdTerm: "anonymous ICP ID",
        after: " will be generated that cannot be linked to your identity."
      },
      accessDenied: "Access Denied",
      accessDeniedDescription: "To participate in this survey, you need an institutional @uoc.edu account.",
      domainError: "Your Google account domain does not belong to the UOC community. If you believe this is an error, please contact technical support.",
      close: "Close"
    },
    success: {
      voteRegistered: "Vote Registered!",
      voteDescription: "Your vote has been registered anonymously and immutably on the Internet Computer blockchain.",
      viewResults: "View Results",
      backToHome: "Back to Home",
      privacyNote: "Your anonymous ICP ID ensures your identity remains protected while your vote is publicly verifiable.",
      privacyNoteParts: {
        before: "Your ",
        anonymousIdTerm: "anonymous ICP ID",
        after: " ensures your identity remains protected while your vote is publicly verifiable."
      }
    },
    voteGuard: {
      alreadyVotedTitle: "You have already voted in this survey",
      alreadyVotedDescription: "Your vote was already recorded, and you cannot vote again in the same survey.",
      viewResults: "View results",
      close: "Close"
    },
    radar: {
      quality: "Quality (Question 4)",
      ethics: "Ethics (Question 5)",
      effort: "Effort (Question 6)",
      savings: "Savings (Question 3)"
    },
    securityCategories: {
      uocId: "UOC Identification (Question 8)",
      anonymousId: "Anonymous ICP ID (Question 9)",
      immutability: "Blockchain Immutability (Question 10)"
    },
    glossary: {
      icp: "Internet Computer Protocol (ICP) is a blockchain developed by DFINITY that enables decentralized applications to run at web speed, without traditional servers.",
      canister: "A canister is a smart contract on ICP containing code (WebAssembly) and state. It works as a container that executes application logic in a decentralized manner.",
      canisterId: "Unique and permanent identifier for a specific canister on the Internet Computer network. Similar to a contract address on other blockchains.",
      cycles: "Cycles are the compute unit in ICP. They work as \"fuel\" to execute code in canisters. 1 Trillion cycles equals approximately 1 USD.",
      wasmModule: "WebAssembly (Wasm) is the compiled code format that canisters execute. The SHA-256 hash allows verification that the deployed code has not been altered.",
      codeVersion: "Semantic version number (MAJOR.MINOR.PATCH) identifying the current version of the deployed canister code.",
      blockchain: "Distributed ledger technology where data is stored in cryptographically linked blocks, ensuring immutability and transparency.",
      oidc: "OpenID Connect is an authentication protocol that verifies user identity through providers like Google, without sharing passwords.",
      anonymousId: "Cryptographically derived identifier from your email that cannot be reversed. Ensures you can vote only once without revealing your identity."
    }
  },
  
  // ============================================================================
  // CATALÀ
  // ============================================================================
  ca: {
    header: {
      title: "Vox Populi UOC",
      subtitle: "Participació Ciutadana a ICP",
      poweredBy: "Powered by Internet Computer"
    },
    landing: {
      heroTitle: "La teva veu, verificable a Blockchain",
      heroDescription: "Participa en enquestes institucionals amb total transparència. Cada vot és anònim, immutable i auditable a la xarxa d'Internet Computer.",
      footerText: "Plataforma de votació descentralitzada sobre Internet Computer"
    },
    surveyCard: {
      active: "Activa",
      upcoming: "Pròximament",
      votes: "vots",
      until: "Fins",
      vote: "Votar",
      viewResults: "Veure Resultats",
      audit: "Auditoria On-chain"
    },
survey: {
      back: "Sortir",
      questionOf: "Pregunta {current} de {total}",
      questionLabel: "Pregunta",
      previous: "Anterior",
      next: "Següent",
      submit: "Enviar Vot"
    },
    results: {
      title: "Dashboard de Resultats",
      backToHome: "Tornar",
      totalVotes: "Vots Totals",
      blockchainTrust: "Confiança Blockchain",
      avgHoursSaved: "Mitjana Hores Estalviades",
      toolEcosystem: "Ecosistema d'Eines IA (Pregunta 1)",
      aiImpact: "Impacte de la IA (Preguntes 3-6)",
      securityMatrix: "Matriu de Seguretat (Preguntes 8-10)",
      digitalSovereignty: "Sobirania Digital: ICP vs Tradicional (Pregunta 12)",
      preferICP: "prefereixen ICP per a enquestes sensibles",
      score: "Puntuació",
      trusts: "Confia",
      neutral: "Neutral",
      distrusts: "Desconfia",
      googleForms: "Google Forms",
      icp: "ICP",
      downloadCSV: "Descarregar CSV",
      csvFilename: "resultats_enquesta"
    },
    audit: {
      title: "Auditoria On-chain",
      backToHome: "Tornar",
      transparencyTitle: "Transparència Total",
      transparencyDescription: "Tota la lògica de votació i emmagatzematge de dades resideix en un canister d'Internet Computer. Verifica de forma independent la integritat del sistema.",
      canisterId: "Canister ID",
      canisterIdDesc: "Identificador únic del contracte intel·ligent a ICP",
      wasmHash: "Wasm Module Hash (SHA-256)",
      wasmHashDesc: "Hash criptogràfic del codi desplegat",
      cyclesBalance: "Cycles Balance",
      cyclesBalanceDesc: "Crèdits computacionals disponibles",
      codeVersion: "Versió del Codi",
      codeVersionDesc: "Versió actual del canister desplegat",
      verificationLinks: "Enllaços de Verificació",
      verificationLinksDesc: "Verifica aquestes dades de forma independent a exploradors externs",
      icDashboard: "IC Dashboard",
      icDashboardDesc: "Panell oficial d'Internet Computer",
      icScan: "ICScan",
      icScanDesc: "Explorador de blockchain ICP",
      dataNote: "Les dades mostrades són un exemple. En producció, s'obtindran directament del canister."
    },
    login: {
      secureAccess: "Accés Segur",
      loginDescription: "Identifica't amb el teu compte institucional de la UOC per participar a l'enquesta de forma anònima i segura.",
      continueWithGoogle: "Continuar amb Google (@uoc.edu)",
      privacyNote: "El teu email només s'utilitza per verificar la teva pertinença a la UOC. Es generarà un ID anònim a ICP que no pot vincular-se a la teva identitat.",
      privacyNoteParts: {
        before: "El teu email només s'utilitza per verificar la teva pertinença a la UOC. Es generarà un ",
        anonymousIdTerm: "ID anònim a ICP",
        after: " que no pot vincular-se a la teva identitat."
      },
      accessDenied: "Accés Denegat",
      accessDeniedDescription: "Per participar en aquesta enquesta necessites un compte institucional @uoc.edu.",
      domainError: "El domini del teu compte de Google no correspon a la comunitat UOC. Si creus que això és un error, contacta amb suport tècnic.",
      close: "Tancar"
    },
    success: {
      voteRegistered: "Vot Registrat!",
      voteDescription: "El teu vot ha estat registrat de forma anònima i immutable a la blockchain d'Internet Computer.",
      viewResults: "Veure Resultats",
      backToHome: "Tornar a l'Inici",
      privacyNote: "El teu ID anònim a ICP garanteix que la teva identitat roman protegida mentre el teu vot és verificable públicament.",
      privacyNoteParts: {
        before: "El teu ",
        anonymousIdTerm: "ID anònim a ICP",
        after: " garanteix que la teva identitat roman protegida mentre el teu vot és verificable públicament."
      }
    },
    voteGuard: {
      alreadyVotedTitle: "Ja has votat en aquesta enquesta",
      alreadyVotedDescription: "El teu vot ja va ser registrat i no pots tornar a votar a la mateixa enquesta.",
      viewResults: "Veure resultats",
      close: "Tancar"
    },
    radar: {
      quality: "Qualitat (Pregunta 4)",
      ethics: "Ètica (Pregunta 5)",
      effort: "Esforç (Pregunta 6)",
      savings: "Estalvi (Pregunta 3)"
    },
    securityCategories: {
      uocId: "Identificació UOC (Pregunta 8)",
      anonymousId: "ID Anònim ICP (Pregunta 9)",
      immutability: "Immutabilitat Blockchain (Pregunta 10)"
    },
    glossary: {
      icp: "Internet Computer Protocol (ICP) és una blockchain desenvolupada per DFINITY que permet executar aplicacions descentralitzades a velocitat web, sense servidors tradicionals.",
      canister: "Un canister és un contracte intel·ligent a ICP que conté codi (WebAssembly) i estat. Funciona com un contenidor que executa la lògica de l'aplicació de forma descentralitzada.",
      canisterId: "Identificador únic i permanent que identifica un canister específic a la xarxa d'Internet Computer. Similar a una adreça de contracte en altres blockchains.",
      cycles: "Els cycles són la unitat de còmput a ICP. Funcionen com a \"combustible\" per executar codi als canisters. 1 Trilió de cycles equival aproximadament a 1 USD.",
      wasmModule: "WebAssembly (Wasm) és el format de codi compilat que executen els canisters. El hash SHA-256 permet verificar que el codi desplegat no ha estat alterat.",
      codeVersion: "Número de versió semàntic (MAJOR.MINOR.PATCH) que identifica la versió actual del codi del canister desplegat.",
      blockchain: "Tecnologia de registre distribuït on les dades s'emmagatzemen en blocs enllaçats criptogràficament, garantint immutabilitat i transparència.",
      oidc: "OpenID Connect és un protocol d'autenticació que permet verificar la identitat de l'usuari a través de proveïdors com Google, sense compartir contrasenyes.",
      anonymousId: "Identificador derivat criptogràficament del teu email que no pot ser revertit. Garanteix que puguis votar una sola vegada sense revelar la teva identitat."
    }
  }
}

// ============================================================================
// FIN DE TRADUCCIONES
// ============================================================================
// Las funciones que combinan traducciones + config están en /lib/survey-helpers.ts
