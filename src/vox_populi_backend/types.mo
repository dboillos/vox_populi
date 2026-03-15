import Nat "mo:base/Nat";
import Float "mo:base/Float";
import Text "mo:base/Text";

module {
  // ------------------------------------------------
  // Tipos compartidos entre canister y frontend
  // ------------------------------------------------
  //
  // Regla de modelado clave:
  // - Las respuestas se guardan como questionId + optionIndex.
  // - No se persiste texto traducido.
  //
  // Ventajas:
  // - El backend es independiente del idioma de la interfaz.
  // - Cambios de textos en frontend no rompen historicos.

  // Respuesta de una pregunta individual (normalizada por indice).
  public type AnswerSelection = {
    questionId : Nat;
    optionIndex : Nat;
  };

  // Respuesta estandar para operaciones de escritura (submitVote).
  public type VoteResponse = {
    success : Bool;
    message : Text;
    voteId : ?Text;
  };

  // Item de distribucion para graficos de porcentaje por opcion.
  public type ToolDistributionItem = {
    optionIndex : Nat;
    value : Nat;
  };

  // Punto de radar en escala comun 0..5.
  public type RadarPoint = {
    axis : Text;
    value : Float;
    fullMark : Nat;
  };

  // Fila de matriz de seguridad con tres bandas porcentuales.
  public type SecurityMatrixRow = {
    category : Text;
    confia : Nat;
    neutral : Nat;
    desconfia : Nat;
  };

  // Resultado agregado completo para dashboard.
  // Incluye tanto KPI generales como datasets de visualizacion.
  public type AggregatedResults = {
    totalVotes : Nat;
    blockchainTrustPercentage : Nat;
    averageHoursSaved : Float;
    toolDistribution : [ToolDistributionItem];
    impactRadar : [RadarPoint];
    securityMatrix : [SecurityMatrixRow];
    icpPreference : Nat;
  };

  // Respuesta cruda para exportacion y trazabilidad.
  public type RawResponse = {
    numero : Nat;
    voterId : Text;
    timestamp : Nat;
    answers : [AnswerSelection];
  };

  // Metadatos de despliegue/version para auditoria tecnica.
  public type AuditData = {
    canisterId : Text;
    wasmModuleHash : Text;
    cyclesBalance : Text;
    codeVersion : Text;
  };

  // Estructura persistida interna.
  // Diferencia importante con RawResponse:
  // - StoredVote guarda voteId interno y surveyId.
  // - RawResponse esta orientado al consumo externo.
  public type StoredVote = {
    voteId : Nat;
    surveyId : Text;
    voterId : Text;
    timestamp : Nat;
    answers : [AnswerSelection];
  };
};