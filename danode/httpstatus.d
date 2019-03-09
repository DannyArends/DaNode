module danode.httpstatus;

import danode.log : custom;

struct StatusCodeT {
  size_t code;
  string reason;
  alias code this;
}

enum StatusCode : StatusCodeT {
  Continue = StatusCodeT(100, "Continue"),
  SwitchingProtocols = StatusCodeT(101, "Switching Protocols"),

  Ok = StatusCodeT(200, "Ok"),
  Saved = StatusCodeT(201, "Saved"),
  Accepted = StatusCodeT(202, "Accepted"),
  NoContent = StatusCodeT(204, "No Content"),
  ResetContent = StatusCodeT(205,"Reset Content"),
  PartialContent = StatusCodeT(206,"Partial Content"),

  MultipleChoices = StatusCodeT(300,"Multiple Choices"),
  MovedPermanently = StatusCodeT(301,"Moved Permanently"),
  MovedTemporarily = StatusCodeT(302,"Moved Temporarily"),
  SeeOther = StatusCodeT(303,"See Other"),
  NotModified = StatusCodeT(304,"Not Modified"),
  TemporaryRedirect = StatusCodeT(307,"Temporary Redirect"),
  EmptyResponse = StatusCodeT(324,"Empty Response"),

  BadRequest = StatusCodeT(400,"Bad Request"),
  Unauthorized = StatusCodeT(401,"Unauthorized"),
  Forbidden = StatusCodeT(403,"Forbidden"),
  NotFound = StatusCodeT(404,"Not Found"),
  MethodNotAllowed = StatusCodeT(405,"Method Not Allowed"),
  TimedOut = StatusCodeT(407,"Connection Timed Out"),
  UriTooLong = StatusCodeT(414,"Request-URI Too Long"),

  ISE = StatusCodeT(500,"Internal Server Error"),
  NotImplemented = StatusCodeT(501,"Not Implemented"),
  ServiceUnavailable = StatusCodeT(502,"Service Unavailable"),
  VersionUnsupported = StatusCodeT(505, "HTTP Version Not Supported")
};

@nogc pure string reason (const StatusCode statuscode) nothrow { return(statuscode.reason); }

unittest {
  custom(0, "FILE", "%s", __FILE__);
  with (StatusCode) {
    custom(0, "TEST", "%d: \"%s\"", Continue, reason(Continue));
    custom(0, "TEST", "%d: \"%s\"", Ok, reason(Ok));
    custom(0, "TEST", "%d: \"%s\"", MovedPermanently, reason(MovedPermanently));
    custom(0, "TEST", "%d: \"%s\"", NotModified, reason(NotModified));
    custom(0, "TEST", "%d: \"%s\"", BadRequest, reason(BadRequest));
    custom(0, "TEST", "%d: \"%s\"", Unauthorized, reason(Unauthorized));
    custom(0, "TEST", "%d: \"%s\"", TimedOut, reason(TimedOut));
    custom(0, "TEST", "%d: \"%s\"", ISE, reason(ISE));
    custom(0, "TEST", "%d: \"%s\"", NotImplemented, reason(NotImplemented));
  }
}

