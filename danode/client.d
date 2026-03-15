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
          if (driver.isAlive()) driver.closeConnection();   // Close connection
          request.clearUploadFiles();                       // Clean uploaded files
          response.kill();                                  // kill any running CGI process
        }
        while (running) {
          if (driver.receive(driver.socket) > 0) {     // We've received new data
            if (!driver.hasHeader()) {
              if (driver.inbuffer.data.length > MAX_HEADER_SIZE) {  // Check if we exceed the max header size
                log(Level.Verbose, "CLIENT", "header too large from %s:%s", ip, port);
                driver.setHeaderTooLarge(response); stop(); continue;
              }
            } else {
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
            log(Level.Trace, "completed: index=%d length=%d", response.index, response.length);
            request.clearUploadFiles();                     // Clean uploaded files
            request.destroy();                              // Clear the request structure
            driver.inbuffer.destroy();                      // Clear the input buffer
            driver.requests++;
            if(!response.keepalive) stop();                 // No keep alive, then stop this client
            response.destroy();                             // Clear the response structure
          }
          if (lastmodified >= maxtime) { // Client are not allowed to be silent for more than maxtime
            log(Level.Trace, "timeout: index=%d length=%d completed=%s", response.index, response.length, response.completed);
            log(Level.Trace, "inactivity: %s > %s", lastmodified, maxtime);
            driver.setTimedOut(response);
            this.log(request, response);
            stop(); continue;
          }
          log(Level.Trace, "Connection %s:%s (%s msecs) %s", ip, port, starttime, to!string(driver.inbuffer.data));
          Thread.sleep(dur!"msecs"(2));
        }
      } catch(Exception e) { log(Level.Verbose, "Unknown Client Exception: %s", e); stop();
      } catch(Error e) { log(Level.Verbose, "Unknown Client Error: %s", e); stop(); }

      log(Level.Verbose, "Connection %s:%s (%s) closed. %d requests %s (%s msecs)", ip, port, (driver.isSecure() ? "SSL" : "HTTP"), 
                                                                                    driver.requests, driver.senddata, starttime);
      driver.destroy();
    }

    // Is the client still running, if the socket was gone it's not otherwise check the terminated flag
    final @property bool running() const {
      if (driver.socket is null) return(false);
      return(!atomicLoad(terminated) && driver.socket.isAlive());
    }

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
  tag(Level.Always, format("%d", rs.statuscode), "%s %s:%s %s%s %s %s", htmltime(), cl.ip, cl.port, rq.shorthost, uri.replace("%", "%%"), Msecs(rq.starttime), bytes);
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

  router.runRequest("GET /test.pdf HTTP/1.1\nHost: localhost\nRange: bytes=0-65535\n\n");
  router.runRequest("GET /test.pdf HTTP/1.1\nHost: localhost\nRange: bytes=32517-\n\n");

  router.runRequest("GET /dmd.d HTTP/1.1\nHost: localhost\n\n");
  router.runRequest("GET /dmd.d HTTP/1.1\nHost: localhost\r\n\r\n");
  router.runRequest("GET /dmd.d HTTP/1.1\nHost: www.localhost\n\n");
  router.runRequest("GET /dmd.d HTTP/1.1\nHost: www.localhost\r\n\r\n");
  router.runRequest("GET /dmd.d HTTP/1.1\nHost: notfound\n\n");
  router.runRequest("GET /dmd.d HTTP/1.1\nHost: notfound\r\n\r\n");

  router.runRequest("GET /dmd.d\nHost: localhost\n\n");
  router.runRequest("GET /dmd.d\nHost: notfound\n\n");

  router.runRequest("GET\nHost: localhost\n\n");
  router.runRequest("GET\nHost: notfound\n\n");

  router.runRequest("GET /php.php HTTP/1.1\nHost: localhost\n\n");
  router.runRequest("GET /php.php HTTP/1.1\nHost: localhost\r\n\r\n");

  router.runRequest("GET /php-cgi.fphp HTTP/1.1\nHost: localhost\n\n");
  router.runRequest("GET /php-cgi.fphp HTTP/1.1\nHost: localhost\r\n\r\n");

  router.runRequest("GET /phpinfo.fphp HTTP/1.1\nHost: localhost\n\n");
  router.runRequest("GET /phpinfo.fphp HTTP/1.1\nHost: localhost\r\n\r\n");

  router.runRequest("GET /dmd.d HTTP/1.2\nHost: localhost\n\n");
  router.runRequest("GET /keepalive.d HTTP/1.1\nHost: localhost\nConnection: keep-alive\n\n");

  // Test all available RequestMethods, and an invalid one
  router.runRequest("GET /dmd.d HTTP/1.1\nHost: localhost\n\n");
  router.runRequest("HEAD /dmd.d HTTP/1.1\nHost: localhost\n\n");
  router.runRequest("POST /dmd.d HTTP/1.1\nHost: localhost\n\n");
  router.runRequest("PUT /dmd.d HTTP/1.1\nHost: localhost\n\n");
  router.runRequest("DELETE /dmd.d HTTP/1.1\nHost: localhost\n\n");
  router.runRequest("CONNECT /dmd.d HTTP/1.1\nHost: localhost\n\n");
  router.runRequest("OPTIONS * HTTP/1.1\n\n");
  router.runRequest("TRACE /dmd.d HTTP/1.1\nHost: localhost\n\n");
  router.runRequest("NO /dmd.d HTTP/1.1\nHost: localhost\n\n");
}

