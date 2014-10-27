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

interface ClientInterface(T) {
  @property bool    running();
  @property long    time();
  @property long    modified();

  void run(); 

  long receive(T conn, long maxsize = 4096);
  void send(ref Response response, T conn, long maxsize = 4096);
}

class Client : Thread, ClientInterface!Socket {
  private:
    Socket              socket;              /// Client socket for reading and writing
    Address             address;             /// Private  address field
    bool                terminated;          /// Is the client / connection terminated
    SysTime             starttime;           /// Time in ms since this process came alive
    SysTime             modtime;             /// Time in ms since this process was last modified
    long                maxtime;             /// Maximum quiet time before we cut the connection
    Appender!(char[])   inbuffer;            /// Input appender buffer
    Router              router;              /// Router class from server
    long                requests;            /// Number of requests we handled
    long[long]          senddata;            /// Size of data send per request
    Request             request;             /// Request structure

  public:
    this(Router router, Socket socket, bool blocking = false, long maxtime = 5000){
      this.router           = router;
      this.starttime        = Clock.currTime();
      this.modtime          = starttime;
      this.socket           = socket;
      this.socket.blocking  = blocking;
      this.maxtime          = maxtime;
      try{
        this.address        = socket.remoteAddress();
      }catch(Exception e){ writefln("[WARN]   unable to resolve requesting origin"); }
      super(&run);
    }


    final @property void    set(Request lastrequest) { request = lastrequest; }
    final @property Request lastrequest() { return(request); }
    final @property bool    running(){   synchronized { return(socket.isAlive() && isRunning() && !terminated); } }          // Is the client still running ?
    final @property long    time(){      synchronized { return(Msecs(starttime)); } }                                        // Time since start of request
    final @property long    modified(){  synchronized { return(Msecs(modtime)); } }                                          // Time since last modified
    final @property void    stop(){      synchronized { terminated = true; } }                                               // Stop the client
    final @property long    port() const { if(address !is null){ return(to!long(address.toPortString())); } return(-1); }    // Client port
    final @property string  ip() const { if(address !is null){ return(address.toAddrString()); } return("0.0.0.0"); }        // Client IP

    final long receive(Socket socket, long maxsize = 4096){ synchronized {
      long received;
      char[] tmpbuffer = new char[](maxsize);
      if((received = socket.receive(tmpbuffer)) > 0){
        inbuffer.put(tmpbuffer[0 .. received]); modtime = Clock.currTime();
      }
      return(inbuffer.data.length);
    } }

    final void send(ref Response response, Socket socket, long maxsize = 4096){ synchronized {
      long send = socket.send(response.bytes(maxsize));
      if(send >= 0){
        response.index += send; modtime = Clock.currTime(); senddata[requests] += send;
        if(response.index >= response.length) response.completed = true;
      }
    } }

    final void run(){
      if(router.verbose >= INFO) writefln("[INFO]   connection established %s %d", ip(), port() );
      try{
        Response response;
        while(running && modified < maxtime){
          if(receive(socket) > 0){                                        // We've received new data
            if(!response.ready){                                            // If we're not ready to respond yet
              router.route(this, response, to!string(inbuffer.data));       // Parse the data and try to create a response (Could fail multiple times)
            }
            if(response.ready && !response.completed){                    // We know what to respond, but haven't send all of it yet
              send(response, socket);                                       // Send the response, this function gets hit multiple times, so just send what you can and return
            }
            if(response.ready && response.completed){                     //We've completed the request, response cycle
              router.logrequest(this, response);                            // Log the response to the request
              if(!response.keepalive) stop();                               // No keep alive, then stop this client
              response.destroy();                                           // Clear the response
              inbuffer.destroy();                                           // Clear the input buffer
              requests++;
            }
          }
          Thread.yield();
        }
      }catch(Exception e){ writefln("[WARN]   unknown client exception: %s", e.msg); }
      if(router.verbose >= INFO) writefln("[INFO]   connection %s:%s closed after %d requests %s (%s msecs)", ip, port, requests, senddata, Msecs(starttime));
      socket.close();
    }
}

