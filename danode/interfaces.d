module danode.interfaces;

import danode.imports;
import danode.functions : Msecs;
import danode.response : Response;
import danode.log : NORMAL, INFO, DEBUG;

/* Client interface used by the server */
interface ClientInterface {
  @property bool    running();          /// Is the client still handling requests
  @property long    starttime();        /// When was the client last started
  @property long    lastmodified();     /// When was the client last modified
  @property void    stop();             /// Stop the client

  @property string  ip() const;         /// IP location of the client
  @property long    port() const;       /// Port at which the client is connected

  void run();                           /// Main client loop and logic
}

/* Connection/Driver interface available to the client */
abstract class DriverInterface {
  public:
    Appender!(char[])   inbuffer;            /// Input appender buffer
    Socket              socket;              /// Client socket for reading and writing
    long                requests = 0;        /// Number of requests we handled
    long[long]          senddata;            /// Size of data send per request
    SysTime             systime;             /// Time in ms since this process came alive
    SysTime             modtime;             /// Time in ms since this process was last modified
    Address             address;             /// Private address field
    bool                blocking = false;    /// Blocking communication ?
    int                 verbose = NORMAL;    /// Verbose level

    bool openConnection(); /// Open the connection
    void closeConnection(); /// Close the connection
    bool isAlive(); /// Is the connection alive ?
    @nogc bool isSecure() const nothrow; /// Are we secure ?

    // Receive upto maxsize of bytes from the client into the input buffer
    ptrdiff_t receive(Socket conn, ptrdiff_t maxsize = 4096);

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
    final @property string header() const { 
      if (headerEnd < 0 || headerEnd > inbuffer.data.length) return("");
      return(to!string(inbuffer.data[0 .. headerEnd()]));
    }
    // Byte input converted to body as string
    final @property string body() const {
      if (bodyStart < 0 || bodyStart > inbuffer.data.length) return("");
      return(to!string(inbuffer.data[bodyStart() .. $]));
    }

    // Where does the HTML request header end ?
    final @property ptrdiff_t headerEnd() const { 
      ptrdiff_t idx = to!string(inbuffer.data).indexOf("\r\n\r\n");
      if(idx <= 0) idx = to!string(inbuffer.data).indexOf("\n\n");
      return(idx);
    }

    // Where does the HTML request body begin ?
    final @property ptrdiff_t bodyStart() const { 
      ptrdiff_t idx = to!string(inbuffer.data).indexOf("\r\n\r\n");
      if (idx > 0) return (idx + 4);
      idx = to!string(inbuffer.data).indexOf("\n\n");
      if (idx > 0) return (idx + 2);
      return(-1);
    }

    // Do we have a header separator ? "\r\n\r\n" or "\n\n"
    final @property bool hasHeader() const {
      if(headerEnd() <= 0) return(false);
      return(true);
    }
}

class StringDriver : DriverInterface {
    this(string input) {
      this.socket = new Socket(AddressFamily.INET, SocketType.STREAM, ProtocolType.TCP);
      this.systime = Clock.currTime(); // Time in ms since this process came alive
      this.modtime = Clock.currTime(); // Time in ms since this process was modified
      inbuffer ~= input;
    }
    override bool openConnection() { return(true); }
    override void closeConnection() nothrow { }
    override bool isAlive() { return(true); }
    @nogc override bool isSecure() const nothrow { return(false); }
    override ptrdiff_t receive(Socket socket, ptrdiff_t maxsize = 4096) { return(inbuffer.data.length); }
    override void send(ref Response response, Socket socket, ptrdiff_t maxsize = 4096)  { 
      response.header();
      response.completed = true;
    }
}


