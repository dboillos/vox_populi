import Text "mo:base/Text";
import Blob "mo:base/Blob";

import AuditHelpers "../audit/audit_helpers";

// Gestion del salt secreto para derivacion de `voterId`.
//
// Diseno:
// - Modulo puro y determinista a partir de entradas.
// - El actor decide persistencia del resultado en `stable var`.
module {
  // API CONTRACT: ensureBackendEmailSalt
  // Parametros:
  // - existingSalt: valor actual persistido (puede venir vacio).
  // - randomBlob: aleatoriedad opcional obtenida de `raw_rand`.
  // Resultado:
  // - `?Text` con salt estable: reutiliza el existente o genera uno nuevo.
  // - `null` cuando no existe salt previo y no hay aleatoriedad disponible.
  // Politica de generacion:
  // - Prioriza `raw_rand` cuando esta disponible.
  // - No usa fallback con datos publicos para no degradar anonimato.
  public func ensureBackendEmailSalt(
    existingSalt : Text,
    randomBlob : ?Blob,
  ) : ?Text {
    if (Text.size(existingSalt) > 0) {
      return ?existingSalt;
    };

    switch (randomBlob) {
      case (?blob) {
        ?("pilot-" # AuditHelpers.blobToHex(blob));
      };
      case null {
        null;
      };
    };
  };
};
