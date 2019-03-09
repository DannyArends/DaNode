module danode.statuscode;

import danode.imports;

struct StatusCodeT {
  size_t code;
  string reason;
  alias code this;
}

enum StatusCode : StatusCodeT {
  Continue = StatusCodeT(100, "Continue"),
  SwitchingProtocols = StatusCodeT(101, "Switching Protocols"),

  Ok = StatusCodeT(200, "Ok"),
  Created = StatusCodeT(201, "Created"),
  Accepted = StatusCodeT(202, "Accepted"),
  NonAuthoritative = StatusCodeT(203, "Non-Authoritative Information"),
  NoContent = StatusCodeT(204, "No Content"),
  ResetContent = StatusCodeT(205, "Reset Content"),
  PartialContent = StatusCodeT(206, "Partial Content"),

  MultipleChoices = StatusCodeT(300, "Multiple Choices"),
  MovedPermanently = StatusCodeT(301, "Moved Permanently"),
  Found = StatusCodeT(302, "Found"),
  SeeOther = StatusCodeT(303, "See Other"),
  NotModified = StatusCodeT(304, "Not Modified"),
  TemporaryRedirect = StatusCodeT(307, "Temporary Redirect"),
  PermanentRedirect = StatusCodeT(308, "Permanent Redirect"),

  BadRequest = StatusCodeT(400, "Bad Request"),
  Unauthorized = StatusCodeT(401, "Unauthorized"),
  Forbidden = StatusCodeT(403, "Forbidden"),
  NotFound = StatusCodeT(404, "Not Found"),
  MethodNotAllowed = StatusCodeT(405, "Method Not Allowed"),
  NotAcceptable = StatusCodeT(406, "Not Acceptable"),
  ProxyAuthentication = StatusCodeT(407, "Proxy Authentication Required"),
  TimedOut = StatusCodeT(408, "Connection Timed Out"),
  Conflict = StatusCodeT(409, "Conflict"),
  Gone = StatusCodeT(410, "Gone"),
  LengthRequired = StatusCodeT(411, "Length Required"),
  PreconditionFailed = StatusCodeT(412, "Precondition Failed"),
  PayloadTooLarge = StatusCodeT(413, "Payload Too Large"),
  UriTooLong = StatusCodeT(414, "URI Too Long"),
  UnsupportedMediaType = StatusCodeT(415, "Unsupported Media Type"),
  RangeNotSatisfiable = StatusCodeT(416, "Range Not Satisfiable"),
  ExpectationFailed = StatusCodeT(417, "Expectation Failed"),
  Teapot = StatusCodeT(418, "I'm a teapot"),
  UnprocessableEntity = StatusCodeT(422, "Unprocessable Entity"),
  TooEarly = StatusCodeT(425, "Too Early"),
  UpgradeRequired = StatusCodeT(426, "Upgrade Required"),
  PreconditionRequired = StatusCodeT(428, "Precondition Required"),
  TooManyRequests = StatusCodeT(429, "Too Many Requests"),
  HeaderFieldsTooLarge = StatusCodeT(431, "Request Header Fields Too Large"),
  LegalReasons = StatusCodeT(451, "Unavailable For Legal Reasons"),

  ISE = StatusCodeT(500, "Internal Server Error"),
  NotImplemented = StatusCodeT(501, "Not Implemented"),
  BadGateway = StatusCodeT(502, "Bad Gateway"),
  ServiceUnavailable = StatusCodeT(503, "Service Unavailable"),
  GatewayTimeout = StatusCodeT(504, "Gateway Timeout"),
  VersionUnsupported = StatusCodeT(505, "HTTP Version Not Supported"),
  NetworkAuthenticationRequired = StatusCodeT(511, "Network Authentication Required")
};

unittest {
  import danode.log : custom;
  custom(0, "FILE", "%s", __FILE__);
  custom(0, "TEST", "statuscodes: %s", EnumMembers!StatusCode.length);
  foreach (immutable v; EnumMembers!StatusCode) {
    custom(2, "TEST", "[%s] %s: \"%s\"", v.code, v, v.reason);
  }
}

