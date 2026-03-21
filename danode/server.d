/** danode/server.d - Entry point: socket setup, connection acceptance, rate limiting
  * License: GPLv3 (https://github.com/DannyArends/DaNode) - Danny Arends **/
module danode.server;

import danode.imports;

import danode.log : cv, abort, log, tag, error, Level;
import danode.functions : Msecs, sISelect, resolveFolder;
import danode.interfaces : DriverInterface;
import danode.http : HTTP;
import danode.router : Router;
import danode.signals : shutdownSignal, registerExitHandler;
import danode.workerpool : WorkerPool;
import danode.webconfig : serverConfig, ServerConfig, serverConfigMutex;

version(SSL) {
  import danode.acme : checkAndRenew;
  import danode.ssl : loadSSL, closeSSL;
  import danode.https : HTTPS;
}

class Server {
  private:
    Socket              socket;                 // The server socket
    SocketSet           set;                    // SocketSet for server socket and client listeners
    SysTime             starttime;              // Start time of the server
    WorkerPool          pool;

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
      starttime = Clock.currTime(); // Start the timer
      socket = initialize(port, backlog); // Create the HTTP socket
      pool = new WorkerPool(new Router(wwwFolder, socket.localAddress()));
      version(SSL) {
        sslPath = sslFolder.resolveFolder();
        ssl = sslKey;
        account = accountKey;
        sslsocket = initialize(443, backlog);  // Create the SSL / HTTPs socket
      }
      set = new SocketSet();
      log(Level.Always, "Server '%s' created backlog: %d", this.hostname(), backlog);
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
    final void accept(Socket socket, bool secure = false) {
      if (set.sISelect(socket, false, 5) <= 0) return;
      try {
        Socket accepted = socket.accept();
        string ip = accepted.remoteAddress().toAddrString();
        bool isLoopback = (ip == "127.0.0.1" || ip == "::1");
        DriverInterface driver = null;
        if (!secure) driver = new HTTP(accepted, false);
        version(SSL) { if (secure) driver = new HTTPS(accepted, false); }
        if (driver is null) { accepted.close(); return; }
        if (!pool.push(driver, ip, isLoopback)) {
          log(Level.Always, "Rate limit or capacity exceeded [%s]", ip);
          driver.closeConnection();
        }
      } catch(Exception e) { error("Unable to accept connection, Exception: %s", e.msg);
      } catch(Error e) { error("Unable to accept connection, Error: %s", e.msg); }
    }

    // Stop the pool and shutdown the server
    final void stop() { pool.stop(); socket.close(); version(SSL) { sslsocket.closeSSL(); } }

    // Returns a Duration object holding the server uptime
    final @property Duration uptime() const { return(Clock.currTime() - starttime); }

    // Hostname of the server
    final @property string hostname() { return(socket.hostName()); }
    version(SSL) {
      final @property string sslKey() { return(sslPath ~ ssl); }
      final @property string accountKey() { return(sslPath ~ account); }
    }

    @property bool alive() {
      if (atomicLoad(shutdownSignal)) return false;
      version(SSL) { return(socket.isAlive() && sslsocket.isAlive());
      } else { return(socket.isAlive()); }
    }

    final void run() {
      SysTime lastScan = Clock.currTime();
      while(alive) {
        try {
          accept(socket);
          version (SSL) { accept(sslsocket, true); }
          if (Msecs(lastScan) > 86_400_000) {
            pool.scan();
            version(SSL) { checkAndRenew(sslPath, sslKey, accountKey); }
            lastScan = Clock.currTime();
          }
        } catch(Exception e) { error("Unspecified top level server exception: %s", e.msg);
        } catch(Error e) { error("Unspecified top level server error: %s", e.msg); }
      }
      stop();
    }
}

void main(string[] args) {
  ushort port         = 80;
  int    backlog      = 100;
  int    verbose      = Level.Verbose;
  string wwwFolder    = "www/";
  string sslFolder    = ".ssl/";
  string sslKey       = "server.key";
  string accountKey   = "account.key";

  getopt(args, "port|p",      &port,         // Port to listen on
               "backlog|b",   &backlog,      // Backlog of clients supported
               "www",         &wwwFolder,    // Server www root folder
               "ssl",         &sslFolder,    // Location of SSL certificates
               "sslKey",      &sslKey,       // Server private key
               "accountKey",  &accountKey,   // Server Let's encrypt account key
               "verbose|v",   &verbose);     // Verbose level (via commandline)
  atomicStore(cv, verbose);
  synchronized(serverConfigMutex) { serverConfig = ServerConfig(wwwFolder ~ "server.config"); }
  registerExitHandler();

  auto server = new Server(port, backlog, wwwFolder, sslFolder, sslKey, accountKey);
  version (SSL) {
    loadSSL(server.sslPath, server.sslKey);                             // Load SSL certificates
    checkAndRenew(server.sslPath, server.sslKey, server.accountKey);    // checkAndRenew SSL certificates
  }
  return(server.run());
}

unittest {
  tag(Level.Always, "FILE", "%s", __FILE__);
  version(SSL) {
    tag(Level.Always, "TEST", "SSL support");
  }else{
    tag(Level.Always, "TEST", "No SSL support");
  }
}

