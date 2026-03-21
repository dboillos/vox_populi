

import { useState, useCallback } from "react"
import { motion, AnimatePresence } from "framer-motion"
import { ChevronLeft, ChevronRight, CheckCircle2, ArrowLeft, AlertCircle } from "lucide-react"
// CORRECCIÓN: Rutas relativas actualizadas (subimos dos niveles)
import { Button } from "../../components/ui/button"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "../../components/ui/dialog"
import { Progress } from "../../components/ui/progress"
import { useAuth } from "../../context/AuthContext"
import { useLocale } from "../../lib/locale-context"
import { getQuestionOptionsByLocale, getTranslatedQuestions } from "../../lib/survey-helpers"
import { buildAnswerSelections, canisterService } from "../../lib/canister-service"

// CORRECCIÓN: Nombre de interfaz actualizado para consistencia profesional
interface SurveyPageProps {
  onComplete: () => void
  onBack: () => void
}

// CORRECCIÓN: Nombre de la función cambiado de SurveySection a SurveyPage
export function SurveyPage({ onComplete, onBack }: SurveyPageProps) {
  const { locale, t } = useLocale()
  const { userIdToken, logout } = useAuth()
  const surveyQuestions = getTranslatedQuestions(locale)
  const optionSets = getQuestionOptionsByLocale(locale)

  const voteProgressSteps = [
    t.voteProgress.stepIdentity,
    t.voteProgress.stepDuplicate,
    t.voteProgress.stepRegister,
    t.voteProgress.stepFinalize,
  ]
  
  const [currentQuestionIndex, setCurrentQuestionIndex] = useState(0)
  const [answers, setAnswers] = useState<Record<number, string>>({})
  const [direction, setDirection] = useState(1) // 1 = forward, -1 = backward
  const [isSubmitting, setIsSubmitting] = useState(false)
  const [showVoteProgressModal, setShowVoteProgressModal] = useState(false)
  const [voteProgressStep, setVoteProgressStep] = useState(0)
  const [voteProgressStatus, setVoteProgressStatus] = useState<"running" | "success" | "error">("running")
  const [voteProgressError, setVoteProgressError] = useState<string | null>(null)

  const currentQuestion = surveyQuestions[currentQuestionIndex]
  const totalQuestions = surveyQuestions.length
  const progress = ((currentQuestionIndex + 1) / totalQuestions) * 100

  const handleSelectOption = useCallback((option: string) => {
    setAnswers(prev => ({
      ...prev,
      [currentQuestion.id]: option
    }))
  }, [currentQuestion.id])

  const openVoteProgress = useCallback(() => {
    setVoteProgressStep(0)
    setVoteProgressStatus("running")
    setVoteProgressError(null)
    setShowVoteProgressModal(true)
  }, [])

  const markVoteProgressError = useCallback((message?: string) => {
    setVoteProgressStatus("error")
    setVoteProgressError(message ?? t.voteProgress.genericError)
  }, [t.voteProgress.genericError])

  const startVoteProgressSimulation = useCallback(() => {
    return window.setInterval(() => {
      setVoteProgressStep(prev => (prev < 2 ? prev + 1 : prev))
    }, 850)
  }, [])

  const forceReloginForVote = useCallback(() => {
    // Marca una reautenticacion obligatoria para que landing abra el modal.
    sessionStorage.setItem("voxpopuli_force_relogin", "1")
    sessionStorage.setItem("voxpopuli_relogin_reason", "session_expired")
    logout()
    onBack()
  }, [logout, onBack])

  const handleNext = useCallback(async () => {
    const selectedOption = answers[currentQuestion.id]
    
    // Lógica de salto: Si selecciona "Ninguna"/"None"/"Cap" en P1, saltar a P8
    if (currentQuestion.skipTrigger && selectedOption === currentQuestion.skipTrigger && currentQuestion.skipTo) {
      const skipToIndex = surveyQuestions.findIndex(q => q.id === currentQuestion.skipTo)
      if (skipToIndex !== -1) {
        setDirection(1)
        setCurrentQuestionIndex(skipToIndex)
        return
      }
    }

    if (currentQuestionIndex < totalQuestions - 1) {
      setDirection(1)
      setCurrentQuestionIndex(prev => prev + 1)
    } else {
      // Enviar voto al canister
      setIsSubmitting(true)
      openVoteProgress()
      const progressTimerId = startVoteProgressSimulation()

      try {
        if (!userIdToken) {
          clearInterval(progressTimerId)
          setVoteProgressStep(0)
          markVoteProgressError(t.voteProgress.sessionExpired)
          await new Promise(resolve => setTimeout(resolve, 850))
          setShowVoteProgressModal(false)
          forceReloginForVote()
          return
        }

        const normalizedAnswers = buildAnswerSelections(answers, optionSets)
        const result = await canisterService.submitVote({
          surveyId: "ai-uoc-2024",
          idToken: userIdToken,
          answers: normalizedAnswers,
          timestamp: Date.now(),
        })

        if (result.success) {
          clearInterval(progressTimerId)
          setVoteProgressStep(3)
          setVoteProgressStatus("success")
          await new Promise(resolve => setTimeout(resolve, 700))
          setShowVoteProgressModal(false)
          onComplete()
        } else {
          if (result.message.startsWith("Autenticacion invalida:")) {
            clearInterval(progressTimerId)
            setVoteProgressStep(0)
            markVoteProgressError(t.voteProgress.sessionExpired)
            await new Promise(resolve => setTimeout(resolve, 850))
            setShowVoteProgressModal(false)
            forceReloginForVote()
            return
          }

          clearInterval(progressTimerId)
          setVoteProgressStep(2)
          markVoteProgressError(result.message)
        }
      } catch (error) {
        clearInterval(progressTimerId)
        setVoteProgressStep(1)
        markVoteProgressError()
        console.error("[SurveyPage] Error de conexión:", error)
      } finally {
        clearInterval(progressTimerId)
        setIsSubmitting(false)
      }
    }
  }, [answers, currentQuestion, currentQuestionIndex, forceReloginForVote, markVoteProgressError, onComplete, openVoteProgress, optionSets, startVoteProgressSimulation, surveyQuestions, t.voteProgress.sessionExpired, totalQuestions, userIdToken])

  const handlePrevious = useCallback(() => {
    if (currentQuestionIndex > 0) {
      setDirection(-1)
      setCurrentQuestionIndex(prev => prev - 1)
    }
  }, [currentQuestionIndex])

  const selectedOption = answers[currentQuestion.id]
  const canProceed = !!selectedOption

  const variants = {
    enter: (direction: number) => ({
      x: direction > 0 ? 100 : -100,
      opacity: 0
    }),
    center: {
      x: 0,
      opacity: 1
    },
    exit: (direction: number) => ({
      x: direction > 0 ? -100 : 100,
      opacity: 0
    })
  }

  // Format question counter text
  const questionCounterText = t.survey.questionOf
    .replace("{current}", String(currentQuestionIndex + 1))
    .replace("{total}", String(totalQuestions))

  const voteStepState = (index: number) => {
    if (voteProgressStatus === "success") {
      return "done"
    }

    if (voteProgressStatus === "error") {
      if (index < voteProgressStep) {
        return "done"
      }

      if (index == voteProgressStep) {
        return "error"
      }

      return "pending"
    }

    if (index < voteProgressStep) {
      return "done"
    }

    if (index == voteProgressStep) {
      return "running"
    }

    return "pending"
  }

  return (
    <section className="snap-section min-h-screen bg-background flex flex-col">
      {/* Header */}
      <header className="w-full border-b border-border/50 bg-card/80 backdrop-blur-sm sticky top-0 z-40">
        <div className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 py-4">
          <div className="flex items-center justify-between mb-3">
            <Button
              variant="ghost"
              size="sm"
              onClick={onBack}
              className="text-muted-foreground hover:text-foreground -ml-2"
            >
              <ArrowLeft className="w-4 h-4 mr-1" />
              {t.survey.back}
            </Button>
            <span className="text-sm text-muted-foreground">
              {questionCounterText}
            </span>
          </div>
          <Progress value={progress} className="h-2" />
        </div>
      </header>

      {/* Question Content */}
      <div className="flex-1 flex items-center justify-center px-4 py-8 overflow-y-auto">
        <div className="w-full max-w-2xl">
          <AnimatePresence mode="wait" custom={direction}>
            <motion.div
              key={currentQuestion.id}
              custom={direction}
              variants={variants}
              initial="enter"
              animate="center"
              exit="exit"
              transition={{ duration: 0.3, ease: "easeInOut" }}
              className="space-y-8"
            >
              <div className="text-center">
                <span className="inline-block px-3 py-1 bg-primary/10 text-primary text-sm font-medium rounded-full mb-4">
                  {t.survey.questionLabel} {currentQuestion.id}
                </span>
                <h2 className="text-2xl sm:text-3xl font-semibold text-foreground leading-snug text-balance">
                  {currentQuestion.text}
                </h2>
              </div>

              <div className="space-y-3">
                {currentQuestion.options.map((option, index) => (
                  <motion.button
                    key={option}
                    initial={{ opacity: 0, y: 10 }}
                    animate={{ opacity: 1, y: 0 }}
                    transition={{ delay: index * 0.05 }}
                    onClick={() => handleSelectOption(option)}
                    className={`w-full p-4 sm:p-5 rounded-xl border-2 text-left transition-all duration-200 ${
                      selectedOption === option
                        ? "border-primary bg-primary/5 text-foreground"
                        : "border-border bg-card hover:border-primary/30 hover:bg-muted/50 text-foreground"
                    }`}
                  >
                    <div className="flex items-center justify-between gap-4">
                      <span className="text-base sm:text-lg font-medium">{option}</span>
                      {selectedOption === option && (
                        <motion.div
                          initial={{ scale: 0 }}
                          animate={{ scale: 1 }}
                          transition={{ type: "spring", damping: 20, stiffness: 300 }}
                        >
                          <CheckCircle2 className="w-6 h-6 text-primary flex-shrink-0" />
                        </motion.div>
                      )}
                    </div>
                  </motion.button>
                ))}
              </div>
            </motion.div>
          </AnimatePresence>
        </div>
      </div>

      {/* Navigation */}
      <footer className="w-full border-t border-border/50 bg-card/80 backdrop-blur-sm mt-auto">
        <div className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 py-4">
          <div className="flex items-center justify-between gap-4">
            <Button
              variant="outline"
              onClick={handlePrevious}
              disabled={currentQuestionIndex === 0}
              className="min-w-[120px]"
            >
              <ChevronLeft className="w-4 h-4 mr-1" />
              {t.survey.previous}
            </Button>
            <Button
              onClick={handleNext}
              disabled={!canProceed || isSubmitting}
              className="min-w-[120px] bg-primary hover:bg-primary/90 text-primary-foreground"
            >
              {isSubmitting ? (
                <div className="animate-spin rounded-full h-4 w-4 border-2 border-primary-foreground/30 border-t-primary-foreground" />
              ) : currentQuestionIndex === totalQuestions - 1 ? (
                t.survey.submit
              ) : (
                <>
                  {t.survey.next}
                  <ChevronRight className="w-4 h-4 ml-1" />
                </>
              )}
            </Button>
          </div>
        </div>
      </footer>

      <Dialog open={showVoteProgressModal}>
        <DialogContent className="max-w-md" aria-describedby="vote-progress-description">
          <DialogHeader>
            <DialogTitle>{t.voteProgress.title}</DialogTitle>
            <DialogDescription id="vote-progress-description">
              {t.voteProgress.description}
            </DialogDescription>
          </DialogHeader>

          <div className="mt-4 space-y-3">
            {voteProgressSteps.map((stepLabel, index) => {
              const state = voteStepState(index)

              return (
                <div key={stepLabel} className="flex items-center gap-3 rounded-lg border border-border/60 bg-muted/30 px-3 py-2">
                  {state === "done" ? (
                    <CheckCircle2 className="h-5 w-5 flex-shrink-0 text-emerald-600" />
                  ) : state === "running" ? (
                    <div className="h-5 w-5 flex-shrink-0 animate-spin rounded-full border-2 border-primary/30 border-t-primary" />
                  ) : state === "error" ? (
                    <AlertCircle className="h-5 w-5 flex-shrink-0 text-destructive" />
                  ) : (
                    <div className="h-5 w-5 flex-shrink-0 rounded-full border border-border" />
                  )}

                  <span className={state === "pending" ? "text-sm text-muted-foreground" : "text-sm text-foreground"}>
                    {stepLabel}
                  </span>
                </div>
              )
            })}
          </div>

          {voteProgressStatus === "error" && voteProgressError ? (
            <div className="mt-4 space-y-3">
              <p className="rounded-lg border border-destructive/20 bg-destructive/5 px-3 py-2 text-sm text-destructive">
                {voteProgressError}
              </p>
              <div className="flex justify-end">
                <Button variant="outline" onClick={() => setShowVoteProgressModal(false)}>
                  {t.voteProgress.close}
                </Button>
              </div>
            </div>
          ) : null}
        </DialogContent>
      </Dialog>
    </section>
  )
}