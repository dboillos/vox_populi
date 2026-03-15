"use client"

import { useEffect, useState } from "react"
import { motion } from "framer-motion"
import { ArrowLeft, Users, TrendingUp, Clock, Download } from "lucide-react"
// Usamos los alias @ para evitar errores de ruta
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { canisterService, type AggregatedResults, type RawResponse } from "@/lib/canister-service"
import { useLocale } from "@/lib/locale-context"
import { getQuestionOptionsByLocale, getTranslatedResultsData } from "@/lib/survey-helpers"
import { useIsMobile } from "@/hooks/use-mobile"
import {
  PieChart,
  Pie,
  Cell,
  RadarChart,
  PolarGrid,
  PolarAngleAxis,
  PolarRadiusAxis,
  Radar,
  BarChart,
  Bar,
  XAxis,
  YAxis,
  Tooltip,
  Legend
} from "recharts"

interface ResultsPageProps {
  onBack: () => void
}

const COLORS = [
  "oklch(0.50 0.18 240)",
  "oklch(0.60 0.14 180)",
  "oklch(0.55 0.12 150)",
  "oklch(0.65 0.16 100)",
  "oklch(0.50 0.10 280)",
  "oklch(0.70 0.05 240)"
]

const EMPTY_RESULTS: AggregatedResults = {
  totalVotes: 0,
  blockchainTrustPercentage: 0,
  averageHoursSaved: 0,
  toolDistribution: [],
  impactRadar: [],
  securityMatrix: [],
  icpPreference: 0,
}

function generateCSV(rawResponses: RawResponse[], questionOptions: Record<number, string[]>): string {
  const headers = [
    "Numero",
    "Voter ID",
    "Timestamp",
    "Pregunta 1 - Herramienta IA",
    "Pregunta 2 - Fase académica",
    "Pregunta 3 - Horas ahorradas",
    "Pregunta 4 - Calidad entregas (1-5)",
    "Pregunta 5 - Uso ético",
    "Pregunta 6 - Esfuerzo aprendizaje",
    "Pregunta 7 - Actitud profesores",
    "Pregunta 8 - Confianza identificación",
    "Pregunta 9 - Seguridad ID anónimo",
    "Pregunta 10 - Inmutabilidad blockchain",
    "Pregunta 11 - Blockchain necesaria",
    "Pregunta 12 - ICP vs Google Forms"
  ]

  const resolveAnswer = (response: RawResponse, questionId: number) => {
    const answer = response.answers.find((item) => item.questionId === questionId)
    if (!answer) {
      return ""
    }

    return questionOptions[questionId]?.[answer.optionIndex] ?? ""
  }
  
  const rows = rawResponses.map((response) => [
    response.numero,
    response.voterId,
    new Date(response.timestamp).toISOString(),
    resolveAnswer(response, 1),
    resolveAnswer(response, 2),
    resolveAnswer(response, 3),
    resolveAnswer(response, 4),
    resolveAnswer(response, 5),
    resolveAnswer(response, 6),
    resolveAnswer(response, 7),
    resolveAnswer(response, 8),
    resolveAnswer(response, 9),
    resolveAnswer(response, 10),
    resolveAnswer(response, 11),
    resolveAnswer(response, 12)
  ].join(";"))
  
  return [headers.join(";"), ...rows].join("\n")
}

function downloadCSV(filename: string, rawResponses: RawResponse[], questionOptions: Record<number, string[]>) {
  const csv = generateCSV(rawResponses, questionOptions)
  const blob = new Blob(["\uFEFF" + csv], { type: "text/csv;charset=utf-8;" })
  const url = URL.createObjectURL(blob)
  const link = document.createElement("a")
  link.href = url
  link.download = `${filename}_${new Date().toISOString().split("T")[0]}.csv`
  document.body.appendChild(link)
  link.click()
  document.body.removeChild(link)
  URL.revokeObjectURL(url)
}

// Cambiado de ResultsSection a ResultsPage para coincidir con AppRoutes
export function ResultsPage({ onBack }: ResultsPageProps) {
  const { locale, t } = useLocale()
  const isMobile = useIsMobile()
  const [results, setResults] = useState<AggregatedResults>(EMPTY_RESULTS)
  const [rawResponses, setRawResponses] = useState<RawResponse[]>([])
  const [isLoading, setIsLoading] = useState(true)
  const questionOptions = getQuestionOptionsByLocale(locale)
  const translatedData = getTranslatedResultsData(locale, results)

  useEffect(() => {
    let isMounted = true

    const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms))

    const loadResults = async () => {
      setIsLoading(true)

      try {
        let lastError: unknown = null
        let aggregatedResults: AggregatedResults | null = null
        let responses: RawResponse[] | null = null

        // Reintento corto para absorber errores transitorios de inicializacion en recarga dura.
        for (let attempt = 1; attempt <= 2; attempt += 1) {
          try {
            const result = await Promise.all([
              canisterService.getAggregatedResults("ai-uoc-2024"),
              canisterService.getRawResponses("ai-uoc-2024"),
            ])
            aggregatedResults = result[0]
            responses = result[1]
            break
          } catch (error) {
            lastError = error
            if (attempt < 2) {
              await sleep(300)
            }
          }
        }

        if (!aggregatedResults || !responses) {
          throw lastError ?? new Error("No se pudieron cargar resultados")
        }

        if (!isMounted) {
          return
        }

        setResults(aggregatedResults)
        setRawResponses(responses)
      } catch (error) {
        console.error("[ResultsPage] No se pudieron cargar los resultados", error)
        if (isMounted) {
          setResults(EMPTY_RESULTS)
          setRawResponses([])
        }
      } finally {
        if (isMounted) {
          setIsLoading(false)
        }
      }
    }

    void loadResults()

    return () => {
      isMounted = false
    }
  }, [])
  
  const handleDownloadCSV = () => {
    downloadCSV(t.results.csvFilename, rawResponses, questionOptions)
  }

  const { totalVotes, blockchainTrustPercentage, averageHoursSaved, icpPreference } = results
  const toolDistribution = translatedData.toolDistribution
  const chartWidth = isMobile ? 300 : 460

  return (
    <div className="min-h-screen bg-background flex flex-col">
      {/* Header */}
      <header className="w-full border-b border-border/50 bg-card/80 backdrop-blur-sm sticky top-0 z-40">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 h-16 flex items-center justify-between">
          <Button
            variant="ghost"
            size="sm"
            onClick={onBack}
            className="text-muted-foreground hover:text-foreground transition-colors"
          >
            <ArrowLeft className="w-4 h-4 mr-2" />
            {t.results.backToHome}
          </Button>
          <h1 className="text-lg font-semibold text-foreground">{t.results.title}</h1>
          <Button
            variant="outline"
            size="sm"
            onClick={handleDownloadCSV}
            disabled={rawResponses.length === 0}
            className="gap-2"
          >
            <Download className="w-4 h-4" />
            {t.results.downloadCSV}
          </Button>
        </div>
      </header>

      <main className="flex-1 max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-8 overflow-y-auto">
        {/* KPIs */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.5 }}
          className="grid grid-cols-1 sm:grid-cols-3 gap-6"
        >
          <Card className="border-primary/20 bg-card">
            <CardContent className="pt-6">
              <div className="flex items-center gap-4">
                <div className="w-12 h-12 bg-primary/10 rounded-xl flex items-center justify-center text-primary">
                  <Users className="w-6 h-6" />
                </div>
                <div>
                  <p className="text-sm text-muted-foreground">{t.results.totalVotes}</p>
                  <p className="text-3xl font-bold">{isLoading ? "..." : totalVotes.toLocaleString()}</p>
                </div>
              </div>
            </CardContent>
          </Card>

          <Card className="border-primary/20 bg-card">
            <CardContent className="pt-6">
              <div className="flex items-center gap-4">
                <div className="w-12 h-12 bg-primary/10 rounded-xl flex items-center justify-center text-primary">
                  <TrendingUp className="w-6 h-6" />
                </div>
                <div>
                  <p className="text-sm text-muted-foreground">{t.results.blockchainTrust}</p>
                  <p className="text-3xl font-bold">{isLoading ? "..." : `${blockchainTrustPercentage}%`}</p>
                </div>
              </div>
            </CardContent>
          </Card>

          <Card className="border-primary/20 bg-card">
            <CardContent className="pt-6">
              <div className="flex items-center gap-4">
                <div className="w-12 h-12 bg-primary/10 rounded-xl flex items-center justify-center text-primary">
                  <Clock className="w-6 h-6" />
                </div>
                <div>
                  <p className="text-sm text-muted-foreground">{t.results.avgHoursSaved}</p>
                  <p className="text-3xl font-bold">{isLoading ? "..." : `${averageHoursSaved.toFixed(1)}h`}</p>
                </div>
              </div>
            </CardContent>
          </Card>
        </motion.div>

        {/* Charts Row 1 */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <Card>
            <CardHeader>
              <CardTitle className="text-lg font-semibold">{t.results.toolEcosystem}</CardTitle>
            </CardHeader>
            <CardContent className="h-[300px] min-w-0">
              <div className="w-full h-full flex flex-col items-center justify-center gap-2 overflow-x-auto">
                <PieChart width={chartWidth} height={220}>
                  <Pie
                    data={toolDistribution}
                    innerRadius={60}
                    outerRadius={100}
                    paddingAngle={2}
                    dataKey="value"
                    label={false}
                    labelLine={false}
                  >
                    {toolDistribution.map((_, index) => (
                      <Cell key={`cell-${index}`} fill={COLORS[index % COLORS.length]} />
                    ))}
                  </Pie>
                  <Tooltip contentStyle={{ backgroundColor: 'var(--card)', border: '1px solid var(--border)', borderRadius: '8px' }} />
                </PieChart>
                <div className="w-full grid grid-cols-2 gap-x-4 gap-y-1 px-2 text-xs">
                  {toolDistribution
                    .filter((item) => item.value > 0)
                    .map((item, index) => (
                      <div key={item.name} className="flex items-center gap-2 text-muted-foreground truncate">
                        <span
                          className="inline-block w-2.5 h-2.5 rounded-full shrink-0"
                          style={{ backgroundColor: COLORS[index % COLORS.length] }}
                        />
                        <span className="truncate">{item.name}: {item.value}%</span>
                      </div>
                    ))}
                </div>
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle className="text-lg font-semibold">{t.results.aiImpact}</CardTitle>
            </CardHeader>
            <CardContent className="h-[300px] min-w-0 overflow-x-auto">
              <div className="w-fit mx-auto">
                <RadarChart width={chartWidth} height={280} data={translatedData.impactRadar}>
                  <PolarGrid stroke="var(--border)" />
                  <PolarAngleAxis dataKey="axis" tick={{ fill: 'var(--muted-foreground)', fontSize: 12 }} />
                  <PolarRadiusAxis angle={30} domain={[0, 5]} />
                  <Radar
                    name={t.results.score}
                    dataKey="value"
                    stroke={COLORS[0]}
                    fill={COLORS[0]}
                    fillOpacity={0.3}
                  />
                  <Tooltip contentStyle={{ backgroundColor: 'var(--card)', border: '1px solid var(--border)', borderRadius: '8px' }} />
                </RadarChart>
              </div>
            </CardContent>
          </Card>
        </div>

        {/* Charts Row 2 */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <Card>
            <CardHeader>
              <CardTitle className="text-lg font-semibold">{t.results.securityMatrix}</CardTitle>
            </CardHeader>
            <CardContent className="h-[300px] min-w-0 overflow-x-auto">
              <div className="w-fit mx-auto">
                <BarChart width={chartWidth} height={280} data={translatedData.securityMatrix} layout="vertical">
                  <XAxis type="number" domain={[0, 100]} />
                  <YAxis type="category" dataKey="category" width={150} tick={{ fontSize: 11 }} />
                  <Tooltip contentStyle={{ backgroundColor: 'var(--card)', border: '1px solid var(--border)', borderRadius: '8px' }} />
                  <Legend />
                  <Bar dataKey="confia" name={t.results.trusts} stackId="a" fill={COLORS[0]} />
                  <Bar dataKey="neutral" name={t.results.neutral} stackId="a" fill={COLORS[3]} />
                  <Bar dataKey="desconfia" name={t.results.distrusts} stackId="a" fill={COLORS[4]} />
                </BarChart>
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle className="text-lg font-semibold">{t.results.digitalSovereignty}</CardTitle>
            </CardHeader>
            <CardContent className="flex flex-col items-center justify-center h-[300px]">
              <div className="w-full max-w-xs space-y-4">
                <div className="h-4 bg-muted rounded-full overflow-hidden">
                  <motion.div
                    initial={{ width: 0 }}
                    animate={{ width: `${icpPreference}%` }}
                    transition={{ duration: 1, ease: "easeOut" }}
                    className="h-full bg-primary"
                  />
                </div>
                <div className="flex justify-between text-xs text-muted-foreground font-bold">
                  <span>{t.results.googleForms}</span>
                  <span>{t.results.icp}</span>
                </div>
              </div>
              <div className="text-center mt-8">
                <p className="text-5xl font-bold text-primary">{icpPreference}%</p>
                <p className="text-muted-foreground mt-2">{t.results.preferICP}</p>
              </div>
            </CardContent>
          </Card>
        </div>
      </main>
    </div>
  )
}