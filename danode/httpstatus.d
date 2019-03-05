module danode.httpstatus;

import danode.log : custom;

enum StatusCode {
  Continue = 100, SwitchingProtocols = 101,
  Ok = 200, Saved = 201, Accepted = 202, NoContent = 204, ResetContent = 205, PartialContent = 206,
  MultipleChoices = 300, MovedPermanently = 301, MovedTemporarily = 302, SeeOther = 303, NotModified = 304, TemporaryRedirect = 307, EmptyResponse = 324,
  BadRequest = 400, Unauthorized = 401, Forbidden = 403, NotFound = 404, MethodNotAllowed = 405, TimedOut = 407, UriTooLong = 414,
  ISE = 500, NotImplemented = 501, ServiceUnavailable = 502, VersionUnsupported = 505
};

@nogc pure string reason (StatusCode statuscode) nothrow { with(StatusCode) {
  final switch(statuscode){
    case Continue                 : return("Continue");
    case SwitchingProtocols       : return("Switching Protocols");

    case Ok                       : return("Ok");
    case Saved                    : return("Saved");
    case Accepted                 : return("Accepted");
    case NoContent                : return("No Content");
    case ResetContent             : return("Reset Content");
    case PartialContent           : return("Partial Content");

    case MultipleChoices          : return("Multiple Choices");
    case MovedPermanently         : return("Moved Permanently");
    case MovedTemporarily         : return("Moved Temporarily");
    case SeeOther                 : return("See Other");
    case NotModified              : return("Not Modified");
    case TemporaryRedirect        : return("Temporary Redirect");
    case EmptyResponse            : return("Empty Response");

    case BadRequest               : return("Bad Request");
    case Unauthorized             : return("Unauthorized");
    case Forbidden                : return("Forbidden");
    case NotFound                 : return("Not Found");
    case MethodNotAllowed         : return("Method Not Allowed");
    case TimedOut                 : return("Connection Timed Out");
    case UriTooLong               : return("Request-URI Too Long");

    case ISE                      : return("Internal Server Error");
    case NotImplemented           : return("Not Implemented");
    case ServiceUnavailable       : return("Service Unavailable");
    case VersionUnsupported       : return("HTTP Version Not Supported");
  }
} }

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
