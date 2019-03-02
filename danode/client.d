module danode.client;

import danode.imports;
import danode.functions : Msecs;
import danode.router : Router;
import danode.httpstatus : StatusCode;
import danode.interfaces : DriverInterface, ClientInterface;
import danode.response : Response;
import danode.request : Request;
import danode.payload : Message;
import danode.log : custom, info, trace, warning;

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
          terminated = true;
        }
        scope (exit) {
          if (driver.isAlive()) driver.closeConnection();
        }
        Request request;
        Response response;
        while (running) {
          if (driver.receive(driver.socket) > 0) {                      // We've received new data
            if (!response.ready) {                                      // If we're not ready to respond yet
              // Parse the data and try to create a response (Could fail multiple times)
              router.route(ip(), port(), request, response, to!string(driver.inbuffer.data), driver.isSecure());
            }
            if (response.ready && !response.completed) {                        // We know what to respond, but haven't send all of it yet
              driver.send(response, driver.socket);                             // Send the response, hit multiple times, send what you can and return
            }
            if (response.ready && response.completed) {                         // We've completed the request, response cycle
              router.logrequest(this, request, response);                       // Log the response to the request
              request.clearUploadFiles();                                       // Remove any upload files left over
              request.destroy();                                                // Clear the request structure
              driver.inbuffer.destroy();                                        // Clear the input buffer
              driver.requests++;
              if(!response.keepalive) stop();                                   // No keep alive, then stop this client
              response.destroy();                                               // Clear the response structure
            }
          } else {
            Thread.sleep(dur!"msecs"(1));
          }
          if(lastmodified >= maxtime) terminated = true;
          custom(3, "CLIENT", "connection %s:%s (%s msecs) %s", ip, port, Msecs(driver.starttime), to!string(driver.inbuffer.data));
          Thread.yield();
        }
      } catch(Exception e) { 
        warning("unknown client exception: %s", e.msg);
        terminated = true;
      }
      custom(1, "CLIENT", "connection %s:%s (%s) closed after %d requests %s (%s msecs)", ip, port, (driver.isSecure() ? "⚐" : "⚑"), 
                                                                                          driver.requests, driver.senddata, Msecs(driver.starttime));
      driver.destroy();                                               // Clear the response structure
    }

    final @property bool running() {
      if (driver.socket is null) return(false);
      return(!terminated && driver.socket.isAlive());
    }

    final @property long starttime(){
      return(Msecs(driver.starttime));
    }

    final @property long lastmodified(){
      return(Msecs(driver.modtime));
    }

    final @property void stop(){
      trace("connection %s:%s stop called", ip, port);
      terminated = true; 
    }

    final @property long port() const { 
      if (driver.address !is null) {
        return(to!long(driver.address.toPortString())); 
      } 
      return(-1); 
    }

    final @property string ip() const {
      if (driver.address !is null) {
        return(driver.address.toAddrString()); 
      }
      return("0.0.0.0"); 
    }
}

