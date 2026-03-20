import Int "mo:base/Int";
import Nat "mo:base/Nat";
import Nat32 "mo:base/Nat32";
import Principal "mo:base/Principal";
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
  // - selfId: principal del canister backend.
  // - nowNs: timestamp actual en nanosegundos.
  // - randomBlob: aleatoriedad opcional obtenida de `raw_rand`.
  // Resultado:
  // - salt estable: reutiliza el existente o genera uno nuevo.
  // Politica de generacion:
  // - Prioriza `raw_rand` cuando esta disponible.
  // - Usa fallback deterministico (selfId + nowNs) si no hay randomBlob.
  public func ensureBackendEmailSalt(
    existingSalt : Text,
    selfId : Principal,
    nowNs : Int,
    randomBlob : ?Blob,
  ) : Text {
    if (Text.size(existingSalt) > 0) {
      return existingSalt;
    };

    switch (randomBlob) {
      case (?blob) {
        "pilot-" # AuditHelpers.blobToHex(blob);
      };
      case null {
        let fallbackSeed = Principal.toText(selfId) # ":" # Nat.toText(Int.abs(nowNs));
        "pilot-fallback-" # Nat32.toText(Text.hash(fallbackSeed));
      };
    };
  };
};
