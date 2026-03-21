

import { useState } from "react"
import { Routes, Route, Navigate, useNavigate } from "react-router-dom"
import { useAuth } from "../context/AuthContext"
import { ProtectedRoute } from "./ProtectedRoute"

// IMPORTACIÓN DE PÁGINAS (Nomenclatura Profesional)
import { LandingPage } from "../pages/landing/LandingPage"
import { ResultsPage } from "../pages/results/ResultsPage"
import { AuditPage } from "../pages/audit/AuditPage"
import { SurveyPage } from "../pages/survey/SurveyPage";

// MODALES GLOBALES
import { SuccessModal } from "../components/success-modal"

export function AppRoutes() {
  const navigate = useNavigate()
  const { isInitializing } = useAuth()
  const [showSuccessModal, setShowSuccessModal] = useState(false)

  // 1. Pantalla de carga mientras se verifica la sesion en el Canister/sessionStorage
  if (isInitializing) {
    return (
      <div className="flex h-screen items-center justify-center bg-background">
        <div className="flex flex-col items-center gap-4">
          <div className="animate-spin rounded-full h-10 w-10 border-t-2 border-primary border-r-2" />
          <p className="text-muted-foreground animate-pulse text-sm">Cargando Vox Populi...</p>
        </div>
      </div>
    )
  }

  return (
    <main className="snap-container">
      <Routes>
        {/* ============================================================
            RUTAS PÚBLICAS
           ============================================================ */}
        <Route path="/" element={
          <LandingPage 
            onVote={() => navigate("/survey")} 
            onResults={() => navigate("/results")} 
            onAudit={() => navigate("/audit")} 
          />
        } />
        
        <Route path="/audit" element={<AuditPage onBack={() => navigate("/")} />} />

        {/* ============================================================
            RUTAS PROTEGIDAS (Requieren Login)
           ============================================================ */}
        <Route element={<ProtectedRoute />}>
          <Route 
            path="/survey" 
            element={
              <SurveyPage 
                onBack={() => navigate("/")} 
                onComplete={() => setShowSuccessModal(true)} 
              />
            } 
          />
          <Route 
            path="/results" 
            element={<ResultsPage onBack={() => navigate("/")} />} 
          />
        </Route>

        {/* ============================================================
            FALLBACK (404)
           ============================================================ */}
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>

      {/* MODAL DE ÉXITO POST-VOTACIÓN */}
      <SuccessModal
        isOpen={showSuccessModal}
        onClose={() => setShowSuccessModal(false)}
        onViewResults={() => { 
          setShowSuccessModal(false); 
          navigate("/results"); 
        }}
        onBackHome={() => { 
          setShowSuccessModal(false); 
          navigate("/"); 
        }}
      />
    </main>
  )
}