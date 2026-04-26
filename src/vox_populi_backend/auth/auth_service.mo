import Blob "mo:base/Blob";
import Int "mo:base/Int";
import Text "mo:base/Text";

import AuthFlow "./auth_flow";
import AuthHelpers "./auth_helpers";
import ICHttpTypes "../infrastructure/ic_http_types";
import SaltManager "./salt_manager";
import Types "../shared/types";

// Servicio de autenticacion OIDC.
//
// Objetivo:
// - Encapsular toda la logica de validacion de identidad fuera del actor.
// - Permitir que `main.mo` actue como capa de orquestacion.
module {
  // API CONTRACT: ICManagement
  // - Subconjunto de operaciones del Management Canister usadas en autenticacion.
  public type ICManagement = actor {
    http_request : shared ICHttpTypes.HttpRequestArgs -> async ICHttpTypes.HttpResponsePayload;
    raw_rand : shared () -> async Blob;
  };

  // API CONTRACT: ValidateGoogleIdTokenResult
  // Resultado compuesto para que el actor pueda persistir el salt actualizado.
  public type ValidateGoogleIdTokenResult = {
    validation : Types.GoogleTokenValidation;
    backendEmailSalt : Text;
  };

  // API CONTRACT: validateGoogleIdentity
  // Parametros:
  // - claims: claims minimos extraidos del id_token.
  // - expectedAudience: client_id OAuth esperado.
  // - nowSec: tiempo actual epoch en segundos.
  // Resultado:
  // - true cuando las claims son coherentes con login institucional UOC.
  public func validateGoogleIdentity(
    claims : Types.GoogleIdentityClaims,
    expectedAudience : Text,
    nowSec : Nat,
  ) : Bool {
    AuthFlow.validateGoogleIdentityClaims(claims, expectedAudience, nowSec);
  };

  // API CONTRACT: validateGoogleIdToken
  // Parametros:
  // - ic: interfaz de red al Management Canister.
  // - existingSalt: salt actual persistido (puede venir vacio).
  // - nowNs: tiempo actual en nanosegundos.
  // - idToken: JWT emitido por Google Identity Services.
  // - expectedAudience: client_id OAuth esperado.
  // Resultado:
  // - validacion OIDC + salt efectivo a persistir en estado estable.
  public func validateGoogleIdToken(
    ic : ICManagement,
    transformFn : shared query (ICHttpTypes.TransformArgs) -> async ICHttpTypes.HttpResponsePayload,
    existingSalt : Text,
    nowNs : Int,
    idToken : Text,
    expectedAudience : Text,
  ) : async ValidateGoogleIdTokenResult {
    if (Text.size(idToken) == 0) {
      return {
        validation = AuthHelpers.invalidToken("id_token vacio");
        backendEmailSalt = existingSalt;
      };
    };

    if (Text.size(expectedAudience) == 0) {
      return {
        validation = AuthHelpers.invalidToken("audiencia esperada vacia");
        backendEmailSalt = existingSalt;
      };
    };

    // Construye el HTTPS outcall hacia tokeninfo de Google.
    // El `transformFn` canoniza la respuesta para reducir no determinismo entre replicas.
    let request = ICHttpTypes.buildGoogleTokenInfoRequest(idToken, transformFn);

    let response =
      try {
        // `http_request` en el management canister requiere cycles adjuntos.
        // Si no hay saldo/coste suficiente o falla la red, esta llamada puede lanzar.
        // El valor se fija de forma conservadora para evitar rechazos por coste variable.
        await (with cycles = 70_000_000_000) ic.http_request(request);
      } catch (_) {
        // Error temporal de infraestructura (no invalida el token por si mismo).
        // Se traduce a respuesta funcional para no propagar traps al caller.
        return {
          validation = AuthHelpers.invalidToken("fallo al consultar tokeninfo de Google");
          backendEmailSalt = existingSalt;
        };
      };

    if (response.status != 200) {
      return {
        validation = AuthHelpers.invalidToken("Google tokeninfo rechazo el token");
        backendEmailSalt = existingSalt;
      };
    };

    let bodyText =
      switch (AuthFlow.decodeUtf8Body(response.body)) {
        case (?text) { text };
        case null {
          return {
            validation = AuthHelpers.invalidToken("respuesta tokeninfo no UTF-8");
            backendEmailSalt = existingSalt;
          };
        };
      };

    let maxRawRandAttempts : Nat = 3;

    func fetchRandomWithRetries(remainingAttempts : Nat) : async ?Blob {
      try {
        ?(await ic.raw_rand());
      } catch (_) {
        if (remainingAttempts <= 1) {
          null;
        } else {
          await fetchRandomWithRetries(remainingAttempts - 1);
        };
      };
    };

    let maybeRandomBlob =
      if (Text.size(existingSalt) > 0) {
        null;
      } else {
        await fetchRandomWithRetries(maxRawRandAttempts);
      };

    let maybeActiveSalt = SaltManager.ensureBackendEmailSalt(existingSalt, maybeRandomBlob);
    let activeSalt =
      switch (maybeActiveSalt) {
        case (?salt) { salt };
        case null {
          return {
            validation = AuthHelpers.invalidToken("servicio temporalmente no disponible: no se pudo inicializar salt seguro");
            backendEmailSalt = existingSalt;
          };
        };
      };
    let nowSec = Int.abs(nowNs / 1_000_000_000);

    {
      validation = AuthFlow.evaluateGoogleTokenInfo(bodyText, expectedAudience, nowSec);
      backendEmailSalt = activeSalt;
    };
  };
};
