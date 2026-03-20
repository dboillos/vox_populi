import Nat "mo:base/Nat";

// Configuracion compartida del cuestionario.
//
// Objetivo:
// - Centralizar constantes de dominio reutilizables por actor y servicios.
module {
  // API CONTRACT: questionOptionCounts
  // Descripcion:
  // - Cardinalidad de opciones por pregunta (questionId indexado desde 1).
  // Ejemplo:
  // - `questionOptionCounts[0] = 6` implica que la pregunta 1 tiene opciones 0..5.
  public let questionOptionCounts : [Nat] = [6, 5, 4, 5, 4, 3, 4, 3, 3, 3, 3, 3];
};
