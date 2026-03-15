import { motion } from "framer-motion"
import { Shield } from "lucide-react"
import { Button } from "../../components/ui/button"
import { useLocale } from "../../lib/locale-context"

export function HeroSection({ onAudit }: { onAudit: () => void }) {
  const { t } = useLocale()
  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      className="text-center py-12 lg:py-16 px-4"
    >
      <h2 className="text-3xl sm:text-4xl lg:text-5xl font-semibold mb-4 text-balance">
        {t.landing.heroTitle}
      </h2>
      <p className="text-lg sm:text-xl text-muted-foreground max-w-2xl mx-auto mb-6">
        {t.landing.heroDescription}
      </p>
      <Button onClick={onAudit} variant="outline" className="border-primary/30 text-primary">
        <Shield className="w-4 h-4 mr-2" />
        {t.surveyCard.audit}
      </Button>
    </motion.div>
  )
}