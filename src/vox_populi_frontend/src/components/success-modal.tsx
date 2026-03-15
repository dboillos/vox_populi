

import { motion, AnimatePresence } from "framer-motion"
import { CheckCircle2, BarChart3, Home, X } from "lucide-react"

// Usando el alias @ que apunta a la raíz de /src
import { Button } from "@/components/ui/button"
import { InfoTerm } from "@/components/layout/info-term"
import { useLocale } from "@/lib/locale-context"

interface SuccessModalProps {
  isOpen: boolean
  onClose: () => void
  onViewResults: () => void
  onBackHome: () => void
}

export function SuccessModal({ isOpen, onClose, onViewResults, onBackHome }: SuccessModalProps) {
  const { t } = useLocale()

  return (
    <AnimatePresence>
      {isOpen && (
        <>
          {/* Backdrop */}
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="fixed inset-0 bg-foreground/20 backdrop-blur-sm z-50"
          />
          
          {/* Modal */}
          <motion.div
            initial={{ opacity: 0, scale: 0.95, y: 20 }}
            animate={{ opacity: 1, scale: 1, y: 0 }}
            exit={{ opacity: 0, scale: 0.95, y: 20 }}
            transition={{ type: "spring", damping: 25, stiffness: 300 }}
            className="fixed inset-0 flex items-center justify-center z-50 p-4"
          >
            <div className="bg-card rounded-xl shadow-2xl max-w-md w-full p-8 relative border border-border">
              {/* Close button */}
              <button
                onClick={onClose}
                className="absolute top-4 right-4 p-2 rounded-full hover:bg-muted transition-colors text-muted-foreground hover:text-foreground"
                aria-label={t.login.close}
              >
                <X className="w-5 h-5" />
              </button>

              <div className="text-center mb-8">
                <motion.div
                  initial={{ scale: 0 }}
                  animate={{ scale: 1 }}
                  transition={{ type: "spring", damping: 15, stiffness: 200, delay: 0.2 }}
                  className="w-20 h-20 bg-primary/10 rounded-full flex items-center justify-center mx-auto mb-4"
                >
                  <CheckCircle2 className="w-10 h-10 text-primary" />
                </motion.div>
                <h2 className="text-2xl font-semibold text-foreground mb-2">
                  {t.success.voteRegistered}
                </h2>
                <p className="text-muted-foreground leading-relaxed">
                  {t.success.voteDescription}
                </p>
              </div>

              <div className="space-y-3">
                <Button
                  onClick={onViewResults}
                  className="w-full h-12 text-base font-medium bg-primary hover:bg-primary/90 text-primary-foreground"
                >
                  <BarChart3 className="w-5 h-5 mr-2" />
                  {t.success.viewResults}
                </Button>
                
                <Button
                  onClick={onBackHome}
                  variant="outline"
                  className="w-full h-12 text-base font-medium"
                >
                  <Home className="w-5 h-5 mr-2" />
                  {t.success.backToHome}
                </Button>
              </div>

              <div className="mt-6 p-4 bg-accent/50 rounded-lg">
                <p className="text-xs text-muted-foreground text-center">
                  {t.success.privacyNoteParts.before}
                  <InfoTerm 
                    term={t.success.privacyNoteParts.anonymousIdTerm} 
                    definition={t.glossary.anonymousId} 
                    showIcon={false}
                    className="text-foreground font-medium"
                  />
                  {t.success.privacyNoteParts.after}
                </p>
              </div>
            </div>
          </motion.div>
        </>
      )}
    </AnimatePresence>
  )
}
