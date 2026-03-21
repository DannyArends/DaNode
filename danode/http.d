/** danode/http.d - Plain HTTP driver: non-blocking socket send/receive
  * License: GPLv3 (https://github.com/DannyArends/DaNode) - Danny Arends **/
module danode.http;

import danode.imports;

import danode.functions : sISelect;
import danode.interfaces : DriverInterface;
import danode.response : Response;
import danode.log : log, tag, error, Level;

class HTTP : DriverInterface {
  public:
    this(Socket socket) { super(socket); }

    // Open the connection by setting the socket to non blocking I/O, and registering the origin address
    override bool openConnection(bool blocking = false) {
      try {
        socket.blocking = blocking;
      } catch(Exception e) { error("Unable to accept socket: %s", e.msg); return(false); }
      try {
        address = socket.remoteAddress();
      } catch(Exception e) { error("Unable to resolve requesting origin: %s", e.msg); }
      return(true);
    }

    override long receiveData(ref char[] buffer) { return(socket.receive(buffer)); }

    // Send upto maxsize bytes from the response to the client
    override void send(ref Response response, Socket socket, ptrdiff_t maxsize = 4096) {
      if (!socketReady()) return;
      // Wait until socket is writable before sending
      if (socketSet.sISelect(socket, true, 0) <= 0) return;
      ptrdiff_t send = socket.send(response.bytes(maxsize));
      if (send > 0) {
        log(Level.Trace, "Send result=%d index=%d length=%d", send, response.index, response.length);
        touch();
        response.index += send;
        senddata[requests] += send;
        if(response.index >= response.length && response.canComplete) response.completed = true;
      }
    }

    // Close the connection, by shutting down the socket
    override void closeConnection() { closeSocket(); }

    @nogc override bool isSecure() const nothrow { return(false); }
}

unittest {
  tag(Level.Always, "FILE", "%s", __FILE__);
}

