module danode.server;

import std.c.stdlib : exit;
import core.thread : Thread;
import std.array : Appender, appender, chomp;
import std.datetime : Clock, dur, SysTime, Duration;
import std.socket : AddressFamily, InternetAddress, ProtocolType, Socket, SocketSet, SocketType, SocketOption, SocketOptionLevel;
import std.stdio : writefln, stdin;
import std.string : startsWith, format;
import danode.functions : Msecs;
import danode.client : Client, HTTP;
import danode.router : Router;
import danode.log;
version(SSL){
  import deimos.openssl.ssl;
  import danode.ssl : HTTPS, initSSL, closeSSL;
}
import std.getopt : getopt;

class Server : Thread {
  private:
    Socket            socket;
    SocketSet         set;
    Client[]          clients;
    bool              terminated;
    SysTime           starttime;
    Router            router;
    version(SSL){
      SSL_CTX*        context;
      Socket          sslsocket;
    }

  public:
    this(ushort port = 80, int backlog = 100, int verbose = NORMAL) {
      this.starttime  = Clock.currTime();
      this.router     = new Router(verbose);
      this.socket     = initialize(port, backlog);
      version(SSL){
        this.sslsocket = initialize(443, backlog);
        this.context   = initSSL();
        backlog = (backlog * 2) + 1;
      }
      backlog = backlog + 1;
      this.set        = new SocketSet(backlog);
      writefln("[SERVER] server created backlog: %d", backlog);
      super(&run);
    }

    Socket initialize(ushort port = 80, int backlog = 200) {
      Socket socket;
      try{
        socket = new Socket(AddressFamily.INET, SocketType.STREAM, ProtocolType.TCP);
        socket.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, true);
        socket.blocking = false;
        socket.bind(new InternetAddress(port));
        socket.listen(backlog);
        writefln("[INFO]   socket listening on port %s", port);
      }catch(Exception e){
        writefln("[ERROR]  unable to bind socket on port %s\n%s", port, e.msg);
        exit(-1);
      }
      return socket;
    }

    // Reset the socketset and add a server socket to listen to
    final int sISelect(Socket socket, int timeout = 10) {
      set.reset();
      set.add(socket);
      return Socket.select(set, null, null, dur!"msecs"(timeout));
    }

    // Create an unsecure connection to a client
    final Client accept(Socket socket) {
      if(set.isSet(socket)){ try{
        HTTP http = new HTTP(socket.accept());
        Client client = new Client(router, http.socket, http);
        client.start();
        return(client);
      }catch(Exception e){ writefln("[ERROR] unable to accept connection: %s", e.msg); } }
      return(null);
    }

    version(SSL){
      // Create a secure connection to a client
      final Client secure(Socket socket) {
        if(set.isSet(socket)){ try{
          HTTPS https = new HTTPS(socket.accept(), context);
          Client client = new Client(router, https.socket, https);
          client.start();
          return(client);
        }catch(Exception e){ writefln("[ERROR] unable to accept connection: %s", e.msg); } }
        return(null);
      }
    }

    final @property bool      running(){ synchronized { return(socket.isAlive() && isRunning() && !terminated); } }                                           // Is the server still running ?
    final @property void      stop(){ synchronized { foreach(ref Client client; clients){ client.stop(); } terminated = true;  } }                            // Stop the server
    final @property Duration  time() const { return(Clock.currTime() - starttime); }                                                                          // Time so far
    final @property void      info() { writefln("[INFO]   uptime %s\n[INFO]   # of connections: %d", time, connections); }                                    // Server information
    final @property long      connections() { long sum = 0; foreach(Client client; clients){ if(client.running){ sum++; } } return sum; }
    final @property int       verbose(string verbose = "") { return(router.verbose(verbose)); }

    final void run() {
      int select;
      Appender!(Client[]) persistent;
      while(running){
        persistent.clear();
        if((select = sISelect(socket)) > 0){ persistent.put(accept(socket)); }                  // Accept basic HTTP requests
        version(SSL){
          if((select = sISelect(sslsocket)) > 0){ persistent.put(secure(sslsocket)); }          // Accept SSL secure clients
        }
        foreach(Client client; clients){ if(client.running){ persistent.put(client); } }        // Add the backlog of persistent clients
        clients = persistent.data;
      }
      socket.close();
      closeSSL(sslsocket, context);
    }
}

void main(string[] args) {
  ushort port     = 80;
  int    backlog  = 100;
  int    verbose  = NORMAL;
  bool   keyoff   = false;
  getopt(args, "port|p",     &port,         // Port to listen on
               "backlog|b",  &backlog,      // Backlog of clients supported
               "keyoff|k",   &keyoff,       // Keyboard on or off
               "verbose|v",  &verbose);     // Verbose level (via commandline)

  auto server = new Server(port, backlog, verbose);
  server.start();
  string line;
  while(server.running){
    if(!keyoff){
      line = chomp(stdin.readln());
      if(line.startsWith("quit")) server.stop();
      if(line.startsWith("info")) server.info();
      if(line.startsWith("verbose")) server.verbose(line);
    }else{
      Thread.sleep(dur!"msecs"(10));
    }
  }
}

