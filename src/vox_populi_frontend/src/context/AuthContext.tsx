import { createContext, useContext, useState, useEffect, ReactNode, useCallback } from "react"

const SESSION_KEY = "voxpopuli_session"
const SESSION_DURATION_DAYS = 30

interface AuthContextType {
  isLoggedIn: boolean      // El nombre que ya tenías
  isAuthenticated: boolean // Añadimos este alias para que no falle la Landing
  isInitializing: boolean
  userEmail: string | null
  userVoterId: string | null
  userIdToken: string | null
  login: (email: string, voterId: string, idToken: string) => void
  logout: () => void
}

const AuthContext = createContext<AuthContextType | null>(null)

export function AuthProvider({ children }: { children: ReactNode }) {
  const [isLoggedIn, setIsLoggedIn] = useState(false)
  const [userEmail, setUserEmail] = useState<string | null>(null)
  const [userVoterId, setUserVoterId] = useState<string | null>(null)
  const [userIdToken, setUserIdToken] = useState<string | null>(null)
  const [isInitializing, setIsInitializing] = useState(true)

  // Creamos la propiedad derivada
  const isAuthenticated = isLoggedIn

  const logout = useCallback(() => {
    sessionStorage.removeItem(SESSION_KEY)
    setIsLoggedIn(false)
    setUserEmail(null)
    setUserVoterId(null)
    setUserIdToken(null)
  }, [])

  useEffect(() => {
    const stored = sessionStorage.getItem(SESSION_KEY)
    if (stored) {
      try {
        const session = JSON.parse(stored)
        if (Date.now() < session.expiresAt) {
          setIsLoggedIn(true)
          setUserEmail(session.email)
          setUserVoterId(session.voterId ?? null)
          setUserIdToken(session.idToken ?? null)
        } else {
          logout()
        }
      } catch {
        logout()
      }
    }
    setIsInitializing(false)
  }, [logout])

  const login = (email: string, voterId: string, idToken: string) => {
    const expiresAt = Date.now() + SESSION_DURATION_DAYS * 24 * 60 * 60 * 1000
    sessionStorage.setItem(SESSION_KEY, JSON.stringify({ email, voterId, idToken, expiresAt }))
    setIsLoggedIn(true)
    setUserEmail(email)
    setUserVoterId(voterId)
    setUserIdToken(idToken)
  }

  return (
    <AuthContext.Provider value={{ 
      isLoggedIn, 
      isAuthenticated, // Lo pasamos aquí
      isInitializing, 
      userEmail, 
      userVoterId,
      userIdToken,
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