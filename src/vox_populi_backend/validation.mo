import Iter "mo:base/Iter";
import Nat "mo:base/Nat";

import Types "./types";

module {
  // -----------------------
  // Reglas de validacion
  // -----------------------
  // Este modulo concentra validaciones puras (sin estado global).

  // Valida que questionId exista dentro del cuestionario configurado.
  // El rango valido es 1..questionOptionCounts.size().
  public func isValidQuestion(questionId : Nat, questionOptionCounts : [Nat]) : Bool {
    questionId >= 1 and questionId <= questionOptionCounts.size();
  };

  // Valida que optionIndex pertenezca al rango permitido de la pregunta.
  // Ejemplo: si una pregunta tiene 4 opciones, los indices validos son 0..3.
  public func isValidOption(questionId : Nat, optionIndex : Nat, questionOptionCounts : [Nat]) : Bool {
    if (not isValidQuestion(questionId, questionOptionCounts)) {
      return false;
    };

    optionIndex < questionOptionCounts[questionId - 1];
  };

  // Detecta si un mismo voto contiene la misma pregunta repetida.
  // Implementacion O(n^2) suficiente para encuestas cortas.
  // Ventaja: no requiere estructuras auxiliares ni hashing.
  public func hasDuplicateQuestion(answers : [Types.AnswerSelection]) : Bool {
    if (answers.size() < 2) {
      return false;
    };

    for (left in Iter.range(0, answers.size() - 2)) {
      for (right in Iter.range(left + 1, answers.size() - 1)) {
        if (answers[left].questionId == answers[right].questionId) {
          return true;
        };
      };
    };

    false;
  };
};