module danode.client;

import danode.imports;
import danode.router : Router, runRequest;
import danode.httpstatus : StatusCode;
import danode.interfaces : DriverInterface, ClientInterface, StringDriver;
import danode.response : Response;
import danode.request : Request;
import danode.payload : Message;
import danode.log : custom, info, trace, warning, NOTSET, NORMAL;

class Client : Thread, ClientInterface {
  private:
    Router              router;              /// Router class from server
    DriverInterface     driver;              /// Driver
    long                maxtime;             /// Maximum quiet time before we cut the connection
  public:
    bool                terminated;          /// Is the client / connection terminated

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
        if (driver.openConnection() == false) {
          warning("new connection aborted: unable to open connection");
          stop();
        }
        scope (exit) {
          if (driver.isAlive()) driver.closeConnection();
        }
        Request request;
        Response response;
        while (running) {
          if (driver.receive(driver.socket) > 0) {     // We've received new data
            if (!response.ready) {                            // If we're not ready to respond yet
              // Parse the data and try to create a response (Could fail multiple times)
              router.route(driver, request, response);
            }
            if (response.ready && !response.completed) {      // We know what to respond, but haven't send all of it yet
              driver.send(response, driver.socket);           // Send the response, hit multiple times, send what you can and return
            }
            if (response.ready && response.completed) {       // We've completed the request, response cycle
              router.logRequest(this, request, response);     // Log the response to the request
              request.clearUploadFiles();                     // Remove any upload files left over
              request.destroy();                              // Clear the request structure
              driver.inbuffer.destroy();                      // Clear the input buffer
              driver.requests++;
              if(!response.keepalive) stop();                 // No keep alive, then stop this client
              response.destroy();                             // Clear the response structure
            }
          }
          if (lastmodified >= maxtime) { // Client are not allowed to be silent for more than maxtime
            warning("client stopped due to maxtime limit: %s > %s", lastmodified, maxtime);
            stop();
          }
          custom(3, "CLIENT", "connection %s:%s (%s msecs) %s", ip, port, starttime, to!string(driver.inbuffer.data));
          Thread.sleep(dur!"msecs"(2));
        }
      } catch(Exception e) { 
        warning("unknown client exception: %s", e.msg);
        stop();
      }
      custom(1, "CLIENT", "connection %s:%s (%s) closed after %d requests %s (%s msecs)", ip, port, (driver.isSecure() ? "⚐" : "⚑"), 
                                                                                          driver.requests, driver.senddata, starttime);
      driver.destroy();                                               // Clear the response structure
    }

    final @property bool running() const {
      if (driver.socket is null) return(false);
      return(!terminated && driver.socket.isAlive());
    }

    final @property void stop() {
      trace("connection %s:%s stop called", ip, port);
      terminated = true; 
    }

    final @property long starttime() const { return(driver.starttime); }
    final @property long lastmodified() const { return(driver.lastmodified); }
    final @property long port() const { return(driver.port()); } 
    final @property string ip() const { return(driver.ip()); } 
}

unittest {
  custom(0, "FILE", "%s", __FILE__);
  auto router = new Router("./www/", NORMAL);
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

  router.runRequest("GET /php-cgi.fphp HTTP/1.1\nHost: localhost\n\n");
  router.runRequest("GET /php-cgi.fphp HTTP/1.1\nHost: localhost\r\n\r\n");

  router.runRequest("GET /phpinfo.fphp HTTP/1.1\nHost: localhost\n\n");
  router.runRequest("GET /phpinfo.fphp HTTP/1.1\nHost: localhost\r\n\r\n");
}

