import Blob "mo:base/Blob";
import Nat8 "mo:base/Nat8";
import Text "mo:base/Text";

// Utilidades de auditoria y formato tecnico.
module {
  // API CONTRACT: blobToHex
  // Parametros:
  // - b: blob de bytes binarios.
  // Resultado:
  // - representacion hexadecimal en minusculas.
  // Uso:
  // - Formatear `module_hash` para comparacion/auditoria humana.
  public func blobToHex(b : Blob) : Text {
    let bytes = Blob.toArray(b);
    let chars = ["0","1","2","3","4","5","6","7","8","9","a","b","c","d","e","f"];
    var hex = "";
    for (byte in bytes.vals()) {
      let n = Nat8.toNat(byte);
      hex #= chars[n / 16] # chars[n % 16];
    };
    hex;
  };
};
