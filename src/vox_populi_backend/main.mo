import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Int "mo:base/Int";
import List "mo:base/List";
import Nat "mo:base/Nat";
import Nat8 "mo:base/Nat8";
import Principal "mo:base/Principal";
import Text "mo:base/Text";
import Time "mo:base/Time";

import Aggregations "./aggregations";
import Types "./types";
import Validation "./validation";

// Actor persistente del dominio de votaciones.
//
// Diseno general:
// - Este archivo funciona como capa de orquestacion y API publica.
// - Los tipos compartidos viven en types.mo.
// - Las reglas de validacion viven en validation.mo.
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

  // -----------------------------
  // Estado persistente del actor
  // -----------------------------

  // Contador incremental para generar identificadores de voto legibles.
  stable var nextVoteId : Nat = 1;
  // Almacen principal de votos en lista enlazada.
  // Ventaja: insercion O(1) con List.push sin copiar todo el historico.
  // Nota: la lista guarda los votos mas recientes al inicio.
  // Enfoque de rendimiento del backend:
  // - Escritura (submitVote): O(1) por insercion.
  // - Lectura/cálculo (queries agregadas): O(n) sobre votos filtrados.
  stable var storedVotes : List.List<Types.StoredVote> = List.nil<Types.StoredVote>();
  // Version de la logica de negocio del cuestionario.
  // Se expone por auditoria en getAuditData.
  let surveyCodeVersion : Text = "1.0.0";

  // Mapa de cardinalidad por pregunta (indexado desde questionId = 1).
  // Ejemplo: la pregunta 1 permite 6 opciones (indices 0..5).
  let questionOptionCounts : [Nat] = [6, 5, 4, 5, 4, 3, 4, 3, 3, 3, 3, 3];

  // Subset de la interfaz del IC Management Canister necesario para canister_status.
  // Para que funcione, este canister debe estar en su propia lista de controladores:
  //   dfx canister update-settings vox_populi_backend --add-controller <canister-id>
  let IC = actor "aaaaa-aa" : actor {
    canister_status : shared ({ canister_id : Principal }) -> async {
      module_hash : ?Blob;
      cycles : Nat;
      memory_size : Nat;
    };
  };

  // Convierte un Blob de bytes a cadena hexadecimal en minusculas.
  // Usado para formatear el module_hash devuelto por canister_status.
  func blobToHex(b : Blob) : Text {
    let bytes = Blob.toArray(b);
    let chars = ["0","1","2","3","4","5","6","7","8","9","a","b","c","d","e","f"];
    var hex = "";
    for (byte in bytes.vals()) {
      let n = Nat8.toNat(byte);
      hex #= chars[n / 16] # chars[n % 16];
    };
    hex
  };

  // Materializa solo los votos de una encuesta en orden de insercion.
  // Se usa en endpoints que requieren array ordenado (p. ej. exportacion cruda).
  func surveyVotesInInsertionOrder(surveyId : Text) : [Types.StoredVote] {
    let surveyVotes = Aggregations.getVotesBySurvey(storedVotes, surveyId);
    List.toArray(List.reverse(surveyVotes));
  };

  // ---------------------------------
  // Endpoint de escritura (update call)
  // ---------------------------------

  // API CONTRACT: submitVote (update)
  // Parametros:
  // - surveyId: identificador logico de la encuesta.
  // - voterId: identificador anonimo del votante; si viene vacio, se usa caller.
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
  // - encuesta obligatoria, respuestas vacias, preguntas repetidas,
  //   respuestas fuera de rango, o voto duplicado (si se reactiva bloqueo).
  // Complejidad aproximada: O(n + m), donde n=answers, m=votos persistidos
  // (solo cuando el bloqueo de duplicados esta activo).
  // Registra un voto con validacion de integridad del payload.
  // Flujo resumido:
  // 1) valida surveyId y que exista al menos una respuesta.
  // 2) valida duplicados y rangos de pregunta/opcion.
  // 3) resuelve voterId (si viene vacio, usa caller).
  // 4) persiste el voto y devuelve voteId.
  // NOTA (modo pruebas): la validacion de voto repetido esta desactivada temporalmente.
  // Para volver al comportamiento de un voto por usuario+encuesta, descomenta el bloque marcado mas abajo.
  public shared ({ caller }) func submitVote(
    surveyId : Text,
    voterId : Text,
    answers : [AnswerSelection],
    _timestamp : Nat,
  ) : async VoteResponse {
    if (Text.size(surveyId) == 0) {
      return {
        success = false;
        message = "El identificador de encuesta es obligatorio";
        voteId = null;
      };
    };

    if (answers.size() == 0) {
      return {
        success = false;
        message = "Debes responder al menos una pregunta";
        voteId = null;
      };
    };

    if (Validation.hasDuplicateQuestion(answers)) {
      return {
        success = false;
        message = "Hay preguntas repetidas en el voto";
        voteId = null;
      };
    };

    for (answer in answers.vals()) {
      if (
        not Validation.isValidQuestion(answer.questionId, questionOptionCounts)
        or not Validation.isValidOption(answer.questionId, answer.optionIndex, questionOptionCounts)
      ) {
        return {
          success = false;
          message = "El voto contiene respuestas fuera de rango";
          voteId = null;
        };
      };
    };

    // Si el cliente no aporta voterId, usamos el principal del caller como fallback.
    let resolvedVoterId =
      if (Text.size(voterId) == 0) {
        Principal.toText(caller);
      } else {
        voterId;
      };

    // --- REACTIVAR PARA BLOQUEAR VOTOS REPETIDOS ---
    // for (vote in List.toIter(storedVotes)) {
    //   if (vote.surveyId == surveyId and vote.voterId == resolvedVoterId) {
    //     return {
    //       success = false;
    //       message = "Este usuario ya ha votado en esta encuesta";
    //       voteId = ?("vote-" # Nat.toText(vote.voteId));
    //     };
    //   };
    // };

    // Tiempo de red del canister (ms epoch) derivado de Time.now() en nanosegundos.
    let currentTimestamp = Int.abs(Time.now() / 1_000_000);

    // Construimos el registro persistente del voto.
    let newVote : Types.StoredVote = {
      voteId = nextVoteId;
      surveyId = surveyId;
      voterId = resolvedVoterId;
      timestamp = currentTimestamp;
      answers = answers;
    };

    // Insercion O(1): anadimos al inicio sin copiar el historico completo.
    // Este punto materializa la decision de priorizar escrituras baratas en ciclos.
    storedVotes := List.push(newVote, storedVotes);
    nextVoteId += 1;

    {
      success = true;
      message = "Voto registrado correctamente";
      voteId = ?("vote-" # Nat.toText(newVote.voteId));
    };
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
  // Complejidad aproximada: O(m), m=votos persistidos en la encuesta.
  // Consulta booleana para detectar si un identificador ya voto en una encuesta.
  // Se usa principalmente para UX (bloquear o avisar antes de entrar a votar).
  public query func hasUserVoted(surveyId : Text, voterId : Text) : async Bool {
    for (vote in List.toIter(storedVotes)) {
      if (vote.surveyId == surveyId and vote.voterId == voterId) {
        return true;
      };
    };

    false;
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
    let votes = Aggregations.getVotesBySurvey(storedVotes, surveyId);
    var trustCount : Nat = 0;
    var trustAnsweredCount : Nat = 0;
    var icpCount : Nat = 0;
    var icpAnsweredCount : Nat = 0;
    var totalVotes : Nat = 0;

    for (vote in List.toIter(votes)) {
      totalVotes += 1;
      switch (Aggregations.getAnswerIndex(vote.answers, 10)) {
        case (?optionIndex) {
          trustAnsweredCount += 1;
          if (optionIndex == 0) {
            trustCount += 1;
          };
        };
        case null {};
      };

      switch (Aggregations.getAnswerIndex(vote.answers, 12)) {
        case (?optionIndex) {
          icpAnsweredCount += 1;
          if (optionIndex == 0) {
            icpCount += 1;
          };
        };
        case null {};
      };
    };

    // El objeto final combina:
    // - conteos globales (totalVotes)
    // - porcentajes (trust / icp)
    // - metricas derivadas (horas medias, radar, matriz)
    {
      totalVotes = totalVotes;
      blockchainTrustPercentage = Aggregations.percentage(trustCount, trustAnsweredCount);
      averageHoursSaved = Aggregations.averageHoursSaved(votes);
      toolDistribution = Aggregations.buildToolDistribution(votes);
      impactRadar = Aggregations.buildImpactRadar(votes);
      securityMatrix = [
        Aggregations.buildSecurityRow(votes, 8, "uocId", true),
        Aggregations.buildSecurityRow(votes, 9, "anonymousId", false),
        Aggregations.buildSecurityRow(votes, 10, "immutability", false),
      ];
      icpPreference = Aggregations.percentage(icpCount, icpAnsweredCount);
    };
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
    let votes = surveyVotesInInsertionOrder(surveyId);

    Array.tabulate<RawResponse>(votes.size(), func(index : Nat) : RawResponse {
      let vote = votes[index];
      {
        numero = index + 1;
        voterId = vote.voterId;
        timestamp = vote.timestamp;
        answers = vote.answers;
      };
    });
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
    let selfId = Principal.fromActor(Self);
    var moduleHashText = "Error: canister no es su propio controlador";
    var cyclesText = "No disponible";
    try {
      let status = await IC.canister_status({ canister_id = selfId });
      moduleHashText := switch (status.module_hash) {
        case (?hash) { blobToHex(hash) };
        case null { "No desplegado" };
      };
      cyclesText := Nat.toText(status.cycles);
    } catch (_) {
      moduleHashText := "Error: configure el canister como su propio controlador";
    };
    {
      canisterId = Principal.toText(selfId);
      wasmModuleHash = moduleHashText;
      cyclesBalance = cyclesText;
      codeVersion = surveyCodeVersion;
    };
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
    try {
      let status = await IC.canister_status({ canister_id = canisterId });
      switch (status.module_hash) {
        case (?hash) { blobToHex(hash) };
        case null { "No desplegado" };
      };
    } catch (_) {
      "Error: el backend no es controlador de ese canister";
    };
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