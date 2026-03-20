
import { useState } from "react"
import { motion, AnimatePresence } from "framer-motion"
import { X, Mail, Shield, AlertCircle, CheckCircle2 } from "lucide-react"

// Componentes de UI (Carpeta src/components/ui)
import { Button } from "@/components/ui/button"

// Lógica y Contexto (Carpeta src/lib)
import { useLocale } from "@/lib/locale-context"
import { LoginError, type LoginIdentity, loginWithGoogle } from "@/lib/login"

interface LoginModalProps {
  isOpen: boolean
  onClose: () => void
  onSuccess: (identity: LoginIdentity) => void
  mode: "login" | "error"
}

export function LoginModal({ isOpen, onClose, onSuccess, mode }: LoginModalProps) {
  const { t } = useLocale()
  const [isLoading, setIsLoading] = useState(false)
  const [authError, setAuthError] = useState<string | null>(null)

  const handleGoogleLogin = async () => {
    setIsLoading(true)
    setAuthError(null)

    try {
      const identity = await loginWithGoogle()
      onSuccess(identity)
    } catch (error) {
      if (error instanceof LoginError && error.code === "domain_not_allowed") {
        setAuthError(t.login.domainError)
      } else {
        setAuthError(t.login.accessDeniedDescription)
      }
    } finally {
      setIsLoading(false)
    }
  }

  return (
    <AnimatePresence>
      {isOpen && (
        <>
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            onClick={onClose}
            className="fixed inset-0 bg-foreground/20 backdrop-blur-sm z-50"
          />
          
          <motion.div
            initial={{ opacity: 0, scale: 0.95, y: 20 }}
            animate={{ opacity: 1, scale: 1, y: 0 }}
            exit={{ opacity: 0, scale: 0.95, y: 20 }}
            className="fixed inset-0 flex items-center justify-center z-50 p-4"
          >
            <div className="bg-card rounded-xl shadow-2xl max-w-md w-full p-8 relative border border-border">
              <button
                onClick={onClose}
                className="absolute top-4 right-4 p-2 rounded-full hover:bg-muted transition-colors text-muted-foreground hover:text-foreground"
              >
                <X className="w-5 h-5" />
              </button>

              {mode === "login" ? (
                <>
                  <div className="text-center mb-8">
                    <div className="w-16 h-16 bg-primary/10 rounded-full flex items-center justify-center mx-auto mb-4">
                      <Shield className="w-8 h-8 text-primary" />
                    </div>
                    <h2 className="text-2xl font-semibold text-foreground mb-2">
                      {t.login.secureAccess}
                    </h2>
                    <p className="text-muted-foreground leading-relaxed">
                      {t.login.loginDescription}
                    </p>
                  </div>

                  <div className="space-y-4">
                    <Button
                      onClick={handleGoogleLogin}
                      disabled={isLoading}
                      className="w-full h-12 text-base font-medium bg-primary text-primary-foreground"
                    >
                      {isLoading ? (
                        <motion.div
                          animate={{ rotate: 360 }}
                          transition={{ duration: 1, repeat: Infinity, ease: "linear" }}
                          className="w-5 h-5 border-2 border-primary-foreground/30 border-t-primary-foreground rounded-full"
                        />
                      ) : (
                        <>
                          <Mail className="w-5 h-5 mr-2" />
                          {t.login.continueWithGoogle}
                        </>
                      )}
                    </Button>

                    <div className="flex items-start gap-3 p-4 bg-accent/50 rounded-lg">
                      <CheckCircle2 className="w-5 h-5 text-primary mt-0.5 flex-shrink-0" />
                      <p className="text-sm text-muted-foreground leading-relaxed">
                        {t.login.privacyNoteParts.before}
                        <span className="font-semibold text-foreground mx-1">
                           {t.login.privacyNoteParts.anonymousIdTerm}
                        </span>
                        {t.login.privacyNoteParts.after}
                      </p>
                    </div>

                    {authError ? (
                      <p className="text-sm text-destructive leading-relaxed">{authError}</p>
                    ) : null}
                  </div>
                </>
              ) : (
                <>
                  <div className="text-center mb-8">
                    <div className="w-16 h-16 bg-destructive/10 rounded-full flex items-center justify-center mx-auto mb-4">
                      <AlertCircle className="w-8 h-8 text-destructive" />
                    </div>
                    <h2 className="text-2xl font-semibold text-foreground mb-2">
                      {t.login.accessDenied}
                    </h2>
                    <p className="text-muted-foreground leading-relaxed">
                      {t.login.accessDeniedDescription}
                    </p>
                  </div>
                  <Button onClick={onClose} variant="outline" className="w-full h-12">
                    {t.login.close}
                  </Button>
                </>
              )}
            </div>
          </motion.div>
        </>
      )}
    </AnimatePresence>
  )
}