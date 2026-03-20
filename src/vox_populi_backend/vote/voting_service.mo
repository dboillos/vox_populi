import Array "mo:base/Array";
import Int "mo:base/Int";
import List "mo:base/List";
import Nat "mo:base/Nat";
import Text "mo:base/Text";

import Aggregations "./aggregations";
import Types "../shared/types";
import VotePolicy "./vote_policy";
import VoteQueries "./vote_queries";

// Servicio de dominio de votacion.
//
// Objetivo:
// - Encapsular reglas de escritura y consultas de resultados fuera del actor.
module {
  // API CONTRACT: SubmitVoteResult
  // Resultado compuesto para que el actor persista estado actualizado.
  public type SubmitVoteResult = {
    response : Types.VoteResponse;
    storedVotes : List.List<Types.StoredVote>;
    nextVoteId : Nat;
    newVote : ?Types.StoredVote;
  };

  // API CONTRACT: submitVote
  // Parametros:
  // - storedVotes: estado actual de votos.
  // - nextVoteId: secuencia actual de ids internos.
  // - surveyId/voterId/answers: payload de voto.
  // - callerPrincipalText: principal del caller en texto para fallback de identidad.
  // - nowNs: timestamp actual en nanosegundos.
  // - questionOptionCounts: cardinalidad por pregunta.
  // Resultado:
  // - respuesta funcional y nuevo estado persistible.
  public func submitVote(
    storedVotes : List.List<Types.StoredVote>,
    nextVoteId : Nat,
    surveyId : Text,
    resolvedVoterId : Text,
    answers : [Types.AnswerSelection],
    duplicateVoteId : ?Nat,
    nowNs : Int,
    questionOptionCounts : [Nat],
  ) : SubmitVoteResult {
    switch (VotePolicy.validateSubmitPayload(surveyId, answers, questionOptionCounts)) {
      case (?errorMessage) {
        return {
          response = {
            success = false;
            message = errorMessage;
            voteId = null;
          };
          storedVotes = storedVotes;
          nextVoteId = nextVoteId;
          newVote = null;
        };
      };
      case null {};
    };

    switch (duplicateVoteId) {
      case (?duplicateVoteId) {
        return {
          response = {
            success = false;
            message = "Este usuario ya ha votado en esta encuesta";
            voteId = ?("vote-" # Nat.toText(duplicateVoteId));
          };
          storedVotes = storedVotes;
          nextVoteId = nextVoteId;
          newVote = null;
        };
      };
      case null {};
    };

    let currentTimestamp = Int.abs(nowNs / 1_000_000);
    let newVote : Types.StoredVote = {
      voteId = nextVoteId;
      surveyId = surveyId;
      voterId = resolvedVoterId;
      timestamp = currentTimestamp;
      answers = answers;
    };

    let updatedVotes = List.push(newVote, storedVotes);
    let updatedNextVoteId = nextVoteId + 1;

    {
      response = {
        success = true;
        message = "Voto registrado correctamente";
        voteId = ?("vote-" # Nat.toText(newVote.voteId));
      };
      storedVotes = updatedVotes;
      nextVoteId = updatedNextVoteId;
      newVote = ?newVote;
    };
  };

  // API CONTRACT: hasUserVoted
  // Parametros:
  // - storedVotes: lista persistida de votos.
  // - surveyId/voterId: clave logica de busqueda.
  // Resultado:
  // - true cuando ya existe voto para `(surveyId, voterId)`.
  public func hasUserVoted(storedVotes : List.List<Types.StoredVote>, surveyId : Text, voterId : Text) : Bool {
    VotePolicy.hasUserVoted(storedVotes, surveyId, voterId);
  };

  // API CONTRACT: getAggregatedResults
  // Parametros:
  // - storedVotes: lista persistida de votos.
  // - surveyId: encuesta objetivo.
  // Resultado:
  // - objeto agregado completo para dashboard.
  public func getAggregatedResults(storedVotes : List.List<Types.StoredVote>, surveyId : Text) : Types.AggregatedResults {
    let votes = Aggregations.getVotesBySurvey(storedVotes, surveyId);
    getAggregatedResultsFromSurveyVotes(votes);
  };

  // API CONTRACT: getAggregatedResultsFromSurveyVotes
  // Parametros:
  // - votes: votos ya filtrados por encuesta.
  // Resultado:
  // - objeto agregado completo para dashboard.
  public func getAggregatedResultsFromSurveyVotes(votes : List.List<Types.StoredVote>) : Types.AggregatedResults {
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

  // API CONTRACT: getRawResponses
  // Parametros:
  // - storedVotes: lista persistida de votos.
  // - surveyId: encuesta objetivo.
  // Resultado:
  // - respuestas crudas en orden de insercion.
  public func getRawResponses(storedVotes : List.List<Types.StoredVote>, surveyId : Text) : [Types.RawResponse] {
    let votes = VoteQueries.surveyVotesInInsertionOrder(storedVotes, surveyId);
    buildRawResponses(votes);
  };

  // API CONTRACT: getRawResponsesFromSurveyVotes
  // Parametros:
  // - surveyVotes: votos ya filtrados por encuesta.
  // Resultado:
  // - respuestas crudas en orden de insercion.
  public func getRawResponsesFromSurveyVotes(surveyVotes : List.List<Types.StoredVote>) : [Types.RawResponse] {
    let votes = VoteQueries.toInsertionOrderArray(surveyVotes);
    buildRawResponses(votes);
  };

  func buildRawResponses(votes : [Types.StoredVote]) : [Types.RawResponse] {

    Array.tabulate<Types.RawResponse>(votes.size(), func(index : Nat) : Types.RawResponse {
      let vote = votes[index];
      {
        numero = index + 1;
        voterId = vote.voterId;
        timestamp = vote.timestamp;
        answers = vote.answers;
      };
    });
  };
};
