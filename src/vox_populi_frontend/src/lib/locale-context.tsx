

import { createContext, useContext, useState, useEffect, type ReactNode } from "react"
import { type Locale, translations, type Translations } from "./i18n"

// ============================================================================
// CONTEXTO DE IDIOMA
// ============================================================================
// Gestiona el idioma seleccionado y lo persiste en sessionStorage.
// El idioma por defecto es castellano (es).
// ============================================================================

const LOCALE_KEY = "voxpopuli_locale"
const DEFAULT_LOCALE: Locale = "es"

interface LocaleContextType {
  locale: Locale
  setLocale: (locale: Locale) => void
  t: Translations
}

const LocaleContext = createContext<LocaleContextType | undefined>(undefined)

export function LocaleProvider({ children }: { children: ReactNode }) {
  const [locale, setLocaleState] = useState<Locale>(DEFAULT_LOCALE)

  // Cargar idioma guardado al iniciar
  useEffect(() => {
    const savedLocale = sessionStorage.getItem(LOCALE_KEY) as Locale | null
    if (savedLocale && translations[savedLocale]) {
      setLocaleState(savedLocale)
    }
  }, [])

  // Guardar idioma cuando cambie
  const setLocale = (newLocale: Locale) => {
    setLocaleState(newLocale)
    sessionStorage.setItem(LOCALE_KEY, newLocale)
  }

  const t = translations[locale]

  return (
    <LocaleContext.Provider value={{ locale, setLocale, t }}>
      {children}
    </LocaleContext.Provider>
  )
}

export function useLocale() {
  const context = useContext(LocaleContext)
  if (!context) {
    throw new Error("useLocale must be used within a LocaleProvider")
  }
  return context
}
