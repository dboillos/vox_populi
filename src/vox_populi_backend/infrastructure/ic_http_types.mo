import Blob "mo:base/Blob";
import Nat64 "mo:base/Nat64";
import Nat8 "mo:base/Nat8";
import Text "mo:base/Text";

// Tipos de integracion HTTP con Management Canister.
//
// Objetivo:
// - Sacar del actor principal los tipos de infraestructura para reducir ruido.
module {
  // API CONTRACT: HttpHeader
  // - Cabecera HTTP simple (nombre/valor).
  public type HttpHeader = {
    name : Text;
    value : Text;
  };

  // API CONTRACT: HttpMethod
  // - Metodos HTTP soportados por este backend.
  public type HttpMethod = {
    #get;
    #head;
    #post;
  };

  // API CONTRACT: HttpResponsePayload
  // - Respuesta raw devuelta por `http_request` del Management Canister.
  public type HttpResponsePayload = {
    status : Nat;
    headers : [HttpHeader];
    body : [Nat8];
  };

  // API CONTRACT: TransformArgs
  // - Entrada de funciones transform de HTTP outcalls.
  public type TransformArgs = {
    response : HttpResponsePayload;
    context : Blob;
  };

  // API CONTRACT: TransformContext
  // - Contexto de transformacion opcional para outcalls HTTP.
  public type TransformContext = {
    function : shared query (TransformArgs) -> async HttpResponsePayload;
    context : Blob;
  };

  // API CONTRACT: HttpRequestArgs
  // - Parametros de peticion para `http_request`.
  public type HttpRequestArgs = {
    url : Text;
    max_response_bytes : ?Nat64;
    headers : [HttpHeader];
    body : [Nat8];
    method : HttpMethod;
    transform : ?TransformContext;
  };

  // API CONTRACT: buildGoogleTokenInfoRequest
  // Parametros:
  // - idToken: JWT emitido por Google Identity Services.
  // - transformFn: funcion query del canister para normalizar respuesta y
  //   reducir no determinismo entre replicas.
  // Resultado:
  // - request HTTP GET lista para consultar `tokeninfo`.
  public func buildGoogleTokenInfoRequest(
    idToken : Text,
    transformFn : shared query (TransformArgs) -> async HttpResponsePayload,
  ) : HttpRequestArgs {
    {
      url = "https://oauth2.googleapis.com/tokeninfo?id_token=" # idToken;
      max_response_bytes = ?4_096;
      method = #get;
      headers = [
        {
          name = "User-Agent";
          value = "vox-populi-backend";
        },
      ];
      body = [];
      transform = ?{
        function = transformFn;
        context = Blob.fromArray([]);
      };
    };
  };
};
