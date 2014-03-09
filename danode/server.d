/**
 * | <a href="index.html">Home</a>             | <a href="server.html">Server</a>              |
 *   <a href="client.html">Client</a>          | <a href="router.html">Router</a>              |
 *   <a href="cgi.html">CGI</a>                | <a href="filebuffer.html">File Buffer</a>     |
 *   <a href="structs.html">Structures</a>     | <a href="helper.html">Helper functions</a>    |
 *
 * License: Use freely for any purpose
 */
module danode.server;

import std.stdio, std.getopt, std.socket,std.string, std.conv,std.datetime, std.c.stdlib, core.memory, std.random;
import danode.jobrunner, danode.httpstatus, danode.client, danode.clientfunctions, danode.cgi, std.zlib;
import danode.filebuffer, danode.helper, danode.structs, danode.response, danode.index;
import danode.https, danode.keyboard, danode.crypto.currency, danode.crypto.daemon;

/***********************************
 * Handle any incomming data from a client
 *
 * This function receives data from the client socket and adds it to the received data
 */
void handleincoming(ref Client client, bool verbose = false){
  char buf[KBYTE];
  size_t read = client.socket.receive(buf);
  if(read == Socket.ERROR){
    if(verbose) writefln("[WARN]   Connection: Unable to read %s", client.address);
    /// client.completed = true;
  }else if(read == 0){
    if(verbose) writefln("[WARN]   Connection: Noting to read %s", client.address);
    /// client.completed = true;
  }else{
    client.data(to!string(buf[0 .. read].dup));
    client.isModified();
    if(verbose) writefln("[INFO]   Received %s bytes from %s", read, client.address);
    debug writefln("[INFO]   %s", client.data());
  }
}

/***********************************
 * Setup a socket to listen on port for a backlog amount of clients
 */
void setup(ref Socket socket, in ushort port = 3000, in uint backlog = 10, bool exitOnError = true){
  try{
    socket = new Socket(AddressFamily.INET, SocketType.STREAM, ProtocolType.TCP);
    socket.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, true);
    socket.blocking = false;
    socket.bind(new InternetAddress(port));
    socket.listen(backlog);
    writefln("[INFO]   Socket is now listening on: %s [%s|%s]", port, backlog, MAX_CONNECTIONS);
  }catch(Exception e){
    writefln("[ERROR]  Unable to bind socket on port %s\n%s", port, e.msg);
    if(exitOnError) exit(-1);
  }
}

/***********************************
 * Setup the server to listen on port
 *
 * Initialization routine to initialize the server.
 */
void setup(ref Server server, in ushort port = 3000, in uint backlog = 100){
  version(SSL){
    server.SSL = initSSL();
    server.https = new HTTPS(server, server.SSL);
    server.https.start();
  }
  server.socket.setup(port, backlog);
  server.set = new SocketSet(MAX_CONNECTIONS + 1);     // +2 adds space for the socket
  server.filebuffer = new FileBuffer();
  server.keyboard = new KeyHandler();
  server.keyboard.start();
  server.cryptodaemon = new CryptoDaemon(server, [ BITCOIN, DOGECOIN, FEDORA ]);
  server.cryptodaemon.start();
}

/***********************************
 * Set the server to listen for new connections on socket
 */
void listen(ref Server server, Socket socket){
  if(server.set.isSet(socket)){                       // A new connection is requested
    try{
      Client client = new Client(server, socket.accept());      
      client.socket.blocking = false;
      if(server.clients.length < MAX_CONNECTIONS){
        debug writefln("[INFO]   New connection from %s", remoteInfo(client.socket));
        server.clients ~= client;
        client.start();
        server.stats.nconnections++;
      }else{
        server.stats.ntoobusy++;
        client.sendErrorResponse(STATUS_SERVICE_UNAVAILABLE, "Error: Too busy");
        client.cleanup();
        writefln("[503]    Rejected connection %s: Too many connections.", remoteInfo(client.socket));
        closeSocket(client.socket);
      }
    }catch(Exception e){ //No worries, its OK to error in non-blocking
      debug writefln("[ERROR] Unable to accept connection: %s", e);
    }
  }
}

/***********************************
 * Update server to handle an active select
 */
void handle(ref Server server, int select){
  Client[] persistent = [];
  for(size_t i = 0; i < server.clients.length; i++){
    Client each = server.clients[i];
    if(each.completed){
      debug writefln("[INFO]   Closing socket %d - %s", i, server.clients[i].address);
      try{
        closeSocket(each.socket);
      //  each.join();             // Join the thread, to make it finish
      }catch(Error e){
        writefln("[ERROR] Client %s Unable to close socket or join: %s", i, e.msg);
      }
      debug writefln("[INFO]   Closed %d - %s", i, server.clients[i].address);
    }else{                                    // Client has completed,close the socket
      // When the client socket is set, new data is available
      if(server.set.isSet(each.socket) && !each.hasdata) handleincoming(each);
      persistent ~= each;                     // Client not completed add it to the persistent list
    }
  }
  server.clients = persistent;
}

/***********************************
 * Call Select on the server waiting timeout number of miliseconds 
 *
 *  This functions fills the socketset and wraps the select function. 
 *  It returns the updated select status
 */
int sISelect(ref Server server, int timeout = 10){
  server.set.reset();
  server.set.add(server.socket);          // The socket listening on the requested port 80,8080
  foreach(Client each; server.clients){ 
    if(each.socket && each.socket.isAlive) server.set.add(each.socket); 
  }
  return Socket.select(server.set, null, null, dur!"msecs"(timeout));
}

/***********************************
 * Main entry point for the server
 */
void main(string[] args){
  int    select;
  Server server = Server();
  getopt(args, "port|p",    &server.port, 
               "backlog|b", &server.backlog, 
               "verbose|v", &server.verbose);

  // Set up the socket, client handling and optionally SSL
  server.setup(server.port, server.backlog);
  scope(exit){ closeSocket(server.socket); }


  while(server.isRunning()){
    try{
      if((select = sISelect(server)) > 0){
        server.listen(server.socket);
      }
      server.handle(select);
      stdout.flush();
    }catch (Exception e){ // Might be serious
      writefln("[ERROR]   Main Uncaught Error: %s", e.msg);
    }
    Sleep(msecs(1));
  }
  writeln("DONE");
}

