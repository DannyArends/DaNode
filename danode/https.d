module danode.https;

version(SSL) {
  import std.datetime : Clock;
  import std.stdio : writeln, writefln, stdin;
  import std.socket : Socket;

  import deimos.openssl.ssl;
  import deimos.openssl.err;

  import danode.response : Response;
  import danode.log : NORMAL, INFO, DEBUG;
  import danode.interfaces : DriverInterface;
  import danode.ssl;

  class HTTPS : DriverInterface {
    private:
      SSL* ssl = null;

    public:
      this(Socket socket, bool blocking = false, int verbose = NORMAL) {
        this.socket = socket;
        this.blocking = blocking;
        cverbose = verbose;
        this.starttime = Clock.currTime(); /// Time in ms since this process came alive
        this.modtime = Clock.currTime(); /// Time in ms since this process was modified
        if(verbose >= INFO) writeln("[HTTPS]  HTTPS driver initialized");
      }

      override bool openConnection() { synchronized {
        writeln("[HTTPS]  Opening HTTPS connection");
        if(ncontext > 0) {
          writefln("[HTTPS]  Number of SSL contexts: %d", ncontext);
          try {
            if (this.socket is null) {
              writefln("[ERROR]  SSL Socket is null");
              return(false);
            }
            writeln("[HTTPS]  Creating SSL_new");
            this.ssl = SSL_new(contexts[0].context); // writefln("[INFO]   SSL created, using standard certificate contexts[0].context");
            writefln("[HTTPS]  initial SSL tunnel created");
            this.ssl.SSL_set_fd(socket.handle()); // writefln("[INFO]   Added socket handle");
            sslAssert(SSL_accept(this.ssl) != -1);
            this.socket.blocking = this.blocking;
          } catch(Exception e) {
            writefln("[ERROR]  Couldn't open SSL connection : %s", e.msg);
            return(false);
          }
          try {
            if (this.socket !is null) {
              this.address = this.socket.remoteAddress();
            }
          } catch(Exception e) {
            writefln("[WARN]   unable to resolve requesting origin: %s", e.msg);
          }
          writeln("[HTTPS]  HTTPS connection opened");
          return(true);
        } else {
          writeln("[ERROR]  HTTPS driver failed, reason: Server has no certificates loaded");
          socket.close();
        }
        return(false);
      } }

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
        if(ssl is null) return;
        ptrdiff_t send = SSL_write(ssl, cast(void*) slice, cast(int) slice.length);
        if(send >= 0) {
          response.index += send; modtime = Clock.currTime(); senddata[requests] += send;
          if(response.index >= response.length) response.completed = true;
        }
      } }

      override bool isSecure() { return(true); }
  }

}
