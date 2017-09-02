module danode.client;

import core.thread : Thread;
import std.array : Appender, appender;
import std.conv : to;
import std.datetime : Clock, SysTime, msecs, dur;
import std.socket : Address, Socket;
import std.string;
import std.stdio : write, writefln, writeln;
import danode.functions : Msecs;
import danode.router : Router;
import danode.httpstatus : StatusCode;
import danode.response : Response;
import danode.request : Request;
import danode.payload : Message;
import danode.log : NORMAL, INFO, DEBUG;

interface ClientInterface {
  @property bool    running();
  @property long    time();
  @property long    modified();
  @property void    stop();

  @property long    port() const;
  @property string  ip() const;

  void run(); 
}

abstract class DriverInterface {
  public:
    Appender!(char[])   inbuffer;            /// Input appender buffer
    Socket              serversocket;        /// Server socket for accepting the connection
    Socket              socket;              /// Client socket for reading and writing
    long                requests = 0;        /// Number of requests we handled
    long[long]          senddata;            /// Size of data send per request
    SysTime             starttime;           /// Time in ms since this process came alive
    SysTime             modtime;             /// Time in ms since this process was last modified
    Address             address;             /// Private address field

    bool openConnection();
    ptrdiff_t receive(Socket conn, ptrdiff_t maxsize = 4096);
    void send(ref Response response, Socket conn, ptrdiff_t maxsize = 4096);
    bool isSecure();
}

class Client : Thread, ClientInterface {
  private:
    Router              router;              /// Router class from server
    DriverInterface     driver;              /// Driver
    long                maxtime;             /// Maximum quiet time before we cut the connection
  public:
    bool                terminated;          /// Is the client / connection terminated

    this(Router router, DriverInterface driver, long maxtime = 5000){ // writefln("[INFO]   client constructor");
      this.driver           = driver;
      this.router           = router;
      this.maxtime          = maxtime;
      super(&run);
    }

   final void run() {
      if(router.verbose >= DEBUG) writefln("[DEBUG]  new connection established %s:%d", ip(), port() );
      try {
        if(this.driver.openConnection() == false){
          this.terminated = true;
          return;
        }
        Request request;
        Response response;
        while(running && modified < maxtime) {
          if(driver.receive(driver.socket) > 0){                      // We've received new data
            if(!response.ready){                                      // If we're not ready to respond yet
              // Parse the data and try to create a response (Could fail multiple times)
              router.route(ip(), port(), request, response, to!string(driver.inbuffer.data), driver.isSecure());
            }
            if(response.ready && !response.completed){                          // We know what to respond, but haven't send all of it yet
              driver.send(response, driver.socket);                             // Send the response, hit multiple times, send what you can and return
            }
            if(response.ready && response.completed){                           // We've completed the request, response cycle
              router.logrequest(this, request, response);                       // Log the response to the request
              request.clearUploadFiles();                                       // Remove any upload files left over
              request.destroy();                                                // Clear the request and uploaded files
              driver.inbuffer.destroy();                                        // Clear the input buffer
              driver.requests++;
              if(!response.keepalive) stop();                                   // No keep alive, then stop this client
              response.destroy();                                               // Clear the response
            }

          } else {
            Thread.sleep(dur!"msecs"(1));
          }
          // writefln("[INFO]   connection %s:%s (%s msecs) %s", ip, port, Msecs(driver.starttime), to!string(driver.inbuffer.data));
          Thread.yield();
        }
      } catch(Exception e) { 
        writefln("[WARN]   unknown client exception: %s", e.msg);
      }
      if(router.verbose >= INFO) {
        writefln("[INFO]   connection %s:%s (%s) closed after %d requests %s (%s msecs)", ip, port, (driver.isSecure() ? "⚐" : "⚑"), 
                                                                                          driver.requests, driver.senddata, Msecs(driver.starttime));
      }
      if(driver.socket !is null) {
        driver.socket.close();
      }
    }

    final @property bool running() {
      if(driver.socket is null) return(false);
      return(driver.socket.isAlive() && !terminated);
    }

    final @property long time(){
      return(Msecs(driver.starttime));
    }

    final @property long modified(){
      return(Msecs(driver.modtime));
    }

    final @property void stop(){
      if(router.verbose >= DEBUG) writefln("[DEBUG]  connection %s:%s stop called", ip, port);
      terminated = true; 
    }

    final @property long port() const { 
      if(driver.address !is null){ 
        return(to!long(driver.address.toPortString())); 
      } 
      return(-1); 
    }

    final @property string ip() const {
      if(driver.address !is null){
        return(driver.address.toAddrString()); 
      }
      return("0.0.0.0"); 
    }
}

class HTTP : DriverInterface {
  private:
    bool blocking = false;
    int verbose = NORMAL;

  public:
    this(Socket socket, bool blocking = false, int verbose = NORMAL) { // writefln("[HTTP]   driver constructor");
      this.serversocket = socket;
      this.blocking = blocking;
      this.starttime = Clock.currTime();         /// Time in ms since this process came alive
      this.modtime = Clock.currTime();           /// Time in ms since this process was modified
    }

    override bool openConnection() {
      try {
        this.socket = this.serversocket.accept();      // Accept the incoming socket connection
        this.socket.blocking = this.blocking;
      } catch(Exception e) {
        writefln("[ERROR]  unable to accept socket: %s", e.msg);
        return(false);
      }
      try {
        this.address = socket.remoteAddress();
      } catch(Exception e) {
        if(verbose >= INFO) writefln("[WARN]   unable to resolve requesting origin: %s", e.msg);
      }
      return(true);
    }

    override ptrdiff_t receive(Socket socket, ptrdiff_t maxsize = 4096) {
      ptrdiff_t received;
      char[] tmpbuffer = new char[](maxsize);
      if(!socket.isAlive()) return(-1);
      if((received = socket.receive(tmpbuffer)) > 0) {
        inbuffer.put(tmpbuffer[0 .. received]); modtime = Clock.currTime();
      }
      // if(received > 0) writefln("[INFO]   received %d bytes of data", received);
      return(inbuffer.data.length);
    }

    override void send(ref Response response, Socket socket, ptrdiff_t maxsize = 4096)  { synchronized {
      if(!socket.isAlive()) return;
      ptrdiff_t send = socket.send(response.bytes(maxsize));
      if(send >= 0) {
        response.index += send; modtime = Clock.currTime(); senddata[requests] += send;
        if(response.index >= response.length) response.completed = true;
      }
      // if(send > 0) writefln("[INFO]   send %d bytes of data", send);
    } }

    override bool isSecure(){ return(false); }
}

unittest {
  writefln("[FILE]   %s", __FILE__);
}

