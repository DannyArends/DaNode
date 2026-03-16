module danode.client;

import danode.imports;
import danode.cgi : CGI;
import danode.router : Router, runRequest;
import danode.statuscode : StatusCode;
import danode.functions: htmltime, Msecs;
import danode.interfaces : DriverInterface, ClientInterface, StringDriver;
import danode.response : Response, setPayload;
import danode.request : Request;
import danode.payload : Message, PayloadType;
import danode.log : log, tag, error, Level;

immutable size_t MAX_HEADER_SIZE  = 1024 * 32;          //  32KB Header
immutable size_t MAX_REQUEST_SIZE = 1024 * 1024 * 2;    //   2MB Body
immutable size_t MAX_UPLOAD_SIZE  = 1024 * 1024 * 100;  // 100MB Multipart uploads

class Client : Thread, ClientInterface {
  private:
    Router              router;              /// Router class from server
    DriverInterface     driver;              /// Driver
    long                maxtime;             /// Maximum quiet time before we cut the connection
    shared bool         terminated;          /// Is the client / connection terminated

  public:
    this(Router router, DriverInterface driver, long maxtime = 5000) {
      log(Level.Trace, "client constructor");
      this.router = router;
      this.driver = driver;
      this.maxtime = maxtime;
      super(&run); // initialize the thread
    }

   final void run() {
      log(Level.Trace, "New connection established %s:%d", ip(), port() );
      try {
        if (driver.openConnection() == false) { log(Level.Verbose, "WARN: Unable to open connection"); stop(); }
        Request request;
        Response response;
        scope (exit) {
          if (driver.socketReady()) driver.closeConnection();   // Close connection
          request.clearUploadFiles();                           // Clean uploaded files
          response.kill();                                      // kill any running CGI process
        }
        while (running) {
          if (driver.receive(driver.socket) > 0) {     // We've received new data
            if (driver.inbuffer.data.length > MAX_HEADER_SIZE) {  // Check if we exceed the max header size
              log(Level.Verbose, "header too large from %s:%s", ip, port);
              driver.setHeaderTooLarge(response); stop(); continue;
            }
            if (driver.hasHeader()) {
              size_t limit  = (driver.header.indexOf("multipart/") >= 0) ? MAX_UPLOAD_SIZE : MAX_REQUEST_SIZE;
              if (driver.inbuffer.data.length > limit) {
                log(Level.Verbose, "request too large from %s:%s", ip, port);
                driver.setPayloadTooLarge(response); stop(); continue;
              }
            }
            // Parse the data and try to create a response (Could fail multiple times)
            if (!response.ready) { router.route(driver, request, response, maxtime); }
          }
          if (response.ready && !response.completed) {      // We know what to respond, but haven't send all of it yet
            log(Level.Trace, "sending: index=%d length=%d isRange=%s", response.index, response.length, response.isRange);
            driver.send(response, driver.socket);           // Send the response, hit multiple times, send what you can and return
          }
          if (response.ready && response.completed) {       // We've completed the request, response cycle
            this.log(request, response);
            request.clearUploadFiles();                     // Clean uploaded files
            driver.inbuffer.clear();                        // Clear the input buffer
            driver.requests++;
            if(!response.keepalive){ stop(); continue; }    // No keep alive, then stop this client
            request = Request.init;                         // Reset request for next request cycle
            response = Response.init;                       // Reset response for next request cycle
          }
          if (lastmodified >= maxtime) { // Client are not allowed to be silent for more than maxtime
            log(Level.Trace, "inactivity: %s > %s", lastmodified, maxtime);
            driver.setTimedOut(response);
            if (request.isValid) { this.log(request, response); }
            stop(); continue;
          }
          log(Level.Trace, "Connection %s:%s (%s msecs) %s", ip, port, starttime, to!string(driver.inbuffer.data));
          Thread.sleep(dur!"msecs"(2));
        }
      } catch(Exception e) { log(Level.Verbose, "Unknown Client Exception: %s", e); stop();
      } catch(Error e) { log(Level.Verbose, "Unknown Client Error: %s", e); stop(); }

      log(Level.Verbose, "Connection %s:%s (%s) closed. %d requests %s (%s msecs)", ip, port, (driver.isSecure() ? "SSL" : "HTTP"), 
                                                                                    driver.requests, driver.senddata, starttime);
    }

    // Is the client still running, if the socket was gone it's not otherwise check the terminated flag
    final @property bool running() const { return(!atomicLoad(terminated) && driver.socketReady()); }

    // Stop the client by setting the terminated flag
    final @property void stop() {
      log(Level.Trace, "connection %s:%s stop called", ip, port);
      atomicStore(terminated, true);
    }

    // Start time of the client in mseconds (stored in the connection driver)
    final @property long starttime() const { return(driver.starttime); }
    // When was the client last modified in mseconds (stored in the connection driver)
    final @property long lastmodified() const { return(driver.lastmodified); }
    // Port of the client
    final @property long port() const { return(driver.port()); } 
    // ip address of the client
    final @property string ip() const { return(driver.ip()); } 
}

void log(in ClientInterface cl, in Request rq, in Response rs) {
  string uri;
  try { uri = decodeComponent(rq.uri); } catch (Exception e) { uri = rq.uri; }
  long bytes = rs.isRange ? (rs.rangeEnd - rs.rangeStart + 1) : rs.payload.length;
  tag(Level.Always, format("%d", rs.statuscode), 
      "%s %s:%s %s%s %s %skb", htmltime(), cl.ip, cl.port, rq.shorthost, uri.replace("%", "%%"), Msecs(rq.starttime), bytes/1024);
}

// serve a 408 connection timed out page
void setTimedOut(ref DriverInterface driver, ref Response response) {
  if(response.payload && response.payload.type == PayloadType.Script){ to!CGI(response.payload).notifyovertime(); }
  response.setPayload(StatusCode.TimedOut, "408 - Connection Timed Out\n", "text/plain");
  driver.send(response, driver.socket);
}

// serve a 431 request header fields too large page
void setHeaderTooLarge(ref DriverInterface driver, ref Response response) {
  response.setPayload(StatusCode.HeaderFieldsTooLarge, "431 - Request Header Fields Too Large\n", "text/plain");
  driver.send(response, driver.socket);
}

// serve a 413 payload too large page
void setPayloadTooLarge(ref DriverInterface driver, ref Response response) {
  response.setPayload(StatusCode.PayloadTooLarge, "413 - Payload Too Large\n", "text/plain");
  driver.send(response, driver.socket);
}

unittest {
  tag(Level.Always, "FILE", "%s", __FILE__);
  auto router = new Router("./www/", Address.init);
  StringDriver res;

  // Range requests
  res = router.runRequest("GET /test.pdf HTTP/1.1\nHost: localhost\nRange: bytes=0-65535\n\n");
  assert(res.lastStatus == StatusCode.PartialContent, format("Range 0-65535 expected 206, got %d", res.lastStatus.code));
  assert(res.lastMime == "application/pdf", format("Range expected application/pdf, got %s", res.lastMime));

  res = router.runRequest("GET /test.pdf HTTP/1.1\nHost: localhost\nRange: bytes=65535-\n\n");
  assert(res.lastStatus == StatusCode.PartialContent, format("Range 32517- expected 206, got %d", res.lastStatus.code));
  assert(res.lastMime == "application/pdf", format("Range expected application/pdf, got %s", res.lastMime));

  // 416 - Range not satisfiable (beyond file size)
  res = router.runRequest("GET /test.pdf HTTP/1.1\nHost: localhost\nRange: bytes=999999999-\n\n");
  assert(res.lastStatus == StatusCode.RangeNotSatisfiable, format("Expected 416, got %d", res.lastStatus.code));

  // \r\n\r\n header terminator
  res = router.runRequest("GET /dmd.d HTTP/1.1\r\nHost: localhost\r\n\r\n");
  assert(res.lastStatus == StatusCode.Ok, format("CRLF expected 200, got %d", res.lastStatus.code));
  assert(res.lastMime == "text/html", format("dmd.d expected text/html, got %s", res.lastMime));

  // www. redirect
  res = router.runRequest("GET /dmd.d HTTP/1.1\nHost: www.localhost\n\n");
  assert(res.lastStatus == StatusCode.MovedPermanently, format("www. expected 301, got %d", res.lastStatus.code));

  // Unknown domain
  res = router.runRequest("GET /dmd.d HTTP/1.1\nHost: notfound\n\n");
  assert(res.lastStatus == StatusCode.NotFound, format("notfound domain expected 404, got %d", res.lastStatus.code));
  assert(res.lastMime == "text/plain", format("notfound expected text/plain, got %s", res.lastMime));

  // No HTTP version
  res = router.runRequest("GET /dmd.d\nHost: localhost\n\n");
  assert(res.lastStatus == StatusCode.BadRequest, format("No version expected 400, got %d", res.lastStatus.code));
  assert(res.lastMime == "text/plain", format("BadRequest expected text/plain, got %s", res.lastMime));

  // Malformed request
  res = router.runRequest("GET\nHost: localhost\n\n");
  assert(res.lastStatus == StatusCode.BadRequest, format("Malformed expected 400, got %d", res.lastStatus.code));
  assert(res.lastMime == "text/plain", format("BadRequest expected text/plain, got %s", res.lastMime));

  // Invalid HTTP version
  res = router.runRequest("GET /dmd.d HTTP/1.2\nHost: localhost\n\n");
  assert(res.lastStatus == StatusCode.Ok, format("HTTP/1.2 expected 200, got %d", res.lastStatus.code));

  // All HTTP methods
  foreach (method; ["GET", "HEAD", "POST", "PUT", "DELETE", "CONNECT", "TRACE"]) {
    res = router.runRequest(format("%s /dmd.d HTTP/1.1\nHost: localhost\n\n", method));
    assert(res.lastStatus == StatusCode.Ok, format("%s /dmd.d expected 200, got %d", method, res.lastStatus.code));
  }

  // Invalid method
  res = router.runRequest("NO /dmd.d HTTP/1.1\nHost: localhost\n\n");
  assert(res.lastStatus == StatusCode.BadRequest, format("Invalid method expected 400, got %d", res.lastStatus.code));

  // OPTIONS (no host required)
  res = router.runRequest("OPTIONS * HTTP/1.1\n\n");
  assert(res.lastStatus == StatusCode.NotFound, format("OPTIONS expected 404, got %d", res.lastStatus.code));

  // 431 - Header too large (>32KB header)
  res = router.runRequest("GET /dmd.d HTTP/1.1\nHost: localhost\n" ~ "X-Pad: " ~ "x".replicate(33000) ~ "\n\n");
  assert(res.lastStatus == StatusCode.HeaderFieldsTooLarge, format("Expected 431, got %d", res.lastStatus.code));

  // 413 - Payload too large (>2MB body)
  res = router.runRequest("POST /dmd.d HTTP/1.1\nHost: localhost\nContent-Length: 2097153\n\n" ~ "x".replicate(2097153));
  assert(res.lastStatus == StatusCode.PayloadTooLarge, format("Expected 413, got %d", res.lastStatus.code));

  // 304 - Not modified (future date)
  res = router.runRequest("GET /test.txt HTTP/1.1\nHost: localhost\nIf-Modified-Since: " ~ htmltime(Clock.currTime + 1.hours) ~ "\n\n");
  assert(res.lastStatus == StatusCode.NotModified, format("Expected 304, got %d", res.lastStatus.code));

}

