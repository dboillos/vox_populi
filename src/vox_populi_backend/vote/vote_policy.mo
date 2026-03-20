import List "mo:base/List";
import Nat "mo:base/Nat";
import Text "mo:base/Text";

import Types "../shared/types";
import Validation "../shared/validation";

// Reglas de negocio de votacion reutilizables por el actor.
//
// Diseno:
// - Modulo puro (sin estado estable, sin await, sin side effects).
// - Centraliza validaciones y politicas para mantener `main.mo` liviano.
module {
  // API CONTRACT: validateSubmitPayload
  // Parametros:
  // - surveyId: identificador de encuesta.
  // - answers: respuestas normalizadas recibidas.
  // - questionOptionCounts: cardinalidad de opciones por pregunta.
  // Resultado:
  // - `null` si el payload es valido.
  // - `?Text` con mensaje de error cuando falla alguna precondicion.
  public func validateSubmitPayload(
    surveyId : Text,
    answers : [Types.AnswerSelection],
    questionOptionCounts : [Nat],
  ) : ?Text {
    if (Text.size(surveyId) == 0) {
      return ?"El identificador de encuesta es obligatorio";
    };

    if (answers.size() == 0) {
      return ?"Debes responder al menos una pregunta";
    };

    if (Validation.hasDuplicateQuestion(answers)) {
      return ?"Hay preguntas repetidas en el voto";
    };

    for (answer in answers.vals()) {
      if (
        not Validation.isValidQuestion(answer.questionId, questionOptionCounts)
        or not Validation.isValidOption(answer.questionId, answer.optionIndex, questionOptionCounts)
      ) {
        return ?"El voto contiene respuestas fuera de rango";
      };
    };

    null;
  };

  // API CONTRACT: resolveVoterId
  // Parametros:
  // - providedVoterId: identificador aportado por cliente.
  // - callerPrincipalText: principal del caller en formato texto.
  // Resultado:
  // - `providedVoterId` si no esta vacio; en caso contrario `callerPrincipalText`.
  public func resolveVoterId(providedVoterId : Text, callerPrincipalText : Text) : Text {
    if (Text.size(providedVoterId) == 0) {
      callerPrincipalText;
    } else {
      providedVoterId;
    };
  };

  // API CONTRACT: findDuplicateVoteId
  // Parametros:
  // - storedVotes: lista persistida de votos.
  // - surveyId: encuesta objetivo.
  // - voterId: identidad anonima del votante.
  // Resultado:
  // - `?Nat` con el voteId interno del voto ya existente, o `null` si no hay duplicado.
  public func findDuplicateVoteId(
    storedVotes : List.List<Types.StoredVote>,
    surveyId : Text,
    voterId : Text,
  ) : ?Nat {
    for (vote in List.toIter(storedVotes)) {
      if (vote.surveyId == surveyId and vote.voterId == voterId) {
        return ?vote.voteId;
      };
    };

    null;
  };

  // API CONTRACT: hasUserVoted
  // Parametros:
  // - storedVotes: lista persistida de votos.
  // - surveyId: encuesta objetivo.
  // - voterId: identidad anonima del votante.
  // Resultado:
  // - true cuando existe al menos un voto para la pareja `(surveyId, voterId)`.
  public func hasUserVoted(storedVotes : List.List<Types.StoredVote>, surveyId : Text, voterId : Text) : Bool {
    switch (findDuplicateVoteId(storedVotes, surveyId, voterId)) {
      case (?_) { true };
      case null { false };
    };
  };
};
