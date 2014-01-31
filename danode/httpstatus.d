/**
 * | <a href="index.html">Home</a>             | <a href="server.html">Server</a>              |
 *   <a href="client.html">Client</a>          | <a href="router.html">Router</a>              |
 *   <a href="cgi.html">CGI</a>                | <a href="filebuffer.html">File Buffer</a>     |
 *   <a href="structs.html">Structures</a>     | <a href="helper.html">Helper functions</a>    |
 *
 * License: Use freely for any purpose
 */
module danode.httpstatus;

import danode.structs, danode.response;

enum Response
  STATUS_CONTINUE =               {100, "Continue"},
  STATUS_SWITCH_PROTOCOL =        {101, "Switching Protocols"},
  STATUS_OK =                     {200, "Ok"},                                /// OK, cool, cool cool cool
  STATUS_SAVED =                  {201, "Saved"},
  STATUS_ACCEPTED =               {202, "Accepted"},
  STATUS_NON_INFORMATION =        {203, "Non-Authoritative Information"},
  STATUS_NO_CONTENT =             {204, "No Content"},
  STATUS_RESET_CONTENT =          {205, "Reset Content"},
  STATUS_PARTIAL_CONTENT =        {206, "Partial Content"},
  STATUS_MULTIPLE_CHOICES =       {300, "Multiple Choices"},
  STATUS_MOVED_PERMANENTLY =      {301, "Moved Permanently"},                 /// Not even a goodbye
  STATUS_FOUND =                  {302, "Found"},
  STATUS_SEE_OTHER =              {303, "See Other"},
  STATUS_NOT_MODIFIED =           {304, "Not Modified"},
  STATUS_TEMP_REDIRECT =          {307, "Temporary Redirect"},
  STATUS_EMPTY_RESPONSE =         {324, "Empty Response"},
  STATUS_BAD_REQUEST =            {400, "Bad Request"},
  STATUS_TIMEOUT =                {400, "Time out"},                          /// Too slow
  STATUS_UNAUTHORIZED =           {401, "Unauthorized"},
  STATUS_PAYMENT_REQUIRED =       {402, "Payment Required"},                  /// All your $ are belong to us
  STATUS_FORBIDDEN =              {403, "Forbidden"},                         /// For your eyes only
  STATUS_PAGE_NOT_FOUND =         {404, "Not Found"},                         /// Awww
  STATUS_METHOD_NOT_ALLOWED =     {405, "Method Not Allowed"},
  STATUS_NOT_ACCEPTABLE =         {406, "Not Acceptable"},
  STATUS_URI_TOO_LONG =           {414, "Request-URI Too Long"},
  STATUS_INTERNAL_ERROR =         {500, "Internal Server Error"},             /// Why server, why ?
  STATUS_NOT_IMPLEMENTED =        {501, "Not Implemented"},
  STATUS_SERVICE_UNAVAILABLE =    {503, "Service Unavailable"},
  STATUS_VERSION_UNSUPPORTED =    {505, "HTTP Version Not Supported"};

