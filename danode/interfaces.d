/** danode/interfaces.d - Abstract driver and client interfaces, StringDriver test stub
  * License: GPLv3 (https://github.com/DannyArends/DaNode) - Danny Arends **/
module danode.interfaces;

import danode.imports;
import danode.functions : Msecs, sISelect, bodystart, endofheader, fullheader;
import danode.response : Response;
import danode.statuscode : StatusCode;
import danode.log : log, error, Level;

/* Client interface used by the server */
interface ClientInterface {
  @property bool    running();          /// Is the client still handling requests
  @property long    starttime();        /// When was the client last started
  @property long    lastmodified();     /// When was the client last modified
  @property void    stop();             /// Stop the client

  @property long requests() const;      /// Number of requests served
  @property string  ip() const;         /// IP location of the client
  @property long    port() const;       /// Port at which the client is connected

  void run();                           /// Main client loop and logic
}

/* Connection/Driver interface available to the client */
abstract class DriverInterface {
  public:
    Appender!(char[])   inbuffer;            /// Input appender buffer
    Socket              socket;              /// Client socket for reading and writing
    SocketSet           socketSet;
    long                requests = 0;        /// Number of requests we handled
    long[long]          senddata;            /// Size of data send per request
    SysTime             systime;             /// Time in ms since this process came alive
    SysTime             modtime;             /// Time in ms since this process was last modified
    Address             address;             /// Private address field
    bool                blocking = false;    /// Blocking communication ?

    this(Socket socket, bool blocking = false) {
      this.socket = socket;
      this.socketSet = new SocketSet();
      this.blocking = blocking;
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
    bool openConnection(); /// Open the connection
    void closeConnection(); /// Close the connection
    @nogc bool isSecure() const nothrow; /// Are we secure ?

    // Send upto maxsize bytes from the response to the client
    void send(ref Response response, Socket conn, ptrdiff_t maxsize = 4096);

    // port being used for communication
    final @property long port() const { 
      if (address !is null) return(to!long(address.toPortString())); 
      return(-1); 
    }

    // IP address connected to
    final @property string ip() const {
      if (address !is null) return(address.toAddrString());
      return("0.0.0.0"); 
    }

    // Milliseconds since start of connection
    final @property long starttime() const { return(Msecs(systime)); }

    // Milliseconds since last modified
    final @property long lastmodified() const { return(Msecs(modtime)); }

    // Byte input converted to header as string
    final @property string header() const { return(fullheader(inbuffer.data)); }

    // Byte input converted to body as string
    final @property string body() const {
      if (bodyStart < 0 || bodyStart > inbuffer.data.length) return("");
      return(to!string(inbuffer.data[bodyStart() .. $]));
    }

    // Where does the HTTP request header end ?
    final @property ptrdiff_t endOfHeader() const { return(endofheader(inbuffer.data)); }

    // Where does the HTTP request body begin ?
    final @property ptrdiff_t bodyStart() const { return(bodystart(inbuffer.data)); }

    // Do we have a header separator ? "\r\n\r\n" or "\n\n"
    final @property bool hasHeader() const { return(endOfHeader > 0); }
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
    override bool openConnection() { return(true); }
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

