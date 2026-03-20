import Nat32 "mo:base/Nat32";
import Prim "mo:prim";
import Text "mo:base/Text";

import Types "../shared/types";

// Modulo de utilidades de autenticacion e identidad pseudonima.
//
// Diseno:
// - Contiene helpers puros para validar issuer y construir identidades.
// - No mantiene estado ni realiza outcalls.
module {
  // API CONTRACT: isGoogleIssuer
  // Parametros:
  // - issuer: claim `iss` recibido de tokeninfo.
  // Resultado:
  // - true si coincide con un emisor oficial de Google OIDC.
  public func isGoogleIssuer(issuer : Text) : Bool {
    issuer == "https://accounts.google.com" or issuer == "accounts.google.com";
  };

  // API CONTRACT: deriveSaltedEmailVoterId
  // Parametros:
  // - email: correo institucional validado.
  // - salt: secreto estable del backend.
  // Resultado:
  // - identificador seudonimo determinista con prefijo `ehs-`.
  public func deriveSaltedEmailVoterId(email : Text, salt : Text) : Text {
    let normalizedEmail = Text.map(email, Prim.charToLower);
    let saltedHash = Text.hash(salt # ":" # normalizedEmail);
    "ehs-" # Nat32.toText(saltedHash);
  };

  // API CONTRACT: invalidToken
  // Parametros:
  // - reason: motivo tecnico/funcional del rechazo de autenticacion.
  // Resultado:
  // - estructura estandar `GoogleTokenValidation` con `isValid=false`.
  public func invalidToken(reason : Text) : Types.GoogleTokenValidation {
    {
      isValid = false;
      email = null;
      voterId = null;
      reason = reason;
    };
  };
};
