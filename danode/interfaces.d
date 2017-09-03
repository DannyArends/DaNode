module danode.interfaces;

import std.array : Appender, appender;
import std.socket : Address, Socket;
import std.datetime : Clock, SysTime, msecs, dur;

import danode.response : Response;
import danode.log : NORMAL, INFO, DEBUG;

interface ClientInterface {
  @property bool    running();
  @property long    time();
  @property long    modified();
  @property void    stop();

  @property long    port() const;
  @property string  ip() const;

  void run(); 
}

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

    bool openConnection();
    ptrdiff_t receive(Socket conn, ptrdiff_t maxsize = 4096);
    void send(ref Response response, Socket conn, ptrdiff_t maxsize = 4096);
    bool isSecure();
}

