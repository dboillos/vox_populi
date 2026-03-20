import Char "mo:base/Char";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import Text "mo:base/Text";

// Modulo utilitario para parseo tolerante de respuestas tokeninfo.
//
// Diseno:
// - No intenta implementar un parser JSON completo.
// - Se centra en extraer claims concretos de payloads pequenos y previsibles.
module {
  // API CONTRACT: compactJson
  // Objetivo:
  // - Eliminar espacios, tabs y saltos de linea para facilitar busquedas por texto.
  // Parametros:
  // - jsonText: texto JSON de entrada.
  // Resultado:
  // - JSON compacto sin whitespace estructural comun.
  public func compactJson(jsonText : Text) : Text {
    var compact = "";
    for (char in jsonText.chars()) {
      if (char != ' ' and char != '\n' and char != '\r' and char != '\t') {
        compact #= Char.toText(char);
      };
    };
    compact;
  };

  // API CONTRACT: extractJsonString
  // Parametros:
  // - jsonText: JSON (normalmente ya compactado).
  // - key: clave del claim string.
  // Resultado:
  // - `?Text` con el valor si existe en formato string, o `null` si no.
  public func extractJsonString(jsonText : Text, key : Text) : ?Text {
    let marker = "\"" # key # "\":\"";
    let splitByKey = Iter.toArray(Text.split(jsonText, #text marker));
    if (splitByKey.size() >= 2) {
      let tail = splitByKey[1];
      let splitByQuote = Iter.toArray(Text.split(tail, #text "\""));
      if (splitByQuote.size() >= 1) {
        return ?splitByQuote[0];
      };
    };

    null;
  };

  // API CONTRACT: extractJsonBool
  // Parametros:
  // - jsonText: JSON (normalmente ya compactado).
  // - key: clave del claim booleano.
  // Resultado:
  // - `?Bool` para valores true/false (booleano o string), o `null` si no hay match.
  public func extractJsonBool(jsonText : Text, key : Text) : ?Bool {
    let trueMarker = "\"" # key # "\":true";
    let falseMarker = "\"" # key # "\":false";
    let quotedTrueMarker = "\"" # key # "\":\"true\"";
    let quotedFalseMarker = "\"" # key # "\":\"false\"";

    if (Iter.toArray(Text.split(jsonText, #text trueMarker)).size() >= 2) {
      return ?true;
    };
    if (Iter.toArray(Text.split(jsonText, #text quotedTrueMarker)).size() >= 2) {
      return ?true;
    };
    if (Iter.toArray(Text.split(jsonText, #text falseMarker)).size() >= 2) {
      return ?false;
    };
    if (Iter.toArray(Text.split(jsonText, #text quotedFalseMarker)).size() >= 2) {
      return ?false;
    };

    null;
  };

  // API CONTRACT: extractJsonNat
  // Parametros:
  // - jsonText: JSON (normalmente ya compactado).
  // - key: clave del claim numerico.
  // Resultado:
  // - `?Nat` si encuentra un natural valido (como string o como numero), o `null`.
  public func extractJsonNat(jsonText : Text, key : Text) : ?Nat {
    switch (extractJsonString(jsonText, key)) {
      case (?value) {
        switch (Nat.fromText(value)) {
          case (?natValue) { return ?natValue };
          case null {};
        };
      };
      case null {};
    };

    let marker = "\"" # key # "\":";
    let splitByKey = Iter.toArray(Text.split(jsonText, #text marker));
    if (splitByKey.size() < 2) {
      return null;
    };

    let tail = splitByKey[1];
    var digits = "";
    for (char in tail.chars()) {
      if (char >= '0' and char <= '9') {
        digits #= Char.toText(char);
      } else {
        if (Text.size(digits) > 0) {
          switch (Nat.fromText(digits)) {
            case (?natValue) { return ?natValue };
            case null { return null };
          };
        };
      };
    };

    if (Text.size(digits) == 0) {
      return null;
    };

    Nat.fromText(digits);
  };
};
