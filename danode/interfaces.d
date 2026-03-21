/** danode/interfaces.d - Abstract driver and client interfaces, StringDriver test stub
  * License: GPLv3 (https://github.com/DannyArends/DaNode) - Danny Arends **/
module danode.interfaces;

import danode.imports;

import danode.cgi : CGI;
import danode.functions : Msecs;
import danode.payload : PayloadType;
import danode.response : Response, setPayload;
import danode.statuscode : StatusCode;
import danode.log : log, error, Level;

/* Connection/Driver interface available to the client */
abstract class DriverInterface {
  public:
    Appender!(char[])   inbuffer;            /// Input appender buffer
    Socket              socket;              /// Client socket for reading and writing
    SocketSet           set;                 /// SocketSet used for non-blocking select on this connection
    long                requests = 0;        /// Number of requests we handled
    long[long]          senddata;            /// Size of data send per request
    SysTime             systime;             /// Time in ms since this process came alive
    SysTime             modtime;             /// Time in ms since this process was last modified
    Address             address;             /// Private address field

    this(Socket s) {
      socket = s;
      set = new SocketSet();
      systime = Clock.currTime();
      touch(); 
    }
    bool socketReady() const { if (socket !is null) { return socket.isAlive(); } return false; }; /// Is the connection alive ?
    void touch() { modtime = Clock.currTime(); }
    private ptrdiff_t readSocket(ref char[] tmpbuffer) {
      if (!socketReady() || sISelect(false, 25) <= 0) return 0;
      ptrdiff_t received = receiveData(tmpbuffer);
      if (received > 0) { touch(); log(Level.Trace, "Received %d bytes of data", received); }
      return received;
    }
    void closeSocket() {
      try {
        if (socket !is null) { if (socket.isAlive()) { socket.shutdown(SocketShutdown.BOTH); } socket.close(); }
      } catch(Exception e) { error("Exception closing socket: %s", e.msg); }
    }

    // Receive a raw chunk without buffering into inbuffer - for streaming use
    final const(char)[] receiveChunk(ptrdiff_t maxsize = 65536) {
      ptrdiff_t bs = bodyStart();
      if (bs > 0 && bs < inbuffer.data.length) {
        auto buffered = inbuffer.data[bs .. $].dup;
        auto header = inbuffer.data[0 .. bs].dup;
        inbuffer.clear();
        inbuffer.put(header);
        return(buffered);
      }
      char[] tmpbuffer = new char[](maxsize);
      ptrdiff_t received = readSocket(tmpbuffer);
      return(received > 0 ? tmpbuffer[0 .. received] : []);
    }

    // Receive upto maxsize of bytes from the client into the input buffer
    ptrdiff_t receive(ptrdiff_t maxsize = 4096) {
      char[] tmpbuffer = new char[](maxsize);
      ptrdiff_t received = readSocket(tmpbuffer);
      if (received > 0) inbuffer.put(tmpbuffer[0 .. received]);
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
    final @property string content() const {
      if (bodyStart < 0 || bodyStart > inbuffer.data.length) return("");
      return(to!string(inbuffer.data[bodyStart() .. $]));
    }
    
    // Reset the socketset and add a server socket to the set
    int sISelect(bool write = false, int timeout = 25) {
      set.reset();
      set.add(socket);
      return(write ? Socket.select(null, set, null, dur!"msecs"(timeout)) : Socket.select(set, null, null, dur!"msecs"(timeout)));
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

// get the HTTP header contained in the buffer (including the \r\n\r\n)
pure string fullheader(T)(const(T) buffer) {
  auto i = bodystart(buffer);
  if (i > 0 && i <= buffer.length) { return(to!string(buffer[0 .. i])); }
  return [];
}

// Where does the HTTP request header end ?
@nogc pure ptrdiff_t endofheader(T)(const(T) buffer) nothrow {
  ptrdiff_t len = buffer.length;
  for (ptrdiff_t i = 0; i < len - 1; i++) {
    if (i < len - 3 && buffer[i] == '\r' && buffer[i+1] == '\n' && buffer[i+2] == '\r' && buffer[i+3] == '\n') return i;
    if (buffer[i] == '\n' && buffer[i+1] == '\n') return i;
  }
  return -1;
}

// Where does the HTTP request body start ?
@nogc pure ptrdiff_t bodystart(T)(const(T) buffer) nothrow {
  ptrdiff_t i = endofheader(buffer);
  if (i < 0) return -1;
  return((i + 3 < buffer.length && buffer[i] == '\r' && buffer[i+1] == '\n') ? i + 4 : i + 2);
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
    override ptrdiff_t receive(ptrdiff_t maxsize = 4096) {
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

