import Blob "mo:base/Blob";
import HashMap "mo:base/HashMap";
import Int "mo:base/Int";
import List "mo:base/List";
import Nat "mo:base/Nat";
import Nat32 "mo:base/Nat32";
import Text "mo:base/Text";
import Prim "mo:prim";

import AuditHelpers "../audit/audit_helpers";
import Types "../shared/types";

// Servicio de registro de identidad pseudonima estable.
//
// Diseno:
// - Separa del actor la logica de normalizacion, lookup y provision de `voterId`.
// - Usa random del IC cuando esta disponible para evitar identificadores deterministas.
module {
  // API CONTRACT: IdentityRegistry
  // - Mapa transient identityKey -> voterId opaco.
  public type IdentityRegistry = HashMap.HashMap<Text, Text>;

  // API CONTRACT: RandomSource
  // - Subconjunto necesario para obtener aleatoriedad del Management Canister.
  public type RandomSource = actor {
    raw_rand : shared () -> async Blob;
  };

  // API CONTRACT: AttachIdentityResult
  // Resultado compuesto para actualizar espejo estable y devolver validacion final.
  public type AttachIdentityResult = {
    validation : Types.GoogleTokenValidation;
    identityRegistryEntries : List.List<(Text, Text)>;
  };

  func normalizeIdentityKey(email : Text) : Text {
    Text.map(email, Prim.charToLower);
  };

  func buildRandomPseudonymousId(nowNs : Int, randomBlob : ?Blob, fallbackSeed : Text) : Text {
    switch (randomBlob) {
      case (?blob) {
        "pid-" # AuditHelpers.blobToHex(blob);
      };
      case null {
        // Fallback solo si raw_rand falla: evita bloquear login en entornos restringidos.
        "pid-fallback-" # Nat32.toText(Text.hash(fallbackSeed # ":" # Nat.toText(Int.abs(nowNs))));
      };
    };
  };

  // API CONTRACT: buildIdentityMap
  // Parametros:
  // - entries: espejo estable (identityKey, voterId).
  // Resultado:
  // - hashmap transient para busquedas O(1) promedio.
  public func buildIdentityMap(entries : List.List<(Text, Text)>) : IdentityRegistry {
    let identity = HashMap.HashMap<Text, Text>(64, Text.equal, Text.hash);
    for ((identityKey, voterId) in List.toIter(entries)) {
      identity.put(identityKey, voterId);
    };
    identity;
  };

  // API CONTRACT: attachPseudonymousIdentity
  // Parametros:
  // - randomSource: origen de aleatoriedad para nuevos identificadores.
  // - backendEmailSalt: salt estable del backend usado en semilla fallback.
  // - nowNs: timestamp de red en nanosegundos.
  // - validation: resultado de tokeninfo (email validado o motivo de error).
  // - identityRegistry: indice transient identityKey -> voterId.
  // - identityRegistryEntries: espejo estable del registro.
  // Resultado:
  // - validacion final con voterId opaco y espejo estable actualizado.
  public func attachPseudonymousIdentity(
    randomSource : RandomSource,
    backendEmailSalt : Text,
    nowNs : Int,
    validation : Types.GoogleTokenValidation,
    identityRegistry : IdentityRegistry,
    identityRegistryEntries : List.List<(Text, Text)>,
  ) : async AttachIdentityResult {
    if (not validation.isValid) {
      return {
        validation = validation;
        identityRegistryEntries = identityRegistryEntries;
      };
    };

    let normalizedIdentityKey =
      switch (validation.email) {
        case (?email) { normalizeIdentityKey(email) };
        case null {
          return {
            validation = {
              isValid = false;
              email = null;
              voterId = null;
              reason = "token validado sin email utilizable";
            };
            identityRegistryEntries = identityRegistryEntries;
          };
        };
      };

    switch (identityRegistry.get(normalizedIdentityKey)) {
      case (?existingVoterId) {
        return {
          validation = {
            isValid = true;
            email = validation.email;
            voterId = ?existingVoterId;
            reason = validation.reason;
          };
          identityRegistryEntries = identityRegistryEntries;
        };
      };
      case null {};
    };

    let maybeRandomBlob =
      try {
        ?(await randomSource.raw_rand());
      } catch (_) {
        null;
      };

    let generatedVoterId = buildRandomPseudonymousId(
      nowNs,
      maybeRandomBlob,
      normalizedIdentityKey # ":" # backendEmailSalt,
    );

    identityRegistry.put(normalizedIdentityKey, generatedVoterId);
    let updatedIdentityRegistryEntries = List.push((normalizedIdentityKey, generatedVoterId), identityRegistryEntries);

    {
      validation = {
        isValid = true;
        email = validation.email;
        voterId = ?generatedVoterId;
        reason = validation.reason;
      };
      identityRegistryEntries = updatedIdentityRegistryEntries;
    };
  };
};