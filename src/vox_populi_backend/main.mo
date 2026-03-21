import Blob "mo:base/Blob";
import Int "mo:base/Int";
import List "mo:base/List";
import Nat "mo:base/Nat";
import Principal "mo:base/Principal";
import Text "mo:base/Text";
import Time "mo:base/Time";

import AuditService "./audit/audit_service";
import IdentityRegistryService "./auth/identity_registry_service";
import AuthService "./auth/auth_service";
import TokenInfoParser "./auth/tokeninfo_parser";
import ICHttpTypes "./infrastructure/ic_http_types";
import SurveyConfig "./shared/survey_config";
import Types "./shared/types";
import VoteRuntimeService "./vote/vote_runtime_service";
import Validation "./shared/validation";

// Actor persistente del dominio de votaciones.
//
// Diseno general:
// - Este archivo funciona como capa de orquestacion y API publica.
// - Los tipos compartidos viven en shared/types.mo.
// - Las reglas de validacion viven en shared/validation.mo.
// - Los calculos estadisticos viven en aggregations.mo.
//
// Objetivo de separacion:
// - Reducir acoplamiento entre endpoints y calculos.
// - Facilitar pruebas y mantenimiento por responsabilidades.
persistent actor Self {
  // Reexport de tipos para mantener estable el contrato Candid.
  // Esto garantiza que las declaraciones TypeScript sigan alineadas.
  public type AnswerSelection = Types.AnswerSelection;
  public type VoteResponse = Types.VoteResponse;
  public type ToolDistributionItem = Types.ToolDistributionItem;
  public type RadarPoint = Types.RadarPoint;
  public type SecurityMatrixRow = Types.SecurityMatrixRow;
  public type AggregatedResults = Types.AggregatedResults;
  public type RawResponse = Types.RawResponse;
  public type AuditData = Types.AuditData;
  public type GoogleIdentityClaims = Types.GoogleIdentityClaims;
  public type GoogleTokenValidation = Types.GoogleTokenValidation;

  // -----------------------------
  // Estado persistente del actor
  // -----------------------------

  // Contador incremental para generar identificadores de voto legibles.
  var nextVoteId : Nat = 1;
  // Almacen principal de votos en lista enlazada.
  // Ventaja: insercion O(1) con List.push sin copiar todo el historico.
  // Nota: la lista guarda los votos mas recientes al inicio.
  // Enfoque de rendimiento del backend:
  // - Escritura (submitVote): O(1) por insercion.
  // - Lectura/cálculo (queries agregadas): O(n) sobre votos filtrados.
  var storedVotes : List.List<Types.StoredVote> = List.nil<Types.StoredVote>();
  // Version de la logica de negocio del cuestionario.
  // Se expone por auditoria en getAuditData.
  let surveyCodeVersion : Text = "1.0.0";
  // Client ID OAuth esperado para validar id_token en backend.
  // En este piloto TFM se fija en codigo para que submitVote no dependa
  // de parametros manipulables desde cliente.
  let expectedGoogleAudience : Text =
    "765842824522-ar0t6cn0uet2qmf9v0lvp0q2p09t24b2.apps.googleusercontent.com";

  // Sal secreta del backend para derivar identificadores seudonimos desde email.
  // Piloto TFM: se inicializa una unica vez y queda persistida en estado estable.
  var backendEmailSalt : Text = "";

  // Se mantiene como estado estable por compatibilidad con upgrades previos.
  // El valor inicial queda centralizado en shared/survey_config.mo.
  var questionOptionCounts : [Nat] = SurveyConfig.questionOptionCounts;

  // Espejo estable del indice de duplicados por (surveyId, voterId) -> voteId.
  // Permite reconstruir lookup O(1) tras upgrade sin recorrer claves complejas.
  var voteLookupEntries : List.List<(Text, Text, Nat)> = List.nil<(Text, Text, Nat)>();

  // Registro estable de identidad validada -> pseudonimo opaco.
  // Clave actual: email normalizado tras validacion OIDC.
  var identityRegistryEntries : List.List<(Text, Text)> = List.nil<(Text, Text)>();

  // Indices en memoria para consultas O(1).
  transient var voteLookup : VoteRuntimeService.VoteLookup = VoteRuntimeService.buildVoteLookup(voteLookupEntries);
  transient var identityRegistry : IdentityRegistryService.IdentityRegistry = IdentityRegistryService.buildIdentityMap(identityRegistryEntries);
  transient var surveyVotesCache : VoteRuntimeService.SurveyVotesCache = VoteRuntimeService.buildSurveyVotesCache(storedVotes);

  // Subset de la interfaz del IC Management Canister necesario para canister_status.
  // Para que funcione, este canister debe estar en su propia lista de controladores:
  //   dfx canister update-settings vox_populi_backend --add-controller <canister-id>
  let IC = actor "aaaaa-aa" : actor {
    canister_status : shared ({ canister_id : Principal }) -> async {
      module_hash : ?Blob;
      cycles : Nat;
      memory_size : Nat;
    };
    http_request : shared ICHttpTypes.HttpRequestArgs -> async ICHttpTypes.HttpResponsePayload;
    raw_rand : shared () -> async Blob;
  };

  // API CONTRACT: transformGoogleTokenInfoResponse (query)
  // Objetivo:
  // - Normalizar respuestas de tokeninfo para reducir no determinismo de
  //   HTTPS outcalls en consenso de subred.
  // Estrategia:
  // - Elimina headers volatiles.
  // - Si status != 200, preserva solo status y cuerpo vacio.
  // - Si status == 200, conserva un JSON canonico con claims minimas usadas
  //   por la validacion (`aud`, `iss`, `exp`, `email`, `email_verified`).
  public query func transformGoogleTokenInfoResponse(args : ICHttpTypes.TransformArgs) : async ICHttpTypes.HttpResponsePayload {
    if (args.response.status != 200) {
      return {
        status = args.response.status;
        headers = [];
        body = [];
      };
    };

    let bodyText =
      switch (Text.decodeUtf8(Blob.fromArray(args.response.body))) {
        case (?decoded) { decoded };
        case null {
          return {
            status = 200;
            headers = [];
            body = [];
          };
        };
      };

    let compactBodyText = TokenInfoParser.compactJson(bodyText);
    let aud = TokenInfoParser.extractJsonString(compactBodyText, "aud");
    let iss = TokenInfoParser.extractJsonString(compactBodyText, "iss");
    let exp = TokenInfoParser.extractJsonNat(compactBodyText, "exp");
    let email = TokenInfoParser.extractJsonString(compactBodyText, "email");
    let emailVerified = TokenInfoParser.extractJsonBool(compactBodyText, "email_verified");

    func renderTextOrNull(value : ?Text) : Text {
      switch (value) {
        case (?text) { "\"" # text # "\"" };
        case null { "null" };
      };
    };

    func renderNatOrNull(value : ?Nat) : Text {
      switch (value) {
        case (?natValue) { Nat.toText(natValue) };
        case null { "null" };
      };
    };

    let canonicalBody =
      "{"
      # "\"aud\":" # renderTextOrNull(aud)
      # ",\"iss\":" # renderTextOrNull(iss)
      # ",\"exp\":" # renderNatOrNull(exp)
      # ",\"email\":" # renderTextOrNull(email)
      # ",\"email_verified\":" # (if (emailVerified == ?true) { "true" } else { "false" })
      # "}";

    {
      status = 200;
      headers = [];
      body = Blob.toArray(Text.encodeUtf8(canonicalBody));
    };
  };

  // Flujo OIDC reutilizable para endpoints que requieran identidad validada.
  // Devuelve `GoogleTokenValidation` con `voterId` pseudonimo si procede.
  func validateAndAttachIdentity(idToken : Text, expectedAudience : Text) : async GoogleTokenValidation {
    let nowNs = Time.now();
    let result = await AuthService.validateGoogleIdToken(
      IC,
      transformGoogleTokenInfoResponse,
      Principal.fromActor(Self),
      backendEmailSalt,
      nowNs,
      idToken,
      expectedAudience,
    );
    backendEmailSalt := result.backendEmailSalt;

    let identityResult = await IdentityRegistryService.attachPseudonymousIdentity(
      IC,
      backendEmailSalt,
      nowNs,
      result.validation,
      identityRegistry,
      identityRegistryEntries,
    );
    identityRegistryEntries := identityResult.identityRegistryEntries;
    identityResult.validation;
  };

  // ---------------------------------
  // Endpoint de escritura (update call)
  // ---------------------------------

  // API CONTRACT: submitVote (update)
  // Parametros:
  // - surveyId: identificador logico de la encuesta.
  // - idToken: JWT emitido por Google Identity Services.
  // - answers: lista normalizada de respuestas (questionId, optionIndex).
  // - _timestamp: campo legado enviado por cliente (actualmente se ignora).
  //   El backend usa tiempo de red del canister para evitar manipulacion del reloj cliente.
  // Precondiciones:
  // - surveyId no vacio.
  // - answers no vacio.
  // - sin preguntas repetidas dentro del mismo voto.
  // - cada questionId/optionIndex dentro de rangos validos.
  // Postcondiciones (success = true):
  // - el voto queda persistido en storedVotes.
  // - nextVoteId se incrementa en 1.
  // - se devuelve voteId con formato "vote-<n>".
  // Errores funcionales (success = false):
  // - id_token invalido o expirado.
  // - encuesta obligatoria, respuestas vacias, preguntas repetidas,
  //   respuestas fuera de rango o voto duplicado.
  // Complejidad aproximada: O(n), donde n=answers.
  // Nota: el bloqueo de duplicados usa indice en memoria O(1) promedio.
  // Registra un voto con autenticacion OIDC obligatoria.
  // Flujo resumido:
  // 1) valida id_token de Google y obtiene voterId pseudonimo estable.
  // 2) valida surveyId y payload de respuestas.
  // 3) valida duplicados y persiste.
  public shared ({ caller }) func submitVote(
    surveyId : Text,
    idToken : Text,
    answers : [AnswerSelection],
    _timestamp : Nat,
  ) : async VoteResponse {
    let validation = await validateAndAttachIdentity(idToken, expectedGoogleAudience);
    if (not validation.isValid) {
      return {
        success = false;
        message = "Autenticacion invalida: " # validation.reason;
        voteId = null;
      };
    };

    let resolvedVoterId =
      switch (validation.voterId) {
        case (?voterId) { voterId };
        case null {
          return {
            success = false;
            message = "No se pudo derivar identidad de voto";
            voteId = null;
          };
        };
      };

    let result = VoteRuntimeService.submitVoteWithIndexes(
      voteLookup,
      surveyVotesCache,
      storedVotes,
      nextVoteId,
      voteLookupEntries,
      surveyId,
      resolvedVoterId,
      answers,
      Principal.toText(caller),
      Time.now(),
      questionOptionCounts,
    );

    storedVotes := result.storedVotes;
    nextVoteId := result.nextVoteId;
    voteLookupEntries := result.voteLookupEntries;

    result.response;
  };

  // -----------------------------
  // Endpoints de lectura (queries)
  // -----------------------------

  // API CONTRACT: hasUserVoted (query)
  // Parametros:
  // - surveyId: identificador de encuesta.
  // - voterId: identificador anonimo del votante.
  // Resultado:
  // - true si existe al menos un voto con esa pareja (surveyId, voterId).
  // - false en caso contrario.
  // Uso tipico:
  // - validaciones de UX antes de iniciar el formulario de votacion.
  // Complejidad aproximada: O(1) promedio (indice runtime de duplicados).
  // Consulta booleana para detectar si un identificador ya voto en una encuesta.
  // Se usa principalmente para UX (bloquear o avisar antes de entrar a votar).
  public query func hasUserVoted(surveyId : Text, voterId : Text) : async Bool {
    VoteRuntimeService.hasUserVoted(voteLookup, surveyId, voterId);
  };

  // API CONTRACT: validateInstitutionalEmail (query)
  // Parametros:
  // - email: correo de la cuenta autenticada por proveedor OIDC.
  // Resultado:
  // - true cuando el dominio es @uoc.edu.
  // Notas:
  // - Esta validacion es la primera capa de backend para login institucional.
  // - La validacion criptografica completa del id_token se implementara en la siguiente fase.
  public query func validateInstitutionalEmail(email : Text) : async Bool {
    Validation.isUocInstitutionalEmail(email);
  };

  // API CONTRACT: validateGoogleIdentity (query)
  // Parametros:
  // - claims: claims minimos extraidos del id_token JWT en frontend.
  // - expectedAudience: client_id de Google esperado por backend.
  // Resultado:
  // - true cuando email/aud/iss/exp son consistentes con login institucional UOC.
  // Nota de seguridad:
  // - Esta fase valida semantica de claims.
  // - La validacion criptografica de firma JWT se incorporara en la siguiente iteracion.
  public query func validateGoogleIdentity(claims : GoogleIdentityClaims, expectedAudience : Text) : async Bool {
    AuthService.validateGoogleIdentity(claims, expectedAudience, Int.abs(Time.now() / 1_000_000_000));
  };

  // API CONTRACT: validateGoogleIdToken (update)
  // Parametros:
  // - idToken: JWT emitido por Google Identity Services.
  // - expectedAudience: client_id OAuth configurado en el frontend.
  // Resultado:
  // - GoogleTokenValidation con estado final, email validado (si aplica) y motivo.
  // Seguridad:
  // - El backend consulta tokeninfo de Google para validar token firmado por Google.
  // - Se valida aud, iss, exp, email_verified y dominio @uoc.edu.
  public func validateGoogleIdToken(idToken : Text, expectedAudience : Text) : async GoogleTokenValidation {
    await validateAndAttachIdentity(idToken, expectedAudience);
  };

  // API CONTRACT: getAggregatedResults (query)
  // Parametros:
  // - surveyId: identificador de encuesta.
  // Resultado:
  // - objeto AggregatedResults con KPI y datasets para dashboard.
  // Campos calculados:
  // - totalVotes, blockchainTrustPercentage, averageHoursSaved,
  //   toolDistribution, impactRadar, securityMatrix, icpPreference.
  // Comportamiento con pocos datos:
  // - si no hay votos, devuelve estructuras vacias/ceros sin lanzar error.
  // Consistencia:
  // - todos los porcentajes se redondean a entero en backend.
  // Complejidad aproximada: O(m), m=votos de la encuesta.
  // Nota de implementacion: se itera la lista filtrada sin conversion global a array,
  // evitando coste extra de memoria y copias intermedias.
  // Genera el payload agregado consumido por la pantalla de resultados.
  // Este endpoint concentra KPI globales y datasets de visualizacion.
  public query func getAggregatedResults(surveyId : Text) : async AggregatedResults {
    VoteRuntimeService.getAggregatedResultsFromCache(surveyVotesCache, surveyId);
  };

  // API CONTRACT: getRawResponses (query)
  // Parametros:
  // - surveyId: identificador de encuesta.
  // Resultado:
  // - lista RawResponse en orden de insercion (numero inicia en 1).
  // Uso tipico:
  // - exportacion CSV, trazabilidad, revision manual o auditoria.
  // Notas:
  // - no transforma etiquetas; devuelve solo datos normalizados.
  // Complejidad aproximada: O(m), m=votos de la encuesta.
  // Devuelve respuestas crudas en orden de insercion.
  // Es util para exportaciones CSV o auditoria externa.
  public query func getRawResponses(surveyId : Text) : async [RawResponse] {
    VoteRuntimeService.getRawResponsesFromCache(surveyVotesCache, surveyId);
  };

  // API CONTRACT: getAuditData (update)
  // Parametros:
  // - ninguno.
  // Resultado:
  // - objeto AuditData con metadatos tecnicos de version/despliegue.
  // Notas:
  // - Es update call (no query) porque necesita await al management canister.
  // - Requiere que este canister sea su propio controlador para leer module_hash y cycles.
  //   Configuracion (una sola vez):
  //     dfx canister update-settings vox_populi_backend --add-controller $(dfx canister id vox_populi_backend)
  // Metadatos tecnicos de trazabilidad del despliegue.
  public func getAuditData() : async AuditData {
    await AuditService.getAuditData(IC, Principal.fromActor(Self), surveyCodeVersion);
  };

  // API CONTRACT: getModuleHash (update)
  // Parametros:
  // - canisterId: principal del canister a consultar.
  // Resultado:
  // - hash hexadecimal del modulo WASM instalado, o mensaje de error.
  // Notas:
  // - El backend debe ser controlador del canister consultado.
  //   Para el frontend: dfx canister update-settings vox_populi_frontend --add-controller $(dfx canister id vox_populi_backend)
  public func getModuleHash(canisterId : Principal) : async Text {
    await AuditService.getModuleHash(IC, canisterId);
  };

  // API CONTRACT: greet (query)
  // Parametros:
  // - name: texto de entrada.
  // Resultado:
  // - saludo simple para verificacion basica de conectividad.
  // Endpoint minimo de smoke test.
  public query func greet(name : Text) : async Text {
    "Hello, " # name # "!";
  };
};