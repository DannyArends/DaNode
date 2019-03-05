module danode.http;

import danode.imports;
import danode.interfaces : DriverInterface;
import danode.response : Response;
import danode.log : custom, warning, error;

class HTTP : DriverInterface {
  public:
    this(Socket socket, bool blocking = false) {
      custom(3, "HTTP", "HTTP constructor");
      this.socket = socket;
      this.blocking = blocking;
      this.systime = Clock.currTime(); // Time in ms since this process came alive
      this.modtime = Clock.currTime(); // Time in ms since this process was modified
    }

    // Open the connection by setting the socket to non blocking I/O, and registering the origin address
    override bool openConnection() {
      try {
        socket.blocking = this.blocking;
      } catch(Exception e) {
        error("unable to accept socket: %s", e.msg);
        return(false);
      }
      try {
        this.address = socket.remoteAddress();
      } catch(Exception e) {
        warning("unable to resolve requesting origin: %s", e.msg);
      }
      return(true);
    }

    // Receive upto maxsize of bytes from the client into the input buffer
    override ptrdiff_t receive(Socket socket, ptrdiff_t maxsize = 4096) {
      if(socket is null) return(-1);
      if(!socket.isAlive()) return(-1);
      ptrdiff_t received;
      char[] tmpbuffer = new char[](maxsize);
      if ((received = socket.receive(tmpbuffer)) > 0) {
        inbuffer.put(tmpbuffer[0 .. received]); modtime = Clock.currTime();
      }
      if(received > 0) custom(3, "HTTP", "received %d bytes of data", received);
      return(inbuffer.data.length);
    }

    // Send upto maxsize bytes from the response to the client
    override void send(ref Response response, Socket socket, ptrdiff_t maxsize = 4096)  { synchronized {
      if(socket is null) return;
      if(!socket.isAlive()) return;
      ptrdiff_t send = socket.send(response.bytes(maxsize));
      if (send >= 0) {
        if (send > 0) modtime = Clock.currTime();
        response.index += send; senddata[requests] += send;
        if(response.index >= response.length) response.completed = true;
      }
      if(send > 0) custom(3, "HTTP", "send %d bytes of data", send);
    } }

    // Close the connection, by shutting down the socket
    override void closeConnection() nothrow {
      if (socket !is null) {
        try {
          socket.shutdown(SocketShutdown.BOTH);
          socket.close();
        } catch(Exception e) {
          warning("unable to close socket: %s", e.msg);
        }
      }
    }

    // Is the connection alive ?, make sure we check for null
    override bool isAlive() { 
      if (socket !is null) return(socket.isAlive());
      return false;
    }

    @nogc override bool isSecure() const nothrow { return(false); }
}

unittest {
  custom(0, "FILE", "%s", __FILE__);
}
