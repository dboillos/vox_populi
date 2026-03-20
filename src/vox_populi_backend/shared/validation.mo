import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import Text "mo:base/Text";
import Prim "mo:⛔";

import Types "./types";

module {
  // -----------------------
  // Reglas de validacion
  // -----------------------
  // Este modulo concentra validaciones puras (sin estado global ni side effects).

  // API CONTRACT: isValidQuestion
  // Parametros:
  // - questionId: identificador de pregunta (indexado desde 1).
  // - questionOptionCounts: cardinalidad de opciones por pregunta.
  // Resultado:
  // - true cuando `questionId` cae en el rango configurado.
  public func isValidQuestion(questionId : Nat, questionOptionCounts : [Nat]) : Bool {
    questionId >= 1 and questionId <= questionOptionCounts.size();
  };

  // API CONTRACT: isValidOption
  // Parametros:
  // - questionId: identificador de pregunta (indexado desde 1).
  // - optionIndex: opcion elegida (indexada desde 0).
  // - questionOptionCounts: cardinalidad de opciones por pregunta.
  // Resultado:
  // - true cuando la opcion existe para esa pregunta.
  public func isValidOption(questionId : Nat, optionIndex : Nat, questionOptionCounts : [Nat]) : Bool {
    if (not isValidQuestion(questionId, questionOptionCounts)) {
      return false;
    };

    optionIndex < questionOptionCounts[questionId - 1];
  };

  // API CONTRACT: hasDuplicateQuestion
  // Parametros:
  // - answers: respuestas normalizadas de un voto.
  // Resultado:
  // - true si existe al menos un `questionId` repetido.
  // Complejidad:
  // - O(n^2), suficiente para cuestionarios cortos.
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

  // API CONTRACT: isUocInstitutionalEmail
  // Parametros:
  // - email: correo a validar.
  // Resultado:
  // - true cuando termina en `@uoc.edu` tras normalizacion a minusculas.
  public func isUocInstitutionalEmail(email : Text) : Bool {
    let normalized = Text.map(email, Prim.charToLower);
    Text.endsWith(normalized, #text "@uoc.edu");
  };
};