

import { HelpCircle } from "lucide-react"

// Usando el alias @ para apuntar a src/components/ui/
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover"

// ============================================================================
// COMPONENTE INFOTERM - POPOVER PARA TÉRMINOS TÉCNICOS
// ============================================================================
// Componente reutilizable para mostrar explicaciones de términos técnicos.
// Usa Popover en lugar de Tooltip para funcionar en móviles (tap) y desktop (click).
//
// USO:
// <InfoTerm term="Canister ID" definition={t.glossary.canisterId} />
// <InfoTerm term="ICP" definition={t.glossary.icp} showIcon={false} />
//
// PROPS:
// - term: El texto que se muestra (puede ser un término técnico)
// - definition: La explicación que aparece en el popover
// - showIcon: Si mostrar el icono de ayuda (default: true)
// - className: Clases adicionales para el contenedor
//
// PARA AÑADIR NUEVOS TÉRMINOS:
// 1. Añade la definición en lib/i18n.ts > glossary (en los 3 idiomas)
// 2. Usa <InfoTerm term="Mi Término" definition={t.glossary.miTermino} />
// ============================================================================

interface InfoTermProps {
  term: string
  definition: string
  showIcon?: boolean
  className?: string
}

export function InfoTerm({ 
  term, 
  definition, 
  showIcon = true,
  className = "" 
}: InfoTermProps) {
  return (
    <Popover>
      <PopoverTrigger asChild>
        <button 
          type="button"
          className={`inline-flex items-center gap-1 cursor-pointer border-b border-dotted border-muted-foreground/50 hover:border-primary focus:border-primary focus:outline-none transition-colors ${className}`}
        >
          {term}
          {showIcon && (
            <HelpCircle className="w-3.5 h-3.5 text-muted-foreground" />
          )}
        </button>
      </PopoverTrigger>
      <PopoverContent 
        side="top" 
        className="max-w-xs text-sm leading-relaxed p-3"
      >
        {definition}
      </PopoverContent>
    </Popover>
  )
}
