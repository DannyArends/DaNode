module danode.server;

import danode.imports;
import danode.functions : Msecs, sISelect;
import danode.client : Client;
import danode.interfaces : DriverInterface;
import danode.http : HTTP;
import danode.router : Router;
import danode.log;
import danode.serverconfig : ServerConfig;

version(SSL) {
  import danode.ssl : initSSL, closeSSL;
  import danode.https : HTTPS;
}

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
    this(ushort port = 80, int backlog = 100, string wwwRoot = "./www/", int verbose = NORMAL) {
      this.starttime = Clock.currTime();            // Start the timer
      this.router = new Router(wwwRoot, verbose);   // Start the router
      this.socket = initialize(port, backlog);      // Create the HTTP socket
      version(SSL) {
        this.sslsocket = initialize(443, backlog);  // Create the SSL / HTTPs socket
      }
      set = new SocketSet(1);                       // Create a server socket set
      writefln("[SERVER] server created backlog: %d", backlog);
      super(&run);
    }

    // Initialize the listening socket to a certain port and backlog
    Socket initialize(ushort port = 80, int backlog = 100) {
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

    // Accept an incoming connection and create a client object
    final Client accept(Socket socket, bool secure = false) {
      if (set.isSet(socket)) {
        try {
          DriverInterface driver = null;
          if(!secure) driver = new HTTP(socket.accept(), false, verbose);
          version(SSL) {
            if(secure) driver = new HTTPS(socket.accept(), false, verbose);
          }
          if(driver is null) return(null);
          Client client = new Client(router, driver);
          client.start();
          //Thread.sleep(dur!"msecs"(1));
          return(client);
        } catch(Exception e) {
          writefln("[ERROR]  unable to accept connection: %s", e.msg);
        }
      } else {
        writefln("[ERROR]  socket is not in the socketset");
      }
      return(null);
    }

    // is the server still running ?
    final @property bool running(){ synchronized {
      version(SSL) {
        return(socket.isAlive() && sslsocket.isAlive() && !terminated);
      } else {
        return(socket.isAlive() && !terminated);
      }
    } }

    // Stop all clients and shutdown the server
    final void stop(){ synchronized {
      foreach(ref Client client; clients){ client.stop(); } terminated = true;
    } }

     // Returns a Duration object holding the server uptime
    final @property Duration uptime() const { return(Clock.currTime() - starttime); }

     // Print some server information
    final @property void info() {
      writefln("[INFO]   uptime %s\n[INFO]   # of connections: %d / %d", uptime(), nAlive(), clients.length);
    }

    // Number of alive connections
    final @property long nAlive() {
      long sum = 0; foreach(Client client; clients){ if(client.running){ sum++; } } return sum; 
    }

    final @property int verbose(string verbose = "") { return(router.verbose(verbose)); } // Verbose level

    final void run() {
      int select;
      Appender!(Client[]) persistent;
      while(running) {
        try {
          persistent.clear();
          if ((select = set.sISelect(socket)) > 0) {           // writefln("Accepting HTTP request");
            Client client = this.accept(socket);
            if(client !is null) persistent.put(client);
          }
          version(SSL) {
            if ((select = set.sISelect(sslsocket)) > 0) {      // writefln("Accepting HTTPs request");
              Client client = this.accept(sslsocket, true);
              if(client !is null) persistent.put(client);
            }
          }
          foreach(Client client; clients){ if(client.running){ persistent.put(client); } }        // Add the backlog of persistent clients
          clients = persistent.data;
        } catch(Exception e) {
          writefln("[SERVER] ERROR: %s", e.msg);
        }
      }
      writefln("[INFO]  Server socket closed, running: %s", running);
      socket.close();
      version(SSL) {
        sslsocket.closeSSL();
      }
    }
}

void parseKeyInput(ref Server server){
  string line = chomp(stdin.readln());
  if(line.startsWith("quit")) server.stop();
  if(line.startsWith("info")) server.info();
  if(line.startsWith("verbose")) server.verbose(line);
}

void main(string[] args) {
  version(unittest){ ushort port = 8080; }else{ ushort port = 80; }
  int    backlog  = 100;
  int    verbose  = NORMAL;
  bool   keyoff   = false;
  string certDir  = ".ssl/";
  string keyFile  = ".ssl/server.key";
  string wwwRoot  = "./www/";
  getopt(args, "port|p",     &port,         // Port to listen on
               "backlog|b",  &backlog,      // Backlog of clients supported
               "keyoff|k",   &keyoff,       // Keyboard on or off
               "certDir",    &certDir,      // Location of SSL certificates
               "keyFile",    &keyFile,      // Server private key
               "wwwRoot",    &wwwRoot,      // Server www root folder
               "verbose|v",  &verbose);     // Verbose level (via commandline)
  version(unittest){
    // Do nothing, unittests will run
  } else {
    version(Posix) {
      import core.sys.posix.signal : signal, SIGPIPE;
      import danode.signals : handle_signal;
      signal(SIGPIPE, &handle_signal);
    }
    version(Windows) {
      writeln("[WARN]   -k has been set to true, we cannot handle keyboard input under windows at the moment");
      keyoff = true;
    }

    auto server = new Server(port, backlog, wwwRoot, verbose);
    version(SSL) {
      server.initSSL(certDir, keyFile);  // Load SSL certificates, using the server key
    }
    server.start();
    while(server.running){
      if(!keyoff){
        server.parseKeyInput();
      }
      stdout.flush();
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

