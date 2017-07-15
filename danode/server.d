module danode.server;

import core.stdc.stdlib : exit;
import core.stdc.stdio;
import core.thread : Thread;
import std.array : Appender, appender;
import std.datetime : Clock, dur, SysTime, Duration;
import std.socket : AddressFamily, InternetAddress, ProtocolType, Socket, SocketSet, SocketType, SocketOption, SocketOptionLevel;
import std.stdio : writefln, stdin;
import std.string : startsWith, format, chomp;
import danode.functions : Msecs, sISelect;
import danode.client : DriverInterface, Client, HTTP;
import danode.router : Router;
import danode.log;
import danode.serverconfig : ServerConfig;
version(SSL){
  import deimos.openssl.ssl;
  import danode.ssl : HTTPS, initSSL, closeSSL;
}
import std.getopt : getopt;

class Server : Thread {
  private:
    Socket            socket;           // The server socket
    SocketSet         set;              // SocketSet for server socket and client listeners
    Client[]          clients;          // List of clients
    bool              terminated;       // Server running
    SysTime           starttime;        // Start time of the server
    Router            router;           // Router to route requests
    version(SSL) {
      Socket          sslsocket;        // SSL / HTTPs socket
    }

  public:
    this(ushort port = 80, int backlog = 100, int verbose = NORMAL) {
      this.starttime = Clock.currTime();            // Start the timer
      this.router = new Router(verbose);            // Start the router
      this.socket = initialize(port, backlog);      // Create the HTTP socket
      version(SSL) {
        this.sslsocket = initialize(443, backlog);  // Create the SSL / HTTPs socket
        initSSL(this);                              // Initialize the SSL certificates
        backlog = (backlog * 2) + 1;                // Enlarge the backlog, for N clients and 1 ssl server socket
      }
      backlog = backlog + 1;                        // Add room for the server socket
      this.set = new SocketSet(backlog);            // Create a socket set
      writefln("[SERVER] server created backlog: %d", backlog);
      super(&run);
    }

    Socket initialize(ushort port = 80, int backlog = 200) {      // Initialize the listening socket to a certain port and backlog
      Socket socket;
      try {
        socket = new Socket(AddressFamily.INET, SocketType.STREAM, ProtocolType.TCP);
        socket.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, true);
        socket.blocking = false;
        socket.bind(new InternetAddress(port));
        socket.listen(backlog);
        writefln("[INFO]   socket listening on port %s", port);
      } catch(Exception e) {
        writefln("[ERROR]  unable to bind socket on port %s\n%s", port, e.msg);
        exit(-1);
      }
      return socket;
    }

    final Client accept(Socket socket, bool secure = false) {     // Create a connection to a client
      if (set.isSet(socket)) {
        try {
          DriverInterface driver = null;
          if(!secure) driver = new HTTP(socket.accept());
          version(SSL) {
            if(secure) driver = new HTTPS(socket.accept());
          }
          if(driver is null) return(null);
          Client client = new Client(router, driver);
          client.start();
          return(client);
        } catch(Exception e) {
          writefln("[ERROR]  unable to accept connection: %s", e.msg);
        }
      }
      return(null);
    }

    final @property bool running(){ synchronized {      // Is the server still running ?
      return(socket.isAlive() && !terminated); 
    } }

    final @property void stop(){ synchronized {     // Stop the server
      foreach(ref Client client; clients){ client.stop(); } terminated = true;
    } }

    final @property Duration time() const { return(Clock.currTime() - starttime); } // Time so far

    final @property void info() {     // Server information
      writefln("[INFO]   uptime %s\n[INFO]   # of connections: %d", time, connections);
    }

    final @property long connections() { // Number of connections
      long sum = 0; foreach(Client client; clients){ if(client.running){ sum++; } } return sum; 
    }

    final @property int verbose(string verbose = "") { return(router.verbose(verbose)); } // Verbose level

    final void run() {
      int select;
      Appender!(Client[]) persistent;
      while(running){
        persistent.clear();
        if((select = set.sISelect(socket)) > 0){           // writefln("Accepting HTTP request");
          Client client = accept(socket);
          if(client !is null) persistent.put(client);
        }
        version(SSL) {
          if((select = set.sISelect(sslsocket)) > 0){      // writefln("Accepting HTTPs request");
            Client client = accept(sslsocket, true);
            if(client !is null) persistent.put(client);
          }
        }
        foreach(Client client; clients){ if(client.running){ persistent.put(client); } }        // Add the backlog of persistent clients
        clients = persistent.data;
      }
      socket.close();
      version(SSL) {
        sslsocket.closeSSL();
      }
    }
}

void main(string[] args) {
  version(unittest){ ushort port     = 8080; }else{ ushort port     = 80; }
  int    backlog  = 100;
  int    verbose  = NORMAL;
  bool   keyoff   = false;
  getopt(args, "port|p",     &port,         // Port to listen on
               "backlog|b",  &backlog,      // Backlog of clients supported
               "keyoff|k",   &keyoff,       // Keyboard on or off
               "verbose|v",  &verbose);     // Verbose level (via commandline)
  version(unittest){
    // Do nothing, unittests will run
  }else{
    auto server = new Server(port, backlog, verbose);
    server.start();
    string line;
    while(server.running){
      if(!keyoff){
        line = chomp(stdin.readln());
        if(line.startsWith("quit")) server.stop();
        if(line.startsWith("info")) server.info();
        if(line.startsWith("verbose")) server.verbose(line);
      }
      fflush(stdout);
      Thread.sleep(dur!"msecs"(250));
    }
    writefln("[INFO]   Server shutting down: %d", server.running);
    server.info();
  }
}

unittest {
  writefln("[FILE]   %s", __FILE__);
  version(SSL) {
    writefln("[TEST]   SSL support");
  }else{
    writefln("[TEST]   No SSL support");
  }
}

