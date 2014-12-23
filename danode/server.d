module danode.server;

import std.c.stdlib : exit;
import core.thread : Thread;
import std.array : Appender, appender, chomp;
import std.datetime : Clock, dur, SysTime, Duration;
import std.socket : AddressFamily, InternetAddress, ProtocolType, Socket, SocketSet, SocketType, SocketOption, SocketOptionLevel;
import std.stdio : writefln, stdin;
import std.string : startsWith, format;
import danode.functions : Msecs;
import danode.client : Client;
import danode.router : Router;
import danode.log;
version(SSL){
  import danode.ssl;
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

  public:
    this(ushort port = 80, int backlog = 100, int verbose = NORMAL) {
      this.starttime  = Clock.currTime();
      this.router     = new Router(verbose);
      this.socket     = initialize(port, backlog);
      this.set        = new SocketSet(backlog + 1);
      super(&run);
    }

    final Socket initialize(ushort port = 80, int backlog = 200) {
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

    final int sISelect(int timeout = 10) {
      set.reset();
      set.add(socket);
      return Socket.select(set, null, null, dur!"msecs"(timeout));
    }

    final Client accept() {
      if(set.isSet(socket)){ try{
        Client client = new Client(router, socket.accept());
        client.start();
        return(client);
      }catch(Exception e){ writefln("[ERROR] unable to accept connection: %s", e.msg); } }
      return(null);
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
        if((select = sISelect()) > 0){ persistent.put(accept()); }
        foreach(Client client; clients){ if(client.running){ persistent.put(client); } }        // Add persistent clients
        clients = persistent.data;
      }
      socket.close();
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

