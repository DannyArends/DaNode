module danode.client;

import danode.imports;
import danode.router : Router, runRequest;
import danode.statuscode : StatusCode;
import danode.interfaces : DriverInterface, ClientInterface, StringDriver;
import danode.response : Response, setTimedOut;
import danode.request : Request;
import danode.payload : Message;
import danode.log : custom, info, trace, warning, NOTSET, NORMAL;

immutable size_t MAX_REQUEST_SIZE = 1024 * 1024 * 100; // 100MB upload limit

class Client : Thread, ClientInterface {
  private:
    Router              router;              /// Router class from server
    DriverInterface     driver;              /// Driver
    long                maxtime;             /// Maximum quiet time before we cut the connection
    shared bool         terminated;          /// Is the client / connection terminated

  public:
    this(Router router, DriverInterface driver, long maxtime = 5000) {
      custom(3, "CLIENT", "client constructor");
      this.router = router;
      this.driver = driver;
      this.maxtime = maxtime;
      super(&run); // initialize the thread
    }

   final void run() {
      trace("new connection established %s:%d", ip(), port() );
      try {
        if (driver.openConnection() == false) { warning("new connection aborted: unable to open connection"); stop(); }
        Request request;
        Response response;
        scope (exit) {
          if (driver.isAlive()) driver.closeConnection();   // Close connection
          request.clearUploadFiles();                       // Clean uploaded files
          response.kill();                                  // kill any running CGI process
        }
        while (running) {
          if (driver.receive(driver.socket) > 0) {     // We've received new data
            if (driver.inbuffer.data.length > MAX_REQUEST_SIZE) {
              custom(2, "CLIENT", "request too large from %s:%s", ip, port);
              driver.setTimedOut(response);
              stop(); continue;
            }
            if (!response.ready) {                            // If we're not ready to respond yet
              // Parse the data and try to create a response (Could fail multiple times)
              router.route(driver, request, response, maxtime);
            }
          }
          if (response.ready && !response.completed) {      // We know what to respond, but haven't send all of it yet
            //custom(1, "CLIENT", "sending: index=%d length=%d isRange=%s", response.index, response.length, response.isRange);
            driver.send(response, driver.socket, 65536);           // Send the response, hit multiple times, send what you can and return
          }
          if (response.ready && response.completed) {       // We've completed the request, response cycle
            //custom(1, "CLIENT", "completed: index=%d length=%d", response.index, response.length);
            router.logRequest(this, request, response);     // Log the response to the request
            request.clearUploadFiles();                     // Clean uploaded files
            request.destroy();                              // Clear the request structure
            driver.inbuffer.destroy();                      // Clear the input buffer
            driver.requests++;
            if(!response.keepalive) stop();                 // No keep alive, then stop this client
            response.destroy();                             // Clear the response structure
          }
          if (lastmodified >= maxtime) { // Client are not allowed to be silent for more than maxtime
            //custom(1, "CLIENT", "timeout: index=%d length=%d completed=%s", response.index, response.length, response.completed);
            custom(2, "CLIENT", "inactivity: %s > %s", lastmodified, maxtime);
            if (!response.ready && request !is Request.init) { // We have an unhandled request
              driver.setTimedOut(response);
              router.logRequest(this, request, response);     // Log the response to the request
            }
            stop(); continue;
          }
          custom(3, "CLIENT", "connection %s:%s (%s msecs) %s", ip, port, starttime, to!string(driver.inbuffer.data));
          Thread.sleep(dur!"msecs"(2));
        }
      } catch(Exception e) { 
        warning("Unknown Client Exception: %s", e);
        stop();
      } catch(Error e) {
        warning("Unknown Client Error: %s", e);
        stop();
      }
      custom(1, "CLIENT", "connection %s:%s (%s) closed after %d requests %s (%s msecs)", ip, port, (driver.isSecure() ? "SSL" : "HTTP"), 
                                                                                          driver.requests, driver.senddata, starttime);
      driver.destroy();                                               // Clear the response structure
    }

    // Is the client still running, if the socket was gone it's not otherwise check the terminated flag
    final @property bool running() const {
      if (driver.socket is null) return(false);
      return(!atomicLoad(terminated) && driver.socket.isAlive());
    }

    // Stop the client by setting the terminated flag
    final @property void stop() {
      trace("connection %s:%s stop called", ip, port);
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

unittest {
  custom(0, "FILE", "%s", __FILE__);
  auto router = new Router("./www/", Address.init, NORMAL);

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

