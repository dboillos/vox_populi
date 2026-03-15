import Array "mo:base/Array";
import Float "mo:base/Float";
import List "mo:base/List";
import Nat "mo:base/Nat";
import Text "mo:base/Text";

import Types "./types";

module {
  // -------------------------------------
  // Funciones de agregacion y estadistica
  // -------------------------------------
  // Este modulo agrupa calculos puros sobre listas de votos.
  // Diseno de complejidad:
  // - Evita conversiones List -> Array en rutas de agregacion.
  // - Mantiene coste lineal O(n) en cada calculo sobre votos filtrados.

  // Busca la opcion seleccionada para una pregunta concreta.
  // Devuelve null cuando la pregunta no fue respondida.
  public func getAnswerIndex(answers : [Types.AnswerSelection], questionId : Nat) : ?Nat {
    for (answer in answers.vals()) {
      if (answer.questionId == questionId) {
        return ?answer.optionIndex;
      };
    };

    null;
  };

  // Filtra votos por surveyId manteniendo la estructura de lista.
  // Este enfoque evita materializar arrays cuando no hace falta orden de insercion.
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

  // Calcula porcentaje entero con redondeo al entero mas cercano.
  // Formula: (part * 100 + total/2) / total
  public func percentage(part : Nat, total : Nat) : Nat {
    if (total == 0) {
      return 0;
    };

    (part * 100 + (total / 2)) / total;
  };

  // Media flotante segura (evita division por cero).
  public func averageFloat(sum : Float, count : Nat) : Float {
    if (count == 0) {
      return 0;
    };

    sum / Float.fromInt(count);
  };

  // Construye la distribucion porcentual de la pregunta 1.
  // El resultado usa optionIndex para que frontend traduzca etiquetas por idioma.
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

  // Construye una fila de la matriz de seguridad.
  // reverseTrust permite invertir semantica cuando la opcion 0 significa desconfianza.
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

  // Construye los 4 ejes del radar (quality, ethics, effort, savings).
  // Cada pregunta se proyecta a una escala comun de 1..5 para comparabilidad.
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

  // Calcula horas medias ahorradas a partir de la pregunta 3.
  // El resultado se redondea a 1 decimal para visualizacion estable.
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