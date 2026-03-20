import HashMap "mo:base/HashMap";
import Int "mo:base/Int";
import List "mo:base/List";
import Nat "mo:base/Nat";
import Text "mo:base/Text";

import Types "../shared/types";
import VotePolicy "./vote_policy";
import VotingService "./voting_service";

// Servicio runtime de voto para desacoplar al actor de indices/caches en memoria.
//
// Diseno:
// - Mantiene logica de clave compuesta y mutacion de estructuras transient fuera de `main.mo`.
// - El actor solo pasa estado/indices y persiste el resultado estable.
module {
  // API CONTRACT: VoteLookup
  // - Indice O(1) promedio para detectar voto existente por (surveyId, voterId).
  public type VoteLookup = HashMap.HashMap<Text, Nat>;

  // API CONTRACT: SurveyVotesCache
  // - Cache en memoria por encuesta para consultas agregadas y respuestas crudas.
  public type SurveyVotesCache = HashMap.HashMap<Text, List.List<Types.StoredVote>>;

  // API CONTRACT: SubmitWithIndexesResult
  // Resultado compuesto con estado persistible + espejo estable del indice de duplicados.
  public type SubmitWithIndexesResult = {
    response : Types.VoteResponse;
    storedVotes : List.List<Types.StoredVote>;
    nextVoteId : Nat;
    voteLookupEntries : List.List<(Text, Text, Nat)>;
  };

  func voteLookupKey(surveyId : Text, voterId : Text) : Text {
    surveyId # "||#||" # voterId;
  };

  // API CONTRACT: buildVoteLookup
  // Parametros:
  // - entries: espejo estable (surveyId, voterId, voteId).
  // Resultado:
  // - hashmap en memoria para busquedas O(1) promedio.
  public func buildVoteLookup(entries : List.List<(Text, Text, Nat)>) : VoteLookup {
    let lookup = HashMap.HashMap<Text, Nat>(64, Text.equal, Text.hash);
    for ((surveyId, voterId, voteId) in List.toIter(entries)) {
      lookup.put(voteLookupKey(surveyId, voterId), voteId);
    };
    lookup;
  };

  // API CONTRACT: buildSurveyVotesCache
  // Parametros:
  // - storedVotes: historico global de votos.
  // Resultado:
  // - cache por encuesta en formato List.
  public func buildSurveyVotesCache(storedVotes : List.List<Types.StoredVote>) : SurveyVotesCache {
    let cache = HashMap.HashMap<Text, List.List<Types.StoredVote>>(64, Text.equal, Text.hash);
    for (vote in List.toIter(storedVotes)) {
      let existing =
        switch (cache.get(vote.surveyId)) {
          case (?surveyVotes) { surveyVotes };
          case null { List.nil<Types.StoredVote>() };
        };
      cache.put(vote.surveyId, List.push(vote, existing));
    };
    cache;
  };

  // API CONTRACT: hasUserVoted
  // Parametros:
  // - voteLookup: indice de duplicados en memoria.
  // - surveyId/voterId: clave logica de consulta.
  // Resultado:
  // - true cuando existe voto previo para esa pareja.
  public func hasUserVoted(voteLookup : VoteLookup, surveyId : Text, voterId : Text) : Bool {
    switch (voteLookup.get(voteLookupKey(surveyId, voterId))) {
      case (?_) { true };
      case null { false };
    };
  };

  // API CONTRACT: submitVoteWithIndexes
  // Parametros:
  // - voteLookup/surveyVotesCache: indices transient en memoria.
  // - storedVotes/nextVoteId/voteLookupEntries: estado actual persistible.
  // - surveyId/voterId/answers: payload de voto.
  // - callerPrincipalText: fallback de identidad cuando voterId viene vacio.
  // - nowNs: timestamp de red en nanosegundos.
  // - questionOptionCounts: cardinalidad por pregunta.
  // Resultado:
  // - respuesta funcional + nuevo estado persistible.
  // Efectos en estructuras transient:
  // - actualiza voteLookup y surveyVotesCache cuando el voto se persiste.
  public func submitVoteWithIndexes(
    voteLookup : VoteLookup,
    surveyVotesCache : SurveyVotesCache,
    storedVotes : List.List<Types.StoredVote>,
    nextVoteId : Nat,
    voteLookupEntries : List.List<(Text, Text, Nat)>,
    surveyId : Text,
    voterId : Text,
    answers : [Types.AnswerSelection],
    callerPrincipalText : Text,
    nowNs : Int,
    questionOptionCounts : [Nat],
  ) : SubmitWithIndexesResult {
    let resolvedVoterId = VotePolicy.resolveVoterId(voterId, callerPrincipalText);
    let duplicateVoteId = voteLookup.get(voteLookupKey(surveyId, resolvedVoterId));

    let result = VotingService.submitVote(
      storedVotes,
      nextVoteId,
      surveyId,
      resolvedVoterId,
      answers,
      duplicateVoteId,
      nowNs,
      questionOptionCounts,
    );

    var updatedVoteLookupEntries = voteLookupEntries;

    switch (result.newVote) {
      case (?newVote) {
        voteLookup.put(voteLookupKey(newVote.surveyId, newVote.voterId), newVote.voteId);
        updatedVoteLookupEntries := List.push((newVote.surveyId, newVote.voterId, newVote.voteId), updatedVoteLookupEntries);

        let existing =
          switch (surveyVotesCache.get(newVote.surveyId)) {
            case (?votes) { votes };
            case null { List.nil<Types.StoredVote>() };
          };
        surveyVotesCache.put(newVote.surveyId, List.push(newVote, existing));
      };
      case null {};
    };

    {
      response = result.response;
      storedVotes = result.storedVotes;
      nextVoteId = result.nextVoteId;
      voteLookupEntries = updatedVoteLookupEntries;
    };
  };

  // API CONTRACT: getSurveyVotes
  // Parametros:
  // - surveyVotesCache: cache en memoria por encuesta.
  // - surveyId: encuesta objetivo.
  // Resultado:
  // - lista de votos de la encuesta (o lista vacia).
  public func getSurveyVotes(surveyVotesCache : SurveyVotesCache, surveyId : Text) : List.List<Types.StoredVote> {
    switch (surveyVotesCache.get(surveyId)) {
      case (?votes) { votes };
      case null { List.nil<Types.StoredVote>() };
    };
  };

  // API CONTRACT: getAggregatedResultsFromCache
  // Parametros:
  // - surveyVotesCache: cache en memoria por encuesta.
  // - surveyId: encuesta objetivo.
  // Resultado:
  // - agregaciones del dashboard para esa encuesta.
  public func getAggregatedResultsFromCache(surveyVotesCache : SurveyVotesCache, surveyId : Text) : Types.AggregatedResults {
    VotingService.getAggregatedResultsFromSurveyVotes(getSurveyVotes(surveyVotesCache, surveyId));
  };

  // API CONTRACT: getRawResponsesFromCache
  // Parametros:
  // - surveyVotesCache: cache en memoria por encuesta.
  // - surveyId: encuesta objetivo.
  // Resultado:
  // - respuestas crudas en orden de insercion.
  public func getRawResponsesFromCache(surveyVotesCache : SurveyVotesCache, surveyId : Text) : [Types.RawResponse] {
    VotingService.getRawResponsesFromSurveyVotes(getSurveyVotes(surveyVotesCache, surveyId));
  };
};