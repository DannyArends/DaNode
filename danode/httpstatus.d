module danode.httpstatus;

enum StatusCode {
  Continue = 100, SwitchingProtocols = 101,
  Ok = 200, Saved = 201, Accepted = 202, NoContent = 204, ResetContent = 205, PartialContent = 206,
  MultipleChoices = 300, MovedPermanently = 301, MovedTemporarily = 302, SeeOther = 303, NotModified = 304, TemporaryRedirect = 307, EmptyResponse = 324,
  BadRequest = 400, Unauthorized = 401, Forbidden = 403, NotFound = 404, MethodNotAllowed = 405, TimedOut = 407, UriTooLong = 414,
  ISE = 500, NotImplemented = 501, ServiceUnavailable = 502, VersionUnsupported = 505
};

pure string reason(StatusCode statuscode){ with(StatusCode){
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
  import std.stdio : writefln;
  writefln("[FILE]   %s", __FILE__);
  with(StatusCode){
    writefln("[TEST]   %d: \"%s\"", Continue, reason(Continue));
    writefln("[TEST]   %d: \"%s\"", Ok, reason(Ok));
    writefln("[TEST]   %d: \"%s\"", MovedPermanently, reason(MovedPermanently));
    writefln("[TEST]   %d: \"%s\"", NotModified, reason(NotModified));
    writefln("[TEST]   %d: \"%s\"", Unauthorized, reason(Unauthorized));
    writefln("[TEST]   %d: \"%s\"", ISE, reason(ISE));
  }
}

