import { BrowserRouter } from "react-router-dom"
import { AuthProvider } from "./context/AuthContext"
import { LocaleProvider } from "./lib/locale-context"
import { AppRoutes } from "./routes/AppRoutes"

export default function App() {
  return (
    <LocaleProvider>
      <AuthProvider>
        <BrowserRouter>
          <AppRoutes />
        </BrowserRouter>
      </AuthProvider>
    </LocaleProvider>
  )
}