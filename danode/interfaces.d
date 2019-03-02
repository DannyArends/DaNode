module danode.interfaces;

import danode.imports;
import danode.response : Response;
import danode.log : NORMAL, INFO, DEBUG;

/* Client interface used by the server */
interface ClientInterface {
  @property bool    running();          /// Is the client still handling requests
  @property long    starttime();        /// When was the client last started
  @property long    lastmodified();     /// When was the client last modified
  @property void    stop();             /// Stop the client

  @property long    port() const;       /// Port at which the client is connected
  @property string  ip() const;         /// IP location of the client

  void run();                           /// Main client loop and logic
}

/* Connection/Driver interface available to the client */
abstract class DriverInterface {
  public:
    Appender!(char[])   inbuffer;            /// Input appender buffer
    Socket              socket;              /// Client socket for reading and writing
    long                requests = 0;        /// Number of requests we handled
    long[long]          senddata;            /// Size of data send per request
    SysTime             starttime;           /// Time in ms since this process came alive
    SysTime             modtime;             /// Time in ms since this process was last modified
    Address             address;             /// Private address field
    bool                blocking = false;    /// Blocking communication ?
    int                 verbose = NORMAL;    /// Verbose level

    bool openConnection();    /// Open the connection
    void closeConnection();   /// Close the connection
    bool isAlive();           /// Is the connection alive ?
    bool isSecure();          /// Are we secure ?

    // Receive upto maxsize of bytes from the client into the input buffer
    ptrdiff_t receive(Socket conn, ptrdiff_t maxsize = 4096);

    // Send upto maxsize bytes from the response to the client
    void send(ref Response response, Socket conn, ptrdiff_t maxsize = 4096);
}

