module danode.https;

version(SSL) {
  import deimos.openssl.ssl;
  import deimos.openssl.err;

  import danode.imports;
  import danode.functions : Msecs;
  import danode.response : Response;
  import danode.log : NORMAL, INFO, DEBUG;
  import danode.interfaces : DriverInterface;
  import danode.log : cverbose;
  import danode.ssl;

  class HTTPS : DriverInterface {
    private:
      SSL* ssl = null;

    public:
      this(Socket socket, bool blocking = false, int verbose = NORMAL) {
        this.socket = socket;
        this.blocking = blocking;
        this.starttime = Clock.currTime(); /// Time in ms since this process came alive
        this.modtime = Clock.currTime(); /// Time in ms since this process was modified
        if(verbose >= INFO) writeln("[HTTPS]  HTTPS driver initialized");
      }

      override bool openConnection() { synchronized {
        if(verbose >= INFO) writeln("[HTTPS]  Opening HTTPS connection");
        if(ncontext > 0) {
          if(verbose >= INFO) writefln("[HTTPS]  Number of SSL contexts: %d", ncontext);
          try {
            if (this.socket is null) {
              writefln("[ERROR]  SSL Socket is null");
              return(false);
            }
            if(verbose >= INFO) writeln("[HTTPS]  Creating SSL_new");
            this.ssl = SSL_new(contexts[0].context); // writefln("[INFO]   SSL created, using standard certificate contexts[0].context");
            if(verbose >= INFO) writefln("[HTTPS]  initial SSL tunnel created");
            this.ssl.SSL_set_fd(socket.handle());
            if(verbose >= INFO) writefln("[HTTPS]  Added socket handle");
            this.socket.blocking = this.blocking;
            if(verbose >= INFO) writefln("[HTTPS]  Socket to non-blocking");
            bool handshaked = false;
            int sslr;
            while(!handshaked && Msecs(starttime) < 100) {
              sslr = SSL_accept(this.ssl);
              if(sslr != -1) handshaked = true;
            }
            if(verbose >= INFO) writefln("[HTTPS]  SSL_accept returned %d after %d milliseconds", sslr, Msecs(starttime));
          } catch(Exception e) {
            writefln("[ERROR]  Couldn't open SSL connection : %s", e.msg);
            return(false);
          }
          try {
            if (this.socket !is null) {
              this.address = this.socket.remoteAddress();
            }
          } catch(Exception e) {
            if(verbose >= INFO) writefln("[WARN]   unable to resolve requesting origin: %s", e.msg);
          }
          if(verbose >= INFO) writeln("[HTTPS]  HTTPS connection opened");
          return(true);
        } else {
          writeln("[ERROR]  HTTPS driver failed, reason: Server has no certificates loaded");
          socket.close();
        }
        return(false);
      } }

      override void closeConnection() {
        if (socket !is null) {
          try {
            //if(socket.isAlive()) SSL_shutdown(ssl);
            socket.shutdown(SocketShutdown.BOTH);
            socket.close();
          } catch(Exception e) {
            if(verbose >= INFO) writefln("[WARN]   unable to close socket: %s", e.msg);
          }
        }
      }

      override bool isAlive() { 
        if(socket !is null) { return socket.isAlive(); }
        return false;
      }

      override ptrdiff_t receive(Socket socket, ptrdiff_t maxsize = 4096){ synchronized {
        ptrdiff_t received;
        if(ssl is null) return -1;
        char[] tmpbuffer = new char[](maxsize);
        if((received = SSL_read(ssl, cast(void*) tmpbuffer, cast(int)maxsize)) > 0) {
          inbuffer.put(tmpbuffer[0 .. received]); modtime = Clock.currTime();
        }
        return(inbuffer.data.length);
      } }

      override void send(ref Response response, Socket socket, ptrdiff_t maxsize = 4096){ synchronized {
        auto slice = response.bytes(maxsize);
        if(socket is null) return;
        if(!socket.isAlive()) return;
        if(ssl is null) return;
        ptrdiff_t send = SSL_write(ssl, cast(void*) slice, cast(int) slice.length);
        if(send >= 0) {
          if(send > 0) modtime = Clock.currTime();
          response.index += send; senddata[requests] += send;
          if(response.index >= response.length) response.completed = true;
        }
      } }

      override bool isSecure() { return(true); }
  }

}
