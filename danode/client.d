module danode.client;

import core.thread : Thread;
import std.array : Appender, appender;
import std.conv : to;
import std.datetime : Clock, SysTime, msecs;
import std.socket : Address, Socket;
import std.stdio : write, writefln, writeln;
import danode.functions : Msecs;
import danode.router : Router;
import danode.response : Response;
import danode.request : Request;
import danode.log : NORMAL, INFO, DEBUG;

interface ClientInterface {
  @property bool    running();
  @property long    time();
  @property long    modified();
  @property void    stop();

  @property long    port() const;
  @property string  ip() const;

  @property void    set(Request req);
  @property Request get();

  void run(); 
}

abstract class DriverInterface {
  public:
    Appender!(char[])   inbuffer;            /// Input appender buffer
    Socket              socket;              /// Client socket for reading and writing
    long                requests = 0;        /// Number of requests we handled
    long[long]          senddata;            /// Size of data send per request
    SysTime             starttime;           /// Time in ms since this process came alive
    SysTime             modtime;             /// Time in ms since this process was last modified
    Address             address;             /// Private  address field

    long receive(Socket conn, long maxsize = 4096);
    void send(ref Response response, Socket conn, long maxsize = 4096);
    bool isSecure();
}

class Client : Thread, ClientInterface {
  private:
    Router              router;              /// Router class from server
    DriverInterface     driver;              /// Driver
    long                maxtime;             /// Maximum quiet time before we cut the connection
    Request             request;             /// Request structure
  public:
    bool                terminated;          /// Is the client / connection terminated

    this(Router router, DriverInterface driver, long maxtime = 5000){ // writefln("[INFO]   client constructor");
      this.driver           = driver;
      this.router           = router;
      this.maxtime          = maxtime;
      super(&run);
    }

   final void run(){
      if(router.verbose >= INFO) writefln("[INFO]   connection established %s %d", ip(), port() );
      try{
        Response response;
        while(running && modified < maxtime){
          if(driver.receive(driver.socket) > 0){                                    // We've received new data
            if(!response.ready){                                                    // If we're not ready to respond yet
              router.route(this, response, to!string(driver.inbuffer.data));        // Parse the data and try to create a response (Could fail multiple times)
            }
            if(response.ready && !response.completed){                              // We know what to respond, but haven't send all of it yet
              driver.send(response, driver.socket);                                 // Send the response, this function gets hit multiple times, so just send what you can and return
            }
            if(response.ready && response.completed){                               // We've completed the request, response cycle
              router.logrequest(this, response);                                    // Log the response to the request
              if(!response.keepalive) stop();                                       // No keep alive, then stop this client
              response.destroy();                                                   // Clear the response
              driver.inbuffer.destroy();                                            // Clear the input buffer
              driver.requests++;
            }
          }
          Thread.yield();
        }
      }catch(Exception e){ writefln("[WARN]   unknown client exception: %s", e.msg); }
      if(router.verbose >= INFO) writefln("[INFO]   connection %s:%s (%s) closed after %d requests %s (%s msecs)", ip, port, driver.isSecure(), driver.requests, driver.senddata, Msecs(driver.starttime));
      driver.socket.close();
    }

    final @property void    set(Request req) { request = req; }
    final @property Request get() { return(request); }

    final @property bool    running(){   synchronized { return(driver.socket.isAlive() && isRunning() && !terminated); } }          // Is the client still running ?
    final @property long    time(){      synchronized { return(Msecs(driver.starttime)); } }                                        // Time since start of request
    final @property long    modified(){  synchronized { return(Msecs(driver.modtime)); } }                                          // Time since last modified
    final @property void    stop(){      synchronized { terminated = true; } }                                               // Stop the client

    final @property long    port() const { if(driver.address !is null){ return(to!long(driver.address.toPortString())); } return(-1); }    // Client port
    final @property string  ip() const { if(driver.address !is null){ return(driver.address.toAddrString()); } return("0.0.0.0"); }        // Client IP
}

class HTTP : DriverInterface {
  public:
    this(Socket socket, bool blocking = false){ // writefln("[HTTP]   driver constructor");
      this.socket           = socket;
      this.socket.blocking  = blocking;
      this.starttime        = Clock.currTime();           /// Time in ms since this process came alive
      this.modtime          = Clock.currTime();           /// Time in ms since this process was modified
      try{
        this.address        = socket.remoteAddress();
      }catch(Exception e){ writefln("[WARN]   unable to resolve requesting origin"); }
    }

    override long receive(Socket socket, long maxsize = 4096){ synchronized {
      long received;
      char[] tmpbuffer = new char[](maxsize);
      if((received = socket.receive(tmpbuffer)) > 0){
        inbuffer.put(tmpbuffer[0 .. received]); modtime = Clock.currTime();
      }
      return(inbuffer.data.length);
    } }

    override void send(ref Response response, Socket socket, long maxsize = 4096){ synchronized {
      long send = socket.send(response.bytes(maxsize));
      if(send >= 0){
        response.index += send; modtime = Clock.currTime(); senddata[requests] += send;
        if(response.index >= response.length) response.completed = true;
      }
    } }

    override bool isSecure(){ return(false); }
}

unittest {
  writefln("[FILE]   %s", __FILE__);
}

