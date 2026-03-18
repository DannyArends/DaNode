/** danode/server.d - Entry point: socket setup, connection acceptance, rate limiting
  * License: GPLv3 (https://github.com/DannyArends/DaNode) - Danny Arends **/
module danode.server;

import danode.imports;
import danode.functions : from, Msecs, sISelect, resolveFolder;
import danode.client : Client;
import danode.interfaces : DriverInterface;
import danode.http : HTTP;
import danode.router : Router;
import danode.log : cv, abort, log, tag, error, Level;

version(SSL) {
  import danode.acme : checkAndRenew;
  import danode.ssl : loadSSL, closeSSL;
  import danode.https : HTTPS;
}

immutable int MAX_CLIENTS = 2048;
immutable int MAX_CLIENTS_PER_IP = 32;

class Server : Thread {
  private:
    Socket              socket;                 // The server socket
    SocketSet           set;                    // SocketSet for server socket and client listeners
    Client[]            clients;                // List of clients
    bool                terminated;             // Server running
    SysTime             starttime;              // Start time of the server
    Router              router;                 // Router to route requests
    long[string]        nAlivePerIP;

  public:
    string wwwFolder    = "www/";

    version(SSL) {
      private:
        Socket sslsocket;                     // SSL / HTTPs socket
        string ssl        = "server.key";
        string account    = "account.key";
      public:
        string sslPath  = ".ssl/";
    }

  public:
    this(ushort port = 80, int backlog = 100, string wwwFolder = "www/",
         string sslFolder = ".ssl/", string sslKey = "server.key", string accountKey = "account.key") {
      starttime = Clock.currTime();                             // Start the timer
      socket = initialize(port, backlog);                       // Create the HTTP socket
      router = new Router(wwwFolder, socket.localAddress());    // Start the router
      version(SSL) {
        sslPath = sslFolder.resolveFolder();
        ssl = sslKey;
        account = accountKey;
        sslsocket = initialize(443, backlog);  // Create the SSL / HTTPs socket
      }
      set = new SocketSet(1);                       // Create a server socket set
      log(Level.Always, "Server '%s' created backlog: %d", this.hostname(), backlog);
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
        log(Level.Always, "Socket listening port %s", port);
      } catch(Exception e) { abort(format("unable to bind socket on port %s\n%s", port, e.msg), -1); }
      return socket;
    }

    // Accept an incoming connection and create a client object
    final void accept(ref Appender!(Client[]) persistent, Socket socket, bool secure = false) {
      if (set.sISelect(socket) <= 0 || nAlive >= MAX_CLIENTS) return;
      log(Level.Trace, "Accepting %s request", secure ? "HTTPs" : "HTTP");
      try {
          DriverInterface driver = null;
          if (!secure) driver = new HTTP(socket.accept(), false);
          version(SSL) { if (secure) driver = new HTTPS(socket.accept(), false); }
          if (driver is null) return;
          Client client = new Client(router, driver);
          client.start();
          if (nAlivePerIP.from(client.ip, 0) <= MAX_CLIENTS_PER_IP) {
            persistent.put(client);
          } else { log(Level.Always, "Rate limit exceeded [%s]", client.ip); client.stop(); }
      } catch(Exception e) { error("Unable to accept connection: %s", e.msg); }
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

    final @property long nAlive() { return nAlivePerIP.byValue.sum; }

     // Returns a Duration object holding the server uptime
    final @property Duration uptime() const { return(Clock.currTime() - starttime); }

     // Print some server information
    final @property void info() { log(Level.Always, "Uptime %s, Connections: %d / %d", uptime(), nAlive, clients.length); }
    
    // Hostname of the server
    final @property string hostname() { return(socket.hostName()); }
    version(SSL) {
      final @property string sslKey() { return(sslPath ~ ssl); }
      final @property string accountKey() { return(sslPath ~ account); }
    }

    final void run() {
      Appender!(Client[]) persistent;
      SysTime lastScan = Clock.currTime();
      while(running) {
        try {
          Client[] previous = clients;                            // Slice reference
          persistent.clear();                                     // Clear the Appender
          accept(persistent, socket);
          version (SSL) { accept(persistent, sslsocket, true); }

          nAlivePerIP = null;
          foreach (Client client; previous) {   // Foreach through the Slice reference
            if(client.running) { nAlivePerIP[client.ip]++; persistent.put(client); }
            else if(!client.isRunning) client.join();           // join finished threads
          }
          clients = persistent.data;
          if (Msecs(lastScan) > 86_400_000) {   // Scan for deleted files & expiring certificates every day
            router.scan();
            version(SSL) { checkAndRenew(sslPath, sslKey, accountKey); }
            lastScan = Clock.currTime();
          }
        } catch(Exception e) { error("Unspecified top level server exception: %s", e.msg);
        } catch(Error e) { error("Unspecified top level server error: %s", e.msg); }
      }
      log(Level.Always, "Server socket closed, running: %s", running);
      socket.close();
      version (SSL) { sslsocket.closeSSL(); }
    }
}

void parseKeyInput(ref Server server){
  string line = chomp(stdin.readln());
  if (line.startsWith("quit")) server.stop();
  if (line.startsWith("info")) server.info();
}

void main(string[] args) {
  version(unittest){ ushort port = 8080; }else{ ushort port = 80; }
  int    backlog      = 100;
  int    verbose      = Level.Verbose;
  bool   keyoff       = false;
  string wwwFolder    = "www/";
  string sslFolder    = ".ssl/";
  string sslKey       = "server.key";
  string accountKey   = "account.key";
  
  getopt(args, "port|p",      &port,         // Port to listen on
               "backlog|b",   &backlog,      // Backlog of clients supported
               "keyoff|k",    &keyoff,       // Keyboard on or off
               "www",         &wwwFolder,    // Server www root folder
               "ssl",         &sslFolder,    // Location of SSL certificates
               "sslKey",      &sslKey,       // Server private key
               "accountKey",  &accountKey,   // Server Let's encrypt account key
               "verbose|v",   &verbose);     // Verbose level (via commandline)
  atomicStore(cv, verbose);
  version (unittest) {
    // Do nothing, unittests will run
  } else {
    version (Posix) {
      import core.sys.posix.signal : signal, SIGPIPE;
      import danode.signals : handle_signal;
      signal(SIGPIPE, &handle_signal);
    }
    version (Windows) {
      log(Level.Always, "-k was set to true. However, keyboard input under windows is not supported");
      keyoff = true;
    }
    auto server = new Server(port, backlog, wwwFolder, sslFolder, sslKey, accountKey);
    version (SSL) {
      loadSSL(server.sslPath, server.sslKey);                             // Load SSL certificates
      checkAndRenew(server.sslPath, server.sslKey, server.accountKey);    // checkAndRenew SSL certificates
    }
    server.start();
    while (server.running) {
      if (!keyoff) { server.parseKeyInput(); }
      stdout.flush();
      Thread.sleep(dur!"msecs"(250));
    }
    log(Level.Always, "Server shutting down: %d", server.running);
    server.info();
  }
}

unittest {
  tag(Level.Always, "FILE", "%s", __FILE__);
  version(SSL) {
    tag(Level.Always, "TEST", "SSL support");
  }else{
    tag(Level.Always, "TEST", "No SSL support");
  }
}

