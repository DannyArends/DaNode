/** danode/http.d - Plain HTTP driver: non-blocking socket send/receive
  * License: GPLv3 (https://github.com/DannyArends/DaNode) - Danny Arends **/
module danode.http;

import danode.imports;

import danode.interfaces : DriverInterface, bodystart, endofheader;
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
      if (sISelect(true, 0) <= 0) return;
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

  // endofheader
  assert(endofheader("GET / HTTP/1.1\r\nHost: x\r\n\r\n") >= 0, "\\r\\n\\r\\n header must be found");
  assert(endofheader("GET / HTTP/1.1\nHost: x\n\n") >= 0, "\\n\\n header must be found");
  assert(endofheader("incomplete header") == -1, "no terminator must return -1");
  assert(endofheader("HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n\r\nbody content") == 40, "\\r\\n\\r\\n position must be 40");
  assert(endofheader("HTTP/1.1 200 OK\nContent-Type: text/html\n\nbody content") == 39,  "\\n\\n position must be 39");
  assert(endofheader("HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n") == -1, "incomplete must return -1");
  assert(endofheader("") == -1, "empty must return -1");
  // bodystart
  assert(bodystart("GET / HTTP/1.1\nHost: x\n\nbody") > 0, "bodystart must be positive");
  assert(bodystart("HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n\r\nbody content") == 44, "\\r\\n\\r\\n bodystart must be 44");
  assert(bodystart("HTTP/1.1 200 OK\nContent-Type: text/html\n\nbody content") == 41,  "\\n\\n bodystart must be 41");
  assert(bodystart("incomplete") == -1, "no terminator must return -1");
}
