

import { motion } from "framer-motion"
import { Vote, BarChart3, Clock, Users } from "lucide-react"

// Componentes de UI (Carpeta src/components/ui)
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"

// Lógica y Contexto (Carpeta src/lib)
import { useLocale } from "@/lib/locale-context"

interface Survey {
  id: string
  title: string
  description: string
  status: "active" | "upcoming" | "closed"
  votes?: number
  deadline?: string
}

interface SurveyCardProps {
  survey: Survey
  onVote: () => void
  onResults: () => void
  index: number
}

export function SurveyCard({ survey, onVote, onResults, index }: SurveyCardProps) {
  const { t } = useLocale()
  const isActive = survey.status === "active"
  const isUpcoming = survey.status === "upcoming"

  return (
    <motion.div
      initial={{ opacity: 0, y: 30 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.5, delay: index * 0.1 }}
    >
      <Card 
        className={`relative overflow-hidden transition-all duration-300 ${
          isActive 
            ? "border-primary/30 shadow-lg hover:shadow-xl bg-card" 
            : "border-border/50 bg-muted/30 opacity-70"
        }`}
      >
        <CardHeader className="pb-4">
          {/* Status badge - inline above title, aligned right */}
          <div className="mb-3 flex justify-end">
            {isActive ? (
              <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-primary/10 text-primary text-sm font-medium">
                <span className="w-2 h-2 bg-primary rounded-full animate-pulse" />
                {t.surveyCard.active}
              </span>
            ) : (
              <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-muted text-muted-foreground text-sm font-medium">
                <Clock className="w-3.5 h-3.5" />
                {t.surveyCard.upcoming}
              </span>
            )}
          </div>
          <CardTitle className={`text-xl font-semibold ${isUpcoming ? "text-muted-foreground" : "text-foreground"}`}>
            {survey.title}
          </CardTitle>
          <CardDescription className="text-muted-foreground leading-relaxed mt-2">
            {survey.description}
          </CardDescription>
        </CardHeader>

        <CardContent className="space-y-4">
          {isActive && (
            <div className="flex items-center gap-4 text-sm text-muted-foreground">
              <div className="flex items-center gap-1.5">
                <Users className="w-4 h-4" />
                <span>{survey.votes} {t.surveyCard.votes}</span>
              </div>
              <div className="flex items-center gap-1.5">
                <Clock className="w-4 h-4" />
                <span>{t.surveyCard.until} {survey.deadline}</span>
              </div>
            </div>
          )}

          <div className={`flex flex-wrap gap-3 pt-2 ${isUpcoming ? "opacity-50 pointer-events-none" : ""}`}>
            <Button
              onClick={onVote}
              disabled={isUpcoming}
              className="flex-1 min-w-[120px] bg-primary hover:bg-primary/90 text-primary-foreground"
            >
              <Vote className="w-4 h-4 mr-2" />
              {t.surveyCard.vote}
            </Button>
            <Button
              onClick={onResults}
              disabled={isUpcoming}
              variant="outline"
              className="flex-1 min-w-[120px] border-primary/30 text-primary hover:bg-primary/5"
            >
              <BarChart3 className="w-4 h-4 mr-2" />
              {t.surveyCard.viewResults}
            </Button>
          </div>
        </CardContent>
      </Card>
    </motion.div>
  )
}
