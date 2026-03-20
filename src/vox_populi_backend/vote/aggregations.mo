import Array "mo:base/Array";
import Float "mo:base/Float";
import List "mo:base/List";
import Nat "mo:base/Nat";
import Text "mo:base/Text";

import Types "../shared/types";

module {
  // -------------------------------------
  // Funciones de agregacion y estadistica
  // -------------------------------------
  // Este modulo agrupa calculos puros sobre listas de votos.
  // Diseno de complejidad:
  // - Evita conversiones List -> Array en rutas de agregacion.
  // - Mantiene coste lineal O(n) en cada calculo sobre votos filtrados.

  // API CONTRACT: getAnswerIndex
  // Parametros:
  // - answers: respuestas normalizadas de un voto.
  // - questionId: pregunta objetivo.
  // Resultado:
  // - `?Nat` con el optionIndex seleccionado, o `null` si no existe respuesta.
  public func getAnswerIndex(answers : [Types.AnswerSelection], questionId : Nat) : ?Nat {
    for (answer in answers.vals()) {
      if (answer.questionId == questionId) {
        return ?answer.optionIndex;
      };
    };

    null;
  };

  // API CONTRACT: getVotesBySurvey
  // Parametros:
  // - storedVotes: lista global de votos persistidos.
  // - surveyId: identificador de encuesta.
  // Resultado:
  // - sublista con solo votos de la encuesta indicada.
  // Nota:
  // - Conserva estructura `List` para evitar conversiones innecesarias a array.
  public func getVotesBySurvey(storedVotes : List.List<Types.StoredVote>, surveyId : Text) : List.List<Types.StoredVote> {
    switch (storedVotes) {
      case null { null };
      case (?(head, tail)) {
        let filteredTail = getVotesBySurvey(tail, surveyId);
        if (head.surveyId == surveyId) {
          ?(head, filteredTail);
        } else {
          filteredTail;
        };
      };
    };
  };

  // API CONTRACT: percentage
  // Parametros:
  // - part: numerador.
  // - total: denominador.
  // Resultado:
  // - porcentaje entero redondeado al entero mas cercano.
  // Formula:
  // - (part * 100 + total/2) / total
  public func percentage(part : Nat, total : Nat) : Nat {
    if (total == 0) {
      return 0;
    };

    (part * 100 + (total / 2)) / total;
  };

  // API CONTRACT: averageFloat
  // Parametros:
  // - sum: suma acumulada.
  // - count: numero de elementos.
  // Resultado:
  // - media aritmetica en float, o 0 cuando count es 0.
  public func averageFloat(sum : Float, count : Nat) : Float {
    if (count == 0) {
      return 0;
    };

    sum / Float.fromInt(count);
  };

  // API CONTRACT: buildToolDistribution
  // Parametros:
  // - votes: votos filtrados de una encuesta.
  // Resultado:
  // - distribucion porcentual por optionIndex para la pregunta 1.
  // Nota:
  // - El frontend resuelve etiquetas segun idioma a partir de optionIndex.
  public func buildToolDistribution(votes : List.List<Types.StoredVote>) : [Types.ToolDistributionItem] {
    let counts = Array.init<Nat>(6, 0);
    var totalVotes : Nat = 0;

    for (vote in List.toIter(votes)) {
      totalVotes += 1;
      switch (getAnswerIndex(vote.answers, 1)) {
        case (?optionIndex) {
          counts[optionIndex] := counts[optionIndex] + 1;
        };
        case null {};
      };
    };

    Array.tabulate<Types.ToolDistributionItem>(6, func(optionIndex : Nat) : Types.ToolDistributionItem {
      {
        optionIndex = optionIndex;
        value = percentage(counts[optionIndex], totalVotes);
      };
    });
  };

  // API CONTRACT: buildSecurityRow
  // Parametros:
  // - votes: votos filtrados de una encuesta.
  // - questionId: pregunta que alimenta la fila.
  // - category: clave semantica de la categoria.
  // - reverseTrust: invierte la semantica de confianza cuando aplica.
  // Resultado:
  // - fila con porcentajes de confia/neutral/desconfia.
  public func buildSecurityRow(votes : List.List<Types.StoredVote>, questionId : Nat, category : Text, reverseTrust : Bool) : Types.SecurityMatrixRow {
    var trustCount : Nat = 0;
    var neutralCount : Nat = 0;
    var distrustCount : Nat = 0;
    var answeredCount : Nat = 0;

    for (vote in List.toIter(votes)) {
      switch (getAnswerIndex(vote.answers, questionId)) {
        case (?optionIndex) {
          answeredCount += 1;

          if (reverseTrust) {
            if (optionIndex == 0) {
              distrustCount += 1;
            } else if (optionIndex == 1) {
              trustCount += 1;
            } else {
              neutralCount += 1;
            };
          } else {
            if (optionIndex == 0) {
              trustCount += 1;
            } else if (optionIndex == 1) {
              neutralCount += 1;
            } else {
              distrustCount += 1;
            };
          };
        };
        case null {};
      };
    };

    {
      category = category;
      confia = percentage(trustCount, answeredCount);
      neutral = percentage(neutralCount, answeredCount);
      desconfia = percentage(distrustCount, answeredCount);
    };
  };

  // API CONTRACT: buildImpactRadar
  // Parametros:
  // - votes: votos filtrados de una encuesta.
  // Resultado:
  // - cuatro ejes de radar (`quality`, `ethics`, `effort`, `savings`) en escala 1..5.
  // Nota:
  // - Incluye mapeos por pregunta para llevar distintas escalas a un marco comun.
  public func buildImpactRadar(votes : List.List<Types.StoredVote>) : [Types.RadarPoint] {
    var qualitySum : Float = 0;
    var qualityCount : Nat = 0;
    var ethicsSum : Float = 0;
    var ethicsCount : Nat = 0;
    var effortSum : Float = 0;
    var effortCount : Nat = 0;
    var savingsSum : Float = 0;
    var savingsCount : Nat = 0;

    for (vote in List.toIter(votes)) {
      switch (getAnswerIndex(vote.answers, 4)) {
        case (?optionIndex) {
          qualitySum += Float.fromInt(optionIndex + 1);
          qualityCount += 1;
        };
        case null {};
      };

      switch (getAnswerIndex(vote.answers, 5)) {
        case (?optionIndex) {
          // Mapeo de etica (pregunta 5) a escala 1..5.
          let mappedValue =
            if (optionIndex == 0) {
              5;
            } else if (optionIndex == 1) {
              4;
            } else if (optionIndex == 2) {
              1;
            } else {
              2;
            };

          ethicsSum += Float.fromInt(mappedValue);
          ethicsCount += 1;
        };
        case null {};
      };

      switch (getAnswerIndex(vote.answers, 6)) {
        case (?optionIndex) {
          // Mapeo de esfuerzo (pregunta 6) a escala 1..5.
          let mappedValue =
            if (optionIndex == 0) {
              1;
            } else if (optionIndex == 1) {
              5;
            } else {
              3;
            };

          effortSum += Float.fromInt(mappedValue);
          effortCount += 1;
        };
        case null {};
      };

      switch (getAnswerIndex(vote.answers, 3)) {
        case (?optionIndex) {
          // Mapeo de ahorro percibido (pregunta 3) a escala 1..5 para radar.
          let mappedValue =
            if (optionIndex == 0) {
              1.0;
            } else if (optionIndex == 1) {
              2.5;
            } else if (optionIndex == 2) {
              3.8;
            } else {
              5.0;
            };

          savingsSum += mappedValue;
          savingsCount += 1;
        };
        case null {};
      };
    };

    [
      {
        axis = "quality";
        value = averageFloat(qualitySum, qualityCount);
        fullMark = 5;
      },
      {
        axis = "ethics";
        value = averageFloat(ethicsSum, ethicsCount);
        fullMark = 5;
      },
      {
        axis = "effort";
        value = averageFloat(effortSum, effortCount);
        fullMark = 5;
      },
      {
        axis = "savings";
        value = averageFloat(savingsSum, savingsCount);
        fullMark = 5;
      },
    ];
  };

  // API CONTRACT: averageHoursSaved
  // Parametros:
  // - votes: votos filtrados de una encuesta.
  // Resultado:
  // - media de horas ahorradas (pregunta 3), redondeada a 1 decimal.
  public func averageHoursSaved(votes : List.List<Types.StoredVote>) : Float {
    var totalHours : Float = 0;
    var answeredCount : Nat = 0;

    for (vote in List.toIter(votes)) {
      switch (getAnswerIndex(vote.answers, 3)) {
        case (?optionIndex) {
          // Mapeo directo de categorias de respuesta a horas estimadas.
          let mappedHours =
            if (optionIndex == 0) {
              0.5;
            } else if (optionIndex == 1) {
              2.0;
            } else if (optionIndex == 2) {
              5.5;
            } else {
              8.0;
            };

          totalHours += mappedHours;
          answeredCount += 1;
        };
        case null {};
      };
    };

    let average = averageFloat(totalHours, answeredCount);
    Float.nearest(average * 10.0) / 10.0;
  };
};