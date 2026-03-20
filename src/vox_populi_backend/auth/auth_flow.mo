import Blob "mo:base/Blob";
import Int "mo:base/Int";
import Text "mo:base/Text";

import AuthHelpers "./auth_helpers";
import TokenInfoParser "./tokeninfo_parser";
import Types "../shared/types";
import Validation "../shared/validation";

// Flujos de autenticacion OIDC desacoplados del actor principal.
//
// Diseno:
// - Modulo de orquestacion funcional (sin estado estable propio).
// - El actor aporta tiempo, salt y realiza outcalls de red.
module {
  // API CONTRACT: validateGoogleIdentityClaims
  // Parametros:
  // - claims: claims minimos extraidos del id_token.
  // - expectedAudience: OAuth client_id esperado.
  // - nowSec: tiempo actual en segundos epoch.
  // Resultado:
  // - true si las claims cumplen reglas de seguridad institucional.
  public func validateGoogleIdentityClaims(
    claims : Types.GoogleIdentityClaims,
    expectedAudience : Text,
    nowSec : Nat,
  ) : Bool {
    if (not claims.emailVerified) {
      return false;
    };

    if (not Validation.isUocInstitutionalEmail(claims.email)) {
      return false;
    };

    if (Text.size(expectedAudience) == 0 or claims.audience != expectedAudience) {
      return false;
    };

    if (not AuthHelpers.isGoogleIssuer(claims.issuer)) {
      return false;
    };

    if (claims.expiresAtSec <= nowSec) {
      return false;
    };

    true;
  };

  // API CONTRACT: decodeUtf8Body
  // Parametros:
  // - body: bytes del cuerpo HTTP.
  // Resultado:
  // - `?Text` con el cuerpo decodificado UTF-8, o null si no es valido.
  public func decodeUtf8Body(body : [Nat8]) : ?Text {
    Text.decodeUtf8(Blob.fromArray(body));
  };

  // API CONTRACT: evaluateGoogleTokenInfo
  // Parametros:
  // - bodyText: payload tokeninfo en texto.
  // - expectedAudience: OAuth client_id esperado.
  // - nowSec: tiempo actual en segundos epoch.
  // Resultado:
  // - `GoogleTokenValidation` final (valido o error con motivo).
  public func evaluateGoogleTokenInfo(
    bodyText : Text,
    expectedAudience : Text,
    nowSec : Nat,
  ) : Types.GoogleTokenValidation {
    let compactBodyText = TokenInfoParser.compactJson(bodyText);

    let aud =
      switch (TokenInfoParser.extractJsonString(compactBodyText, "aud")) {
        case (?value) { value };
        case null { return AuthHelpers.invalidToken("claim aud ausente") };
      };

    if (aud != expectedAudience) {
      return AuthHelpers.invalidToken("aud invalido para este cliente OAuth");
    };

    let issuer =
      switch (TokenInfoParser.extractJsonString(compactBodyText, "iss")) {
        case (?value) { value };
        case null { return AuthHelpers.invalidToken("claim iss ausente") };
      };

    if (not AuthHelpers.isGoogleIssuer(issuer)) {
      return AuthHelpers.invalidToken("issuer no reconocido");
    };

    let exp =
      switch (TokenInfoParser.extractJsonNat(compactBodyText, "exp")) {
        case (?value) { value };
        case null { return AuthHelpers.invalidToken("claim exp invalido") };
      };

    if (exp <= nowSec) {
      return AuthHelpers.invalidToken("token expirado");
    };

    let email =
      switch (TokenInfoParser.extractJsonString(compactBodyText, "email")) {
        case (?value) { value };
        case null { return AuthHelpers.invalidToken("claim email ausente") };
      };

    let emailVerified =
      switch (TokenInfoParser.extractJsonBool(compactBodyText, "email_verified")) {
        case (?value) { value };
        case null { false };
      };

    if (not emailVerified) {
      return AuthHelpers.invalidToken("email no verificado por Google");
    };

    if (not Validation.isUocInstitutionalEmail(email)) {
      return AuthHelpers.invalidToken("dominio no permitido: solo @uoc.edu");
    };

    {
      isValid = true;
      email = ?email;
      // El voterId se asigna en la capa actor con registro estable de pseudonimos.
      voterId = null;
      reason = "ok";
    };
  };
};
