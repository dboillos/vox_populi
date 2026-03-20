import { useState } from "react"
import { motion } from "framer-motion"
import { Vote, Shield, ChevronDown } from "lucide-react"

import { Button } from "@/components/ui/button"
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog"
import { SurveyCard } from "@/components/layout/survey-card"
import { LanguageSelector } from "@/components/layout/language-selector"
import { ICPLogo } from "@/components/icons/icp-logo"
import { LoginModal } from "@/components/login-modal"

import { canisterService } from "@/lib/canister-service"
import { useLocale } from "@/lib/locale-context"
import { useAuth } from "@/context/AuthContext"
import { getTranslatedSurveys } from "@/lib/survey-helpers"

interface LandingPageProps {
  onVote: () => void
  onResults: () => void
  onAudit: () => void
}

// --- SUBCOMPONENTES INTERNOS ---
function LandingHeader() {
  const { t } = useLocale()
  return (
    <header className="w-full border-b border-border/50 bg-card/80 backdrop-blur-sm sticky top-0 z-40">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 h-16 flex items-center justify-between">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 bg-primary rounded-lg flex items-center justify-center">
            <Vote className="w-5 h-5 text-primary-foreground" />
          </div>
          <div>
            <h1 className="font-semibold text-foreground">{t.header.title}</h1>
            <p className="text-xs text-muted-foreground">{t.header.subtitle}</p>
          </div>
        </div>
        <LanguageSelector />
      </div>
    </header>
  )
}

function LandingFooter() {
  const { t } = useLocale()
  return (
    <footer className="border-t border-border/50 bg-card/50 mt-auto">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6 flex flex-col sm:flex-row items-center justify-between gap-4">
        <p className="text-sm text-muted-foreground text-center sm:text-left">
          {t.landing.footerText}
        </p>
        <div className="flex items-center gap-2 text-sm text-muted-foreground">
          <ICPLogo className="w-5 h-5" />
          <span>{t.header.poweredBy}</span>
        </div>
      </div>
    </footer>
  )
}

// --- COMPONENTE PRINCIPAL ---
export function LandingPage({ onVote, onResults, onAudit }: LandingPageProps) {
  const { locale, t } = useLocale()
  const { isLoggedIn, login, userVoterId } = useAuth()
  const [showLoginModal, setShowLoginModal] = useState(false)
  const [showAlreadyVotedModal, setShowAlreadyVotedModal] = useState(false)
  
  // Guarda la intención del usuario para ejecutarla tras login.
  const [pendingAction, setPendingAction] = useState<"vote" | "results" | null>(null)
  
  const surveys = getTranslatedSurveys(locale)

  const handleProtectedAction = (action: () => void) => {
    if (isLoggedIn) {
      action()
    } else {
      setPendingAction("results")
      setShowLoginModal(true)
    }
  }

  const handleVoteAction = async (voterIdOverride?: string) => {
    const effectiveVoterId = voterIdOverride ?? userVoterId
    const hasFreshIdentity = typeof voterIdOverride === "string" && voterIdOverride.length > 0

    if (!isLoggedIn && !hasFreshIdentity) {
      setPendingAction("vote")
      setShowLoginModal(true)
      return
    }

    if (!effectiveVoterId) {
      setPendingAction("vote")
      setShowLoginModal(true)
      return
    }

    try {
      const alreadyVoted = await canisterService.hasUserVoted("ai-uoc-2024", effectiveVoterId)

      if (alreadyVoted) {
        setShowAlreadyVotedModal(true)
        return
      }

      onVote()
    } catch (error) {
      console.error("[LandingPage] No se pudo validar si el usuario ya ha votado", error)
      onVote()
    }
  }

  return (
    <div className="flex flex-col min-h-screen bg-background">
      <LandingHeader />
      
      <main className="flex-1 flex flex-col">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-12 lg:py-16 w-full">
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.6 }}
            className="text-center mb-12 lg:mb-16"
          >
            <h2 className="text-3xl sm:text-4xl lg:text-5xl font-semibold text-foreground mb-4 text-balance">
              {t.landing.heroTitle}
            </h2>
            <p className="text-lg sm:text-xl text-muted-foreground max-w-2xl mx-auto leading-relaxed text-pretty mb-6">
              {t.landing.heroDescription}
            </p>
            <Button
              onClick={onAudit}
              variant="outline"
              className="border-primary/30 text-primary hover:bg-primary/5"
            >
              <Shield className="w-4 h-4 mr-2" />
              {t.surveyCard.audit}
            </Button>
          </motion.div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-6 lg:gap-8">
            {surveys.map((survey, index) => (
              <SurveyCard
                key={survey.id}
                survey={survey}
                index={index}
                onVote={() => {
                  void handleVoteAction()
                }}
                onResults={() => handleProtectedAction(onResults)}
              />
            ))}
          </div>
        </div>

        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ delay: 1, duration: 0.5 }}
          className="flex justify-center pb-4 mt-auto"
        >
          <motion.div
            animate={{ y: [0, 8, 0] }}
            transition={{ duration: 2, repeat: Infinity, ease: "easeInOut" }}
            className="text-muted-foreground/50"
          >
            <ChevronDown className="w-6 h-6" />
          </motion.div>
        </motion.div>
      </main>

      <LandingFooter />

      <LoginModal 
        isOpen={showLoginModal} 
        onClose={() => {
          setShowLoginModal(false)
          setPendingAction(null) // Limpiamos si cierra sin loguearse
        }}
        mode="login"
        onSuccess={(identity) => {
          login(identity.email, identity.voterId)
          setShowLoginModal(false)
          
          // EJECUCIÓN AUTOMÁTICA: Si había algo pendiente, lo lanzamos ahora
          if (pendingAction === "vote") {
            void handleVoteAction(identity.voterId)
          }

          if (pendingAction === "results") {
            onResults()
          }

          setPendingAction(null)
        }}
      />

      <AlertDialog open={showAlreadyVotedModal} onOpenChange={setShowAlreadyVotedModal}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{t.voteGuard.alreadyVotedTitle}</AlertDialogTitle>
            <AlertDialogDescription>{t.voteGuard.alreadyVotedDescription}</AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>{t.voteGuard.close}</AlertDialogCancel>
            <AlertDialogAction
              onClick={() => {
                setShowAlreadyVotedModal(false)
                onResults()
              }}
            >
              {t.voteGuard.viewResults}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  )
}