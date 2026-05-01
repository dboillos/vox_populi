
import { useEffect, useState } from "react"
import { motion } from "framer-motion"
import { ArrowLeft, ExternalLink, Hash, Cpu, Copy, Check, AlertCircle } from "lucide-react"

import { Button } from "../../components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "../../components/ui/card"
import { useLocale } from "../../lib/locale-context"
import { InfoTerm } from "../../components/layout/info-term"
import { Principal } from "@icp-sdk/core/principal"
import { canisterService } from "../../lib/canister-service"
import { canisterId as backendCanisterId } from "declarations/vox_populi_backend"

const frontendCanisterId = (import.meta.env.CANISTER_ID_VOX_POPULI_FRONTEND as string || "").trim()

// CORRECCIÓN: Nombre de interfaz coherente
interface AuditPageProps {
  onBack: () => void
}

type VerifyStep = {
  title: string
  description: string
  command?: string
}

type CanisterAuditRow = {
  key: string
  name: string
  canisterId: string
  moduleHash: string
}

export function AuditPage({ onBack }: AuditPageProps) {
  const { t } = useLocale()
  const [copiedCommand, setCopiedCommand] = useState<string | null>(null)

  // Cargamos auditData on-chain del backend (sin mocks).
  const [backendAuditData, setBackendAuditData] = useState<{
    canisterId: string
    wasmModuleHash: string
    codeVersion: string
  } | null>(null)
  const [frontendModuleHash, setFrontendModuleHash] = useState<string | null>(null)
  const [frontendAssetHashes, setFrontendAssetHashes] = useState<Array<{ file: string; hash: string }>>([])
  const [isBackendAuditLoading, setIsBackendAuditLoading] = useState(true)
  const [isFrontendHashLoading, setIsFrontendHashLoading] = useState(true)
  const [isFrontendAssetsLoading, setIsFrontendAssetsLoading] = useState(true)
  const [subnetId, setSubnetId] = useState<string | null>(null)

  // Recuperacion inicial del backend para version de codigo y metadatos disponibles.
  useEffect(() => {
    void canisterService.getAuditData()
      .then((data) => setBackendAuditData(data))
      .catch((error) => {
        console.error("[AuditPage] No se pudieron cargar metadatos de auditoria", error)
        setBackendAuditData(null)
      })
      .finally(() => setIsBackendAuditLoading(false))

    if (frontendCanisterId) {
      void canisterService.getModuleHash(Principal.fromText(frontendCanisterId))
        .then((hash) => setFrontendModuleHash(/^[0-9a-f]{64}$/.test(hash) ? hash : null))
        .catch(() => setFrontendModuleHash(null))
        .finally(() => setIsFrontendHashLoading(false))

      // Para auditoría, los hashes de assets deben reflejar SIEMPRE mainnet,
      // incluso cuando el frontend se está ejecutando en localhost.
      void canisterService.getFrontendAssetHashes(frontendCanisterId, { host: "https://ic0.app" })
        .then((entries) => setFrontendAssetHashes(entries))
        .catch(() => setFrontendAssetHashes([]))
        .finally(() => setIsFrontendAssetsLoading(false))
    } else {
      setIsFrontendHashLoading(false)
      setIsFrontendAssetsLoading(false)
    }

    // Obtener el subnet ID via IC public API usando siempre el canister ID de mainnet
    const icCanisterId =
      (import.meta.env.VITE_BACKEND_CANISTER_ID_IC as string || "").trim() || backendCanisterId
    if (icCanisterId) {
      fetch(`https://ic-api.internetcomputer.org/api/v3/canisters/${icCanisterId}`)
        .then((res) => res.ok ? res.json() : Promise.reject(res.status))
        .then((data: { subnet_id?: string }) => {
          if (data?.subnet_id) setSubnetId(data.subnet_id)
        })
        .catch(() => setSubnetId(null))
    }
  }, [])

  const runtimeHost = typeof window !== "undefined" ? window.location.hostname : ""
  const isLocalRuntime = runtimeHost === "127.0.0.1" || runtimeHost.endsWith(".localhost") || runtimeHost === "localhost"
  const network = !isLocalRuntime && import.meta.env.DFX_NETWORK === "ic" ? "ic" : "local"
  const githubRepoUrl = import.meta.env.VITE_GITHUB_REPO_URL || "https://github.com/dboillos/vox_populi"
  const rawReleaseTag = (import.meta.env.VITE_GITHUB_RELEASE_TAG || "").trim()
  const githubTagRef = (import.meta.env.VITE_GITHUB_GIT_TAG_AUTO || "").trim()
  const githubCommitRef = (import.meta.env.VITE_GITHUB_COMMIT_SHORT_AUTO || "").trim()
  const githubReleaseRef =
    rawReleaseTag && rawReleaseTag !== "<release-tag>" && rawReleaseTag !== "<release_tag>"
      ? rawReleaseTag
      : import.meta.env.VITE_GITHUB_RELEASE_TAG_AUTO || "main"
  const githubTagDisplay = githubTagRef || "No disponible"
  const githubCommitDisplay = githubCommitRef || "No disponible"
  const githubReleaseDisplay = githubTagRef || githubReleaseRef || "No disponible"
  const githubTagUrl = githubTagRef ? `${githubRepoUrl}/tree/${githubTagRef}` : `${githubRepoUrl}/tags`
  const githubCommitUrl = githubCommitRef ? `${githubRepoUrl}/commit/${githubCommitRef}` : `${githubRepoUrl}/commits`
  const githubReleaseUrl = githubTagRef ? `${githubRepoUrl}/releases/tag/${githubTagRef}` : `${githubRepoUrl}/releases`

  const embeddedMainnetBackendId = (import.meta.env.VITE_BACKEND_CANISTER_ID_IC as string || "").trim()
  const backendId =
    (backendAuditData?.canisterId || "").trim() ||
    embeddedMainnetBackendId ||
    backendCanisterId ||
    (isBackendAuditLoading ? t.audit.loading : "No disponible")
  const frontendId = frontendCanisterId || (isFrontendHashLoading ? t.audit.loading : "No disponible")

  const verifyTexts = t.audit.verify

  const backendModuleHash = isBackendAuditLoading
    ? t.audit.loading
    : /^[0-9a-f]{64}$/.test(backendAuditData?.wasmModuleHash ?? "")
      ? backendAuditData!.wasmModuleHash
      : verifyTexts.moduleHashUnavailable
  const codeVersion = isBackendAuditLoading
    ? t.audit.loading
    : githubReleaseDisplay || backendAuditData?.codeVersion || "No disponible"

  const canisterRows: CanisterAuditRow[] = [
    {
      key: "backend",
      name: "vox_populi_backend",
      canisterId: backendId,
      moduleHash: backendModuleHash,
    },
    {
      key: "frontend",
      name: "vox_populi_frontend",
      canisterId: frontendId,
      moduleHash: isFrontendHashLoading
        ? t.audit.loading
        : frontendModuleHash ?? verifyTexts.moduleHashUnavailable,
    },
  ]

  const verifySteps: VerifyStep[] = [
    {
      title: verifyTexts.step1,
      description: verifyTexts.step1Desc,
      command: verifyTexts.step1Command,
    },
    {
      title: verifyTexts.step2,
      description: verifyTexts.step2Desc,
      command: verifyTexts.step2CommandTemplate
        .replaceAll("{repoUrl}", githubRepoUrl)
        .replaceAll("{releaseTag}", githubReleaseDisplay),
    },
    {
      title: verifyTexts.step3,
      description: verifyTexts.step3Desc,
      command: verifyTexts.step3Command
        .replaceAll("{repoUrl}", githubRepoUrl)
        .replaceAll("{releaseTag}", githubReleaseDisplay),
    },
  ]

  const copyToClipboard = async (value: string) => {
    try {
      await navigator.clipboard.writeText(value)
      setCopiedCommand(value)
      setTimeout(() => setCopiedCommand(null), 1400)
    } catch (error) {
      console.error("[AuditPage] No se pudo copiar al portapapeles", error)
    }
  }

  const subnetUrl = subnetId
    ? `https://dashboard.internetcomputer.org/network/subnets/${subnetId}`
    : `https://dashboard.internetcomputer.org/network/subnets`

  const verificationLinks = [
    {
      name: t.audit.icDashboard,
      url: "https://dashboard.internetcomputer.org/",
      description: t.audit.icDashboardDesc
    },
    {
      name: t.audit.icScan,
      url: "https://www.icpexplorer.org/#/",
      description: t.audit.icScanDesc
    },
    {
      name: t.audit.icSubnet,
      url: subnetUrl,
      description: t.audit.icSubnetDesc
    }
  ]

  return (
    <section className="snap-section min-h-screen bg-background overflow-y-auto">
      {/* Header */}
      <header className="w-full border-b border-border/50 bg-card/80 backdrop-blur-sm sticky top-0 z-40">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-4">
          <div className="flex items-center justify-between">
            <Button
              variant="ghost"
              size="sm"
              onClick={onBack}
              className="text-muted-foreground hover:text-foreground -ml-2"
            >
              <ArrowLeft className="w-4 h-4 mr-1" />
              {t.audit.backToHome}
            </Button>
            <h1 className="text-lg font-semibold text-foreground">{t.audit.title}</h1>
            <div className="w-24" /> {/* Spacer */}
          </div>
        </div>
      </header>

      <div className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-8">
        {/* Intro */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.5 }}
          className="text-center"
        >
          <div className="w-16 h-16 bg-primary/10 rounded-full flex items-center justify-center mx-auto mb-4">
            <Cpu className="w-8 h-8 text-primary" />
          </div>
          <h2 className="text-2xl sm:text-3xl font-semibold text-foreground mb-3 text-balance">
            {t.audit.transparencyTitle}
          </h2>
          <p className="text-muted-foreground max-w-xl mx-auto leading-relaxed text-pretty">
            {t.audit.transparencyDescription.split("Internet Computer").map((part, i, arr) => (
              <span key={i}>
                {part}
                {i < arr.length - 1 && (
                  <InfoTerm 
                    term="Internet Computer" 
                    definition={t.glossary.icp}
                    showIcon={false}
                  />
                )}
              </span>
            ))}
          </p>
        </motion.div>

        {/* Tabla de canisters auditables */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.5, delay: 0.25 }}
        >
          <Card className="border-border bg-card">
            <CardHeader>
              <CardTitle className="text-lg font-semibold text-foreground flex items-center gap-2">
                <Hash className="w-5 h-5 text-primary" />
                {t.audit.canistersAndHashes}
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              {canisterRows.map((row) => (
                <div key={row.key} className="rounded-lg border border-border p-4 space-y-2">
                  <p className="font-semibold text-foreground">{row.name}</p>
                  <p className="text-sm text-muted-foreground break-all">
                    <span className="font-medium text-foreground">{t.audit.canisterIdLabel}:</span> {row.canisterId}
                  </p>
                  <p className="text-sm text-muted-foreground break-all">
                    <span className="font-medium text-foreground">{t.audit.onChainModuleHashLabel}:</span> {row.moduleHash}
                  </p>
                  {row.key === 'frontend' && (
                    <div className="mt-4 pt-4 border-t border-border space-y-3">
                      <div className="flex gap-2">
                        <AlertCircle className="w-4 h-4 text-amber-600 dark:text-amber-400 flex-shrink-0 mt-0.5" />
                        <p className="text-xs text-muted-foreground leading-relaxed">
                          {t.audit.moduleHashNote}
                        </p>
                      </div>
                      <div className="mt-3 pt-3 border-t border-border space-y-2">
                        <p className="text-xs font-semibold text-foreground">{t.audit.frontendAssetsLabel}</p>
                        <p className="text-xs text-muted-foreground">{t.audit.frontendAssetsDesc}</p>
                        <div className="overflow-x-auto">
                          <table className="w-full text-xs">
                            <thead>
                              <tr className="border-b border-border/50">
                                <th className="text-left py-2 px-2 font-semibold text-foreground">{t.audit.assetFileLabel}</th>
                                <th className="text-left py-2 px-2 font-semibold text-foreground">{t.audit.assetHashLabel}</th>
                              </tr>
                            </thead>
                            <tbody className="divide-y divide-border/50">
                              {isFrontendAssetsLoading ? (
                                <tr>
                                  <td className="py-1.5 px-2 text-muted-foreground text-xs" colSpan={2}>{t.audit.loading}</td>
                                </tr>
                              ) : frontendAssetHashes.length > 0 ? (
                                frontendAssetHashes.map((asset) => (
                                  <tr key={asset.file} className="hover:bg-muted/30 transition-colors">
                                    <td className="py-1.5 px-2 text-muted-foreground font-mono text-xs break-all">{asset.file}</td>
                                    <td className="py-1.5 px-2 text-muted-foreground font-mono text-xs break-all">{asset.hash}</td>
                                  </tr>
                                ))
                              ) : (
                                <tr>
                                  <td className="py-1.5 px-2 text-muted-foreground text-xs" colSpan={2}>No disponible</td>
                                </tr>
                              )}
                            </tbody>
                          </table>
                        </div>
                      </div>
                    </div>
                  )}
                </div>
              ))}
            </CardContent>
          </Card>
        </motion.div>

        {/* Bloque didactico: Como verificar */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.5, delay: 0.35 }}
        >
          <Card className="border-primary/20 bg-accent/20">
            <CardHeader>
              <CardTitle className="text-lg font-semibold text-foreground">{verifyTexts.title}</CardTitle>
              <CardDescription>{verifyTexts.intro}</CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="rounded-lg border border-border bg-card p-4 space-y-2">
                <p className="text-sm text-muted-foreground">
                  <span className="font-medium text-foreground">{t.audit.runningAppVersionLabel}:</span> {codeVersion}
                </p>
                <p className="text-sm text-muted-foreground">
                  <span className="font-medium text-foreground">{verifyTexts.repo}:</span>{" "}
                  <a
                    href={githubRepoUrl}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-primary underline-offset-4 hover:underline"
                  >
                    {githubRepoUrl}
                  </a>
                </p>
                <p className="text-sm text-muted-foreground">
                  <span className="font-medium text-foreground">{t.audit.githubTagLabel}:</span>{" "}
                  <a
                    href={githubTagUrl}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-primary underline-offset-4 hover:underline"
                  >
                    {githubTagDisplay}
                  </a>
                </p>
                <p className="text-sm text-muted-foreground">
                  <span className="font-medium text-foreground">{t.audit.githubCommitLabel}:</span>{" "}
                  <a
                    href={githubCommitUrl}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-primary underline-offset-4 hover:underline"
                  >
                    {githubCommitDisplay}
                  </a>
                </p>
                <p className="text-sm text-muted-foreground">
                  <span className="font-medium text-foreground">{t.audit.githubReleaseLabel}:</span>{" "}
                  <a
                    href={githubReleaseUrl}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-primary underline-offset-4 hover:underline"
                  >
                    {githubReleaseDisplay}
                  </a>
                </p>
              </div>

              {verifySteps.map((step, index) => (
                <div key={step.title} className="rounded-lg border border-border bg-card p-4 space-y-3">
                  <p className="font-medium text-foreground">{index + 1}. {step.title}</p>
                  <p className="text-sm text-muted-foreground">{step.description}</p>
                  {step.command ? (
                    <div className="flex items-start gap-2">
                      <pre className="flex-1 overflow-x-auto rounded-md bg-muted p-3 text-xs text-foreground">{step.command}</pre>
                      <Button
                        size="sm"
                        variant="outline"
                        onClick={() => {
                          void copyToClipboard(step.command as string)
                        }}
                        className="shrink-0"
                      >
                        {copiedCommand === step.command ? (
                          <>
                            <Check className="w-4 h-4 mr-1" />
                            {verifyTexts.copied}
                          </>
                        ) : (
                          <>
                            <Copy className="w-4 h-4 mr-1" />
                            {verifyTexts.copy}
                          </>
                        )}
                      </Button>
                    </div>
                  ) : null}
                </div>
              ))}

              <div className="rounded-md border border-dashed border-border p-3 text-xs text-muted-foreground">
                {verifyTexts.controllersNote}
              </div>
            </CardContent>
          </Card>
        </motion.div>

        {/* Verification Links */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.5, delay: 0.4 }}
        >
          <Card className="border-primary/20 bg-accent/30">
            <CardHeader>
              <CardTitle className="text-lg font-semibold text-foreground flex items-center gap-2">
                <ExternalLink className="w-5 h-5 text-primary" />
                {t.audit.verificationLinks}
              </CardTitle>
              <CardDescription>
                {t.audit.verificationLinksDesc}
              </CardDescription>
            </CardHeader>
            <CardContent className="space-y-3">
              {verificationLinks.map((link) => (
                <a
                  key={link.name}
                  href={link.url}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="flex items-center justify-between p-4 bg-card rounded-lg border border-border hover:border-primary/30 transition-all group"
                >
                  <div>
                    <p className="font-medium text-foreground group-hover:text-primary transition-colors">
                      {link.name}
                    </p>
                    <p className="text-sm text-muted-foreground">{link.description}</p>
                  </div>
                  <ExternalLink className="w-5 h-5 text-muted-foreground group-hover:text-primary transition-colors flex-shrink-0" />
                </a>
              ))}
            </CardContent>
          </Card>
        </motion.div>
      </div>
    </section>
  )
}