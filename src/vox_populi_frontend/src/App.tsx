import { BrowserRouter } from "react-router-dom"
import { Component, type ReactNode } from "react"
import { AuthProvider } from "./context/AuthContext"
import { LocaleProvider } from "./lib/locale-context"
import { AppRoutes } from "./routes/AppRoutes"

class ErrorBoundary extends Component<{ children: ReactNode }, { error: Error | null }> {
  constructor(props: { children: ReactNode }) {
    super(props)
    this.state = { error: null }
  }
  static getDerivedStateFromError(error: Error) {
    return { error }
  }
  render() {
    if (this.state.error) {
      return (
        <div style={{ padding: "2rem", fontFamily: "sans-serif", color: "#333" }}>
          <h2>Algo ha ido mal</h2>
          <pre style={{ whiteSpace: "pre-wrap", fontSize: "0.8rem", color: "#c00" }}>
            {this.state.error.message}
          </pre>
          <button onClick={() => window.location.reload()}>Recargar</button>
        </div>
      )
    }
    return this.props.children
  }
}

export default function App() {
  return (
    <ErrorBoundary>
      <LocaleProvider>
        <AuthProvider>
          <BrowserRouter>
            <AppRoutes />
          </BrowserRouter>
        </AuthProvider>
      </LocaleProvider>
    </ErrorBoundary>
  )
}