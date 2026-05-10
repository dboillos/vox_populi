import { createContext, useContext, useState, useEffect, ReactNode, useCallback } from "react"
import { canisterService } from "@/lib/canister-service"

const SESSION_KEY = "voxpopuli_session"
interface AuthContextType {
  isLoggedIn: boolean      // El nombre que ya tenías
  isAuthenticated: boolean // Añadimos este alias para que no falle la Landing
  isInitializing: boolean
  userSessionId: string | null
  login: (sessionId: string, expiresAt: number) => void
  logout: () => void
}

const AuthContext = createContext<AuthContextType | null>(null)

export function AuthProvider({ children }: { children: ReactNode }) {
  const [isLoggedIn, setIsLoggedIn] = useState(false)
  const [userSessionId, setUserSessionId] = useState<string | null>(null)
  const [isInitializing, setIsInitializing] = useState(true)

  // Creamos la propiedad derivada
  const isAuthenticated = isLoggedIn

  const logout = useCallback(() => {
    sessionStorage.removeItem(SESSION_KEY)
    canisterService.resetClientIdentity()
    setIsLoggedIn(false)
    setUserSessionId(null)
  }, [])

  useEffect(() => {
    const stored = sessionStorage.getItem(SESSION_KEY)
    if (stored) {
      try {
        const session = JSON.parse(stored)
        if (Date.now() < session.expiresAt) {
          setIsLoggedIn(true)
          setUserSessionId(session.sessionId ?? null)
        } else {
          logout()
        }
      } catch {
        logout()
      }
    }
    setIsInitializing(false)
  }, [logout])

  const login = (sessionId: string, expiresAt: number) => {
    sessionStorage.setItem(SESSION_KEY, JSON.stringify({ sessionId, expiresAt }))
    setIsLoggedIn(true)
    setUserSessionId(sessionId)
  }

  return (
    <AuthContext.Provider value={{ 
      isLoggedIn, 
      isAuthenticated, // Lo pasamos aquí
      isInitializing, 
      userSessionId,
      login, 
      logout 
    }}>
      {children}
    </AuthContext.Provider>
  )
}

export const useAuth = () => {
  const context = useContext(AuthContext)
  if (!context) throw new Error("useAuth debe usarse dentro de AuthProvider")
  return context
}