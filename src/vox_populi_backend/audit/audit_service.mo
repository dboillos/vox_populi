import Blob "mo:base/Blob";
import Principal "mo:base/Principal";
import Nat "mo:base/Nat";
import Text "mo:base/Text";

import AuditHelpers "./audit_helpers";
import Types "../shared/types";

// Servicio de auditoria y metadatos de despliegue.
module {
  // API CONTRACT: ICManagement
  // - Subconjunto de operaciones del Management Canister usadas para auditoria.
  public type ICManagement = actor {
    canister_status : shared ({ canister_id : Principal }) -> async {
      module_hash : ?Blob;
      cycles : Nat;
      memory_size : Nat;
    };
  };

  // API CONTRACT: getAuditData
  // Parametros:
  // - ic: interfaz al Management Canister.
  // - selfId: principal del backend.
  // - surveyCodeVersion: version logica declarada por backend.
  // Resultado:
  // - metadatos de auditoria para UI/TFM.
  public func getAuditData(
    ic : ICManagement,
    selfId : Principal,
    surveyCodeVersion : Text,
  ) : async Types.AuditData {
    var moduleHashText = "Error: canister no es su propio controlador";
    var cyclesText = "No disponible";
    try {
      let status = await ic.canister_status({ canister_id = selfId });
      moduleHashText := switch (status.module_hash) {
        case (?hash) { AuditHelpers.blobToHex(hash) };
        case null { "No desplegado" };
      };
      cyclesText := Nat.toText(status.cycles);
    } catch (_) {
      moduleHashText := "Error: configure el canister como su propio controlador";
    };

    {
      canisterId = Principal.toText(selfId);
      wasmModuleHash = moduleHashText;
      cyclesBalance = cyclesText;
      codeVersion = surveyCodeVersion;
    };
  };

  // API CONTRACT: getModuleHash
  // Parametros:
  // - ic: interfaz al Management Canister.
  // - canisterId: principal a consultar.
  // Resultado:
  // - hash hexadecimal del modulo o mensaje de error.
  public func getModuleHash(ic : ICManagement, canisterId : Principal) : async Text {
    try {
      let status = await ic.canister_status({ canister_id = canisterId });
      switch (status.module_hash) {
        case (?hash) { AuditHelpers.blobToHex(hash) };
        case null { "No desplegado" };
      };
    } catch (_) {
      "Error: el backend no es controlador de ese canister";
    };
  };
};
