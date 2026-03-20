import List "mo:base/List";

import Aggregations "./aggregations";
import Types "../shared/types";

// Consultas de lectura de votos para mantener el actor enfocado en orquestacion.
module {
  // API CONTRACT: surveyVotesInInsertionOrder
  // Parametros:
  // - storedVotes: lista persistida global.
  // - surveyId: encuesta objetivo.
  // Resultado:
  // - array de votos de esa encuesta en orden de insercion.
  // Nota:
  // - Internamente la lista esta en orden inverso (push al inicio),
  //   por eso se aplica `List.reverse` antes de materializar el array.
  public func surveyVotesInInsertionOrder(
    storedVotes : List.List<Types.StoredVote>,
    surveyId : Text,
  ) : [Types.StoredVote] {
    let surveyVotes = Aggregations.getVotesBySurvey(storedVotes, surveyId);
    toInsertionOrderArray(surveyVotes);
  };

  // API CONTRACT: toInsertionOrderArray
  // Parametros:
  // - surveyVotes: lista de votos ya filtrada por encuesta.
  // Resultado:
  // - array en orden de insercion (mas antiguo -> mas reciente).
  public func toInsertionOrderArray(surveyVotes : List.List<Types.StoredVote>) : [Types.StoredVote] {
    List.toArray(List.reverse(surveyVotes));
  };
};
