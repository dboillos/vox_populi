import { Navigate, Outlet } from "react-router-dom"
import { useAuth } from "../context/AuthContext"

export function ProtectedRoute() {
  const { isLoggedIn, isInitializing } = useAuth()

  // No retornamos nada mientras verificamos la sesión
  if (isInitializing) return null 

  // Si no está logueado, lo redirigimos a la raíz
  return isLoggedIn ? <Outlet /> : <Navigate to="/" replace />
}