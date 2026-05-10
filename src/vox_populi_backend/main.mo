import Blob "mo:base/Blob";
import Int "mo:base/Int";
import List "mo:base/List";
import Nat "mo:base/Nat";
import Principal "mo:base/Principal";
import Text "mo:base/Text";
import Time "mo:base/Time";
import HashMap "mo:base/HashMap";
import Nat8 "mo:base/Nat8";

import AuditService "./audit/audit_service";
import IdentityRegistryService "./auth/identity_registry_service";
import AuthService "./auth/auth_service";
import TokenInfoParser "./auth/tokeninfo_parser";
import ICHttpTypes "./infrastructure/ic_http_types";
import SurveyConfig "./shared/survey_config";
import Types "./shared/types";
import VoteRuntimeService "./vote/vote_runtime_service";

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
  // Campo persistente conservado por compatibilidad de layout en upgrades.
  // No se usa en la API final, pero evita ruptura de memoria estable (IC0503).
  let MIGRATION_ADMIN : Principal = Principal.fromText("tn77x-osmtr-gtg2m-qzwxl-ptenl-jfezc-im5h2-7t556-tfi26-j5ljr-kqe");

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
    public type AuthSessionResult = Types.AuthSessionResult;

  // -----------------------------
  // Estado persistente del actor
  // -----------------------------

  // Contador incremental para generar identificadores de voto legibles.
  var nextVoteId : Nat = 1;
  // Almacen principal de votos en lista enlazada (sin timestamp en estado estable).
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
  transient let questionOptionCounts : [Nat] = SurveyConfig.questionOptionCounts;

  // Espejo estable del indice de duplicados por (surveyId, voterId) -> voteId.
  // Permite reconstruir lookup O(1) tras upgrade sin recorrer claves complejas.
  var voteLookupEntries : List.List<(Text, Text, Nat)> = List.nil<(Text, Text, Nat)>();

  // Registro estable de identidad validada -> pseudonimo opaco.
  // Clave actual: email normalizado tras validacion OIDC.
  var identityRegistryEntries : List.List<(Text, Text)> = List.nil<(Text, Text)>();

  // Indices en memoria para consultas O(1).

    // Sesiones de autenticacion de un solo uso: (sessionId, voterId, expiresAtNs, usado).
    // Se persiste como lista estable; el mapa transient permite lookup O(1) en runtime.
    transient var sessionStableEntries : List.List<(Text, Text, Int, Bool)> = List.nil<(Text, Text, Int, Bool)>();


    // Duracion de sesion: 30 minutos en nanosegundos.
    transient let SESSION_DURATION_NS : Int = 30 * 60 * 1_000_000_000;

  transient var voteLookup : VoteRuntimeService.VoteLookup = VoteRuntimeService.buildVoteLookup(voteLookupEntries);
  transient var identityRegistry : IdentityRegistryService.IdentityRegistry = IdentityRegistryService.buildIdentityMap(identityRegistryEntries);
  transient var surveyVotesCache : VoteRuntimeService.SurveyVotesCache = VoteRuntimeService.buildSurveyVotesCache(storedVotes);

    // Mapa transient de sesiones activas (sessionId -> (voterId, expiresAtNs, usado)).
    // Se reconstruye desde sessionStableEntries en cada arranque/upgrade.
    // -----------------------------------------------
    // Helpers internos de sesion
    // -----------------------------------------------

    func buildSessionMapFromEntries(
      entries : List.List<(Text, Text, Int, Bool)>
    ) : HashMap.HashMap<Text, (Text, Int, Bool)> {
      let map = HashMap.HashMap<Text, (Text, Int, Bool)>(16, Text.equal, Text.hash);
      var current = entries;
      label iter loop {
        switch current {
          case null { break iter };
          case (?(head, tail)) {
            let (sid, vid, exp, used) = head;
            map.put(sid, (vid, exp, used));
            current := tail;
          };
        };
      };
      map
    };

    func byteToHex(b : Nat8) : Text {
      let digits = ["0","1","2","3","4","5","6","7","8","9","a","b","c","d","e","f"];
      digits[Nat8.toNat(b) / 16] # digits[Nat8.toNat(b) % 16]
    };

    func blobToHex(b : Blob) : Text {
      var result = "";
      for (byte in b.vals()) {
        result := result # byteToHex(byte);
      };
      result
    };

    transient var sessionMap : HashMap.HashMap<Text, (Text, Int, Bool)> = buildSessionMapFromEntries(sessionStableEntries);

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
    // API CONTRACT: authenticateWithGoogle (update)
    // Parametros:
    // - idToken: JWT de Google Identity Services obtenido en cliente.
    // Postcondiciones (success = true):
    // - Se valida el id_token contra Google tokeninfo.
    // - Se deriva el voterId pseudonimo (hash(email + salt)).
    // - Se genera un sessionId opaco de un solo uso (32 bytes aleatorios en hex).
    // - La sesion caduca en SESSION_DURATION_NS nanosegundos.
    // Seguridad:
    // - El id_token de Google NUNCA se persiste ni se retransmite a cliente de vuelta.
    // - Solo se retorna el sessionId opaco + voterId pseudonimo para checks de UX.
    public shared ({ caller }) func authenticateWithGoogle(idToken : Text) : async AuthSessionResult {
      if (Principal.toText(caller) == "2vxsx-fae") {
        return {
          success = false;
          sessionId = "";
          expiresAt = 0;
          voterId = "";
          reason = "Se requiere una identidad ICP firmada para autenticarse";
        };
      };

      let validation = await validateAndAttachIdentity(idToken, expectedGoogleAudience);
      if (not validation.isValid) {
        return {
          success = false;
          sessionId = "";
          expiresAt = 0;
          voterId = "";
          reason = validation.reason;
        };
      };

      let resolvedVoterId = switch (validation.voterId) {
        case (?vid) { vid };
        case null {
          return {
            success = false;
            sessionId = "";
            expiresAt = 0;
            voterId = "";
            reason = "No se pudo derivar identidad de voto";
          };
        };
      };

      // Generar sessionId criptograficamente aleatorio (32 bytes = 64 chars hex).
      let randomBlob = await IC.raw_rand();
      let callerText = Principal.toText(caller);
      let sessionId = callerText # "." # blobToHex(randomBlob);
      let nowNs = Time.now();
      let expiresAt = nowNs + SESSION_DURATION_NS;

      // Persistir sesion en lista estable y mapa transient.
      sessionStableEntries := List.push(
        (sessionId, resolvedVoterId, expiresAt, false),
        sessionStableEntries
      );
      sessionMap.put(sessionId, (resolvedVoterId, expiresAt, false));

      {
        success = true;
        sessionId;
        expiresAt;
        voterId = resolvedVoterId;
        reason = "";
      }
    };

    // Registra un voto autenticado mediante sessionId de un solo uso.
    // API CONTRACT: submitVote (update)
    // Parametros:
    // - surveyId: identificador logico de la encuesta.
    // - sessionId: sesion opaca de un solo uso emitida por authenticateWithGoogle.
    // - answers: lista normalizada de respuestas (questionId, optionIndex).
    // Errores funcionales (success = false):
    // - sesion no encontrada, ya usada o expirada.
    // - encuesta obligatoria, respuestas vacias, preguntas repetidas,
    //   respuestas fuera de rango o voto duplicado.
    // Flujo resumido:
    // 1) busca y valida la sesion (no expirada, no usada).
    // 2) marca la sesion como usada de forma atomica.
    // 3) valida surveyId y payload de respuestas.
    // 4) valida duplicados y persiste.
    public shared ({ caller }) func submitVote(
      surveyId : Text,
      sessionId : Text,
      answers : [AnswerSelection],
    ) : async VoteResponse {
      if (Principal.toText(caller) == "2vxsx-fae") {
        return {
          success = false;
          message = "Autenticacion invalida: se requiere una identidad ICP firmada";
          voteId = null;
        };
      };

      let nowNs = Time.now();
      let callerText = Principal.toText(caller);

      // Buscar sesion en mapa transient O(1).
      let (resolvedVoterId) = switch (sessionMap.get(sessionId)) {
        case null {
          return {
            success = false;
            message = "Autenticacion invalida: sesion no encontrada o invalida";
            voteId = null;
          };
        };
        case (?(voterId, expiresAt, used)) {
          let expectedPrefix = callerText # ".";
          if (Text.startsWith(sessionId, #text expectedPrefix)) {
            // Sesion emitida con binding de principal ICP actual.
          } else {
            return {
              success = false;
              message = "Autenticacion invalida: la sesion no pertenece a este caller ICP";
              voteId = null;
            };
          };

          if (used) {
            return {
              success = false;
              message = "Autenticacion invalida: sesion ya utilizada";
              voteId = null;
            };
          };
          if (nowNs > expiresAt) {
            return {
              success = false;
              message = "Autenticacion invalida: sesion expirada";
              voteId = null;
            };
          };
          // Marcar sesion como usada (tanto en mapa transient como en lista estable).
          sessionMap.put(sessionId, (voterId, expiresAt, true));
          sessionStableEntries := List.map<(Text, Text, Int, Bool), (Text, Text, Int, Bool)>(
            sessionStableEntries,
            func (entry : (Text, Text, Int, Bool)) : (Text, Text, Int, Bool) {
              let (sid, vid, exp, u) = entry;
              if (sid == sessionId) { (sid, vid, exp, true) } else (sid, vid, exp, u)
            }
          );
          voterId
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