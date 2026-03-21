/** danode/interfaces.d - Abstract driver and client interfaces, StringDriver test stub
  * License: GPLv3 (https://github.com/DannyArends/DaNode) - Danny Arends **/
module danode.interfaces;

import danode.imports;

import danode.cgi : CGI;
import danode.functions : Msecs, sISelect, bodystart, endofheader, fullheader;
import danode.payload : PayloadType;
import danode.response : Response, setPayload;
import danode.statuscode : StatusCode;
import danode.log : log, error, Level;

/* Connection/Driver interface available to the client */
abstract class DriverInterface {
  public:
    Appender!(char[])   inbuffer;            /// Input appender buffer
    Socket              socket;              /// Client socket for reading and writing
    SocketSet           socketSet;           /// SocketSet used for non-blocking select on this connection
    long                requests = 0;        /// Number of requests we handled
    long[long]          senddata;            /// Size of data send per request
    SysTime             systime;             /// Time in ms since this process came alive
    SysTime             modtime;             /// Time in ms since this process was last modified
    Address             address;             /// Private address field

    this(Socket socket) {
      this.socket = socket;
      this.socketSet = new SocketSet();
      systime = Clock.currTime();
      touch(); 
    }
    bool socketReady() const { if (socket !is null) { return socket.isAlive(); } return false; }; /// Is the connection alive ?
    void touch() { modtime = Clock.currTime(); }
    void closeSocket() {
      try {
        if (socket !is null) { if (socket.isAlive()) { socket.shutdown(SocketShutdown.BOTH); } socket.close(); }
      } catch(Exception e) { error("Exception closing socket: %s", e.msg); }
    }

    // Receive a raw chunk without buffering into inbuffer - for streaming use
    final const(char)[] receiveChunk(ptrdiff_t maxsize = 65536) {
      // Drain any body bytes already in inbuffer first
      ptrdiff_t bs = bodyStart();
      if (bs >= 0 && bs < inbuffer.data.length) {
        auto buffered = inbuffer.data[bs .. $].dup;
        if (bs  > 0 && bs  <= inbuffer.data.length) {
          auto header = inbuffer.data[0 .. bs].dup;
          inbuffer.clear();
          inbuffer.put(header);
        }
        return buffered;
      }
      if (!socketReady()) return [];
      if (socketSet.sISelect(socket, false, 25) <= 0) return [];
      char[] tmpbuffer = new char[](maxsize);
      ptrdiff_t received = receiveData(tmpbuffer);
      if (received > 0) { touch(); return tmpbuffer[0 .. received]; }
      return [];
    }

    // Receive upto maxsize of bytes from the client into the input buffer
    ptrdiff_t receive(Socket socket, ptrdiff_t maxsize = 4096) {
      if (!socketReady()) return(-1);
      if (socketSet.sISelect(socket, false, 25) <= 0) return(0);
      ptrdiff_t received;
      char[] tmpbuffer = new char[](maxsize);
      if ((received = receiveData(tmpbuffer)) > 0) { inbuffer.put(tmpbuffer[0 .. received]); touch(); }
      if(received > 0) log(Level.Trace, "Received %d bytes of data", received);
      return(inbuffer.data.length);
    }

    long receiveData(ref char[] buffer);
    bool openConnection(bool blocking = false);
    void closeConnection();
    @nogc bool isSecure() const nothrow;

    // Send upto maxsize bytes from the response to the client
    void send(ref Response response, Socket conn, ptrdiff_t maxsize = 4096);

    final @property long port() const { if (address !is null){ return(to!long(address.toPortString())); } return(-1); }
    final @property string ip() const { if (address !is null){ return(address.toAddrString()); } return("0.0.0.0"); }
    final @property long starttime() const { return(Msecs(systime)); }
    final @property long lastmodified() const { return(Msecs(modtime)); }
    final @property string header() const { return(fullheader(inbuffer.data)); }

    // Byte input converted to body as string
    final @property string body() const {
      if (bodyStart < 0 || bodyStart > inbuffer.data.length) return("");
      return(to!string(inbuffer.data[bodyStart() .. $]));
    }

    final @property ptrdiff_t endOfHeader() const { return(endofheader(inbuffer.data)); }
    final @property ptrdiff_t bodyStart() const { return(bodystart(inbuffer.data)); }
    final @property bool hasHeader() const { return(endOfHeader > 0); }
}

// serve a 408 connection timed out page
void sendTimedOut(ref DriverInterface driver, ref Response response) {
  if(response.payload !is null && response.payload.type == PayloadType.Script){ to!CGI(response.payload).notifyovertime(); }
  response.setPayload(StatusCode.TimedOut, "408 - Connection Timed Out\n", "text/plain");
  driver.send(response, driver.socket);
}

// serve a 431 request header fields too large page
void sendHeaderTooLarge(ref DriverInterface driver, ref Response response) {
  response.setPayload(StatusCode.HeaderFieldsTooLarge, "431 - Request Header Fields Too Large\n", "text/plain");
  driver.send(response, driver.socket);
}

// serve a 413 payload too large page
void sendPayloadTooLarge(ref DriverInterface driver, ref Response response) {
  response.setPayload(StatusCode.PayloadTooLarge, "413 - Payload Too Large\n", "text/plain");
  driver.send(response, driver.socket);
}

class StringDriver : DriverInterface {
  public:
    StatusCode      lastStatus;
    string          lastMime;
    string          lastConnection;
    const(char)[]   lastBody;
    string[string]  lastHeaders;

  public:
    this(string input) { super(null); inbuffer ~= input; }
    override bool openConnection(bool blocking = false) { return(true); }
    override void closeConnection() nothrow { }
    override bool socketReady() const { return inbuffer.data.length > 0; }
    @nogc override bool isSecure() const nothrow { return(false); }
    override long receiveData(ref char[] buffer) { return(0); }  // unused - overriding receive() directly
    override ptrdiff_t receive(Socket socket, ptrdiff_t maxsize = 4096) {
      if (inbuffer.data.length != 0) touch();
      return(inbuffer.data.length);
    }
    override void send(ref Response response, Socket socket, ptrdiff_t maxsize = 4096) {
      response.header();
      lastStatus = response.statuscode;
      lastMime = response.payload.mimetype.idup;
      lastConnection = response.connection.idup;
      lastBody = response.payload.bytes(0, cast(ptrdiff_t) response.payload.length);
      lastHeaders = response.headers.dup;
      response.completed = true;
    }
}

