
import { useEffect, useMemo, useState } from "react"
import { motion } from "framer-motion"
import { ArrowLeft, ExternalLink, Hash, Cpu, Copy, Check } from "lucide-react"

import { Button } from "../../components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "../../components/ui/card"
import { useLocale } from "../../lib/locale-context"
import { InfoTerm } from "../../components/layout/info-term"
import { Principal } from "@icp-sdk/core/principal"
import { canisterService } from "../../lib/canister-service"
import { canisterId as backendCanisterId } from "../../../../declarations/vox_populi_backend"
import { canisterId as frontendCanisterId } from "../../../../declarations/vox_populi_frontend"

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
  const { locale, t } = useLocale()
  const [copiedCommand, setCopiedCommand] = useState<string | null>(null)

  // Cargamos auditData on-chain del backend (sin mocks).
  const [backendAuditData, setBackendAuditData] = useState<{
    canisterId: string
    wasmModuleHash: string
    codeVersion: string
  } | null>(null)
  const [frontendModuleHash, setFrontendModuleHash] = useState<string | null>(null)

  // Recuperacion inicial del backend para version de codigo y metadatos disponibles.
  useEffect(() => {
    void canisterService.getAuditData()
      .then((data) => setBackendAuditData(data))
      .catch((error) => {
        console.error("[AuditPage] No se pudieron cargar metadatos de auditoria", error)
        setBackendAuditData(null)
      })

    if (frontendCanisterId) {
      void canisterService.getModuleHash(Principal.fromText(frontendCanisterId))
        .then((hash) => setFrontendModuleHash(/^[0-9a-f]{64}$/.test(hash) ? hash : null))
        .catch(() => setFrontendModuleHash(null))
    }
  }, [])

  const network = import.meta.env.DFX_NETWORK === "ic" ? "ic" : "local"
  const githubRepoUrl = import.meta.env.VITE_GITHUB_REPO_URL || "https://github.com/<org>/<repo>"
  const githubReleaseTag = import.meta.env.VITE_GITHUB_RELEASE_TAG || "<release-tag>"

  const backendId = backendCanisterId || "No disponible"
  const frontendId = frontendCanisterId || "No disponible"

  // Texto didactico inline por idioma para no romper el contrato de traducciones existente.
  const verifyTexts = useMemo(() => {
    if (locale === "en") {
      return {
        title: "How To Verify",
        intro: "Compare on-chain data with the published release artifacts in GitHub.",
        step1: "Check canister identity and module hash on-chain",
        step1Desc: "Open each canister in a blockchain explorer and confirm module hash.",
        step2: "Compute local WASM hash",
        step2Desc: "Build locally and compute SHA-256 hash for each wasm.",
        step3: "Compare against published release manifest",
        step3Desc: "Ensure the on-chain hash matches the hash from the release artifacts in GitHub.",
        copy: "Copy",
        copied: "Copied",
        repo: "Source repository",
        release: "Release reference",
        controllersNote: "Tip: canister status requires controller permissions. From browser clients, module hash may not be directly readable.",
        moduleHashUnavailable: "Not directly readable from this client (requires canister_status by a controller)",
      }
    }

    if (locale === "ca") {
      return {
        title: "Com Verificar",
        intro: "Compara dades on-chain amb els artefactes publicats a GitHub.",
        step1: "Comprova identitat del canister i module hash on-chain",
        step1Desc: "Obre cada canister a l'explorador i valida el module hash.",
        step2: "Calcula el hash local del WASM",
        step2Desc: "Compila en local i calcula el SHA-256 de cada wasm.",
        step3: "Compara amb el manifest publicat de la release",
        step3Desc: "Assegura que el hash on-chain coincideix amb el hash dels artefactes publicats a GitHub.",
        copy: "Copiar",
        copied: "Copiat",
        repo: "Repositori font",
        release: "Referencia de release",
        controllersNote: "Consell: canister status requereix permisos de controller. Des del navegador, el module hash pot no ser llegible directament.",
        moduleHashUnavailable: "No llegible directament des d'aquest client (requereix canister_status per un controller)",
      }
    }

    return {
      title: "Como Verificar",
      intro: "Compara los datos on-chain con los artefactos publicados en GitHub.",
      step1: "Comprobar identidad del canister y module hash on-chain",
      step1Desc: "Abre cada canister en el explorer y valida su module hash.",
      step2: "Calcular hash local del WASM",
      step2Desc: "Compila en local y calcula SHA-256 de cada wasm.",
      step3: "Comparar con el manifest publicado de la release",
      step3Desc: "Asegura que el hash on-chain coincide con el hash de los artefactos publicados en GitHub.",
      copy: "Copiar",
      copied: "Copiado",
      repo: "Repositorio fuente",
      release: "Referencia de release",
      controllersNote: "Nota: canister status requiere permisos de controller. Desde navegador, el module hash puede no ser legible directamente.",
      moduleHashUnavailable: "No legible directamente desde este cliente (requiere canister_status por un controller)",
    }
  }, [locale])

  const backendModuleHash = /^[0-9a-f]{64}$/.test(backendAuditData?.wasmModuleHash ?? "")
    ? backendAuditData!.wasmModuleHash
    : verifyTexts.moduleHashUnavailable
  const codeVersion = backendAuditData?.codeVersion || "No disponible"

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
      moduleHash: frontendModuleHash ?? verifyTexts.moduleHashUnavailable,
    },
  ]

  const verifySteps: VerifyStep[] = [
    {
      title: verifyTexts.step1,
      description: verifyTexts.step1Desc,
      command: `dfx canister status ${backendId}`,
    },
    {
      title: verifyTexts.step2,
      description: verifyTexts.step2Desc,
      command:
        "dfx build vox_populi_backend && shasum -a 256 .dfx/local/canisters/vox_populi_backend/vox_populi_backend.wasm",
    },
    {
      title: verifyTexts.step3,
      description: verifyTexts.step3Desc,
      command: `Open ${githubRepoUrl}/releases/tag/${githubReleaseTag}`,
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

  const verificationLinks = [
    {
      name: t.audit.icDashboard,
      url: network === "ic"
        ? `https://dashboard.internetcomputer.org/canister/${backendId}`
        : `http://127.0.0.1:4943/?canisterId=${backendId}`,
      description: t.audit.icDashboardDesc
    },
    {
      name: t.audit.icScan,
      url: network === "ic"
        ? `https://icscan.io/canister/${backendId}`
        : `http://127.0.0.1:4943/?canisterId=${frontendId}`,
      description: t.audit.icScanDesc
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
                Canisters y Hashes
              </CardTitle>
              <CardDescription>
                <span className="font-medium text-foreground">{t.audit.codeVersion}:</span> {codeVersion}
              </CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
              {canisterRows.map((row) => (
                <div key={row.key} className="rounded-lg border border-border p-4 space-y-2">
                  <p className="font-semibold text-foreground">{row.name}</p>
                  <p className="text-sm text-muted-foreground break-all">
                    <span className="font-medium text-foreground">Canister ID:</span> {row.canisterId}
                  </p>
                  <p className="text-sm text-muted-foreground break-all">
                    <span className="font-medium text-foreground">On-chain module hash:</span> {row.moduleHash}
                  </p>
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

              <div className="space-y-1 text-sm text-muted-foreground">
                <p><span className="font-medium text-foreground">{verifyTexts.repo}:</span> {githubRepoUrl}</p>
                <p><span className="font-medium text-foreground">{verifyTexts.release}:</span> {githubReleaseTag}</p>
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