module danode.http;

import std.datetime : Clock;
import std.stdio : writeln, writefln, stdin;
import std.socket : Socket, SocketShutdown;

import danode.interfaces : DriverInterface;
import danode.response : Response;
import danode.log : NORMAL, INFO, DEBUG;

class HTTP : DriverInterface {
  public:
    this(Socket socket, bool blocking = false, int verbose = NORMAL) { // writefln("[HTTP]   driver constructor");
      this.socket = socket;
      this.blocking = blocking;
      this.starttime = Clock.currTime();         /// Time in ms since this process came alive
      this.modtime = Clock.currTime();           /// Time in ms since this process was modified
    }

    override bool openConnection() {
      try {
        socket.blocking = this.blocking;
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
      if(socket is null) return;
      if(!socket.isAlive()) return;
      ptrdiff_t send = socket.send(response.bytes(maxsize));
      if(send >= 0) {
        if(send > 0) modtime = Clock.currTime();
        response.index += send; senddata[requests] += send;
        if(response.index >= response.length) response.completed = true;
      }
      // if(send > 0) writefln("[INFO]   send %d bytes of data", send);
    } }

    override void closeConnection() {
      if (socket !is null) {
        try {
          socket.shutdown(SocketShutdown.BOTH);
          socket.close();
        } catch(Exception e) {
          if(verbose >= INFO) writefln("[WARN]   unable to close socket: %s", e.msg);
        }
      }
    }

    override bool isAlive() { 
      if(socket !is null) { return socket.isAlive(); }
      return false;
    }

    override bool isSecure(){ return(false); }
}

unittest {
  writefln("[FILE]   %s", __FILE__);
}

