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
        this.starttime = Clock.currTime(); // Time in ms since this process came alive
        this.modtime = Clock.currTime(); // Time in ms since this process was modified
        if(verbose >= INFO) writeln("[HTTPS]  HTTPS driver initialized");
      }

      // Perform the SSL handshake
      bool performHandshake() {
        bool handshaked = false;
        int ret_accept, ret_error;
        while (!handshaked && Msecs(starttime) < 500) {
          ret_accept = SSL_accept(ssl);
          if (ret_accept == 1) {
            handshaked = true;
          } else {
            ret_error = ssl.checkForError(socket, ret_accept);
            if (ret_accept == 0) return(false);
            if (ret_error == SSL_ERROR_SSL) return(false);
            if (ret_error == SSL_ERROR_WANT_READ) Thread.sleep(5.msecs);
            if (ret_error == SSL_ERROR_WANT_WRITE) Thread.sleep(5.msecs);
          }
        }
        return(handshaked);
      }

      // Open the connection by setting the socket to non blocking I/O, and registering the origin address
      override bool openConnection() { synchronized {
        if(verbose >= INFO) writeln("[HTTPS]  Opening HTTPS connection");
        if (ncontext > 0) {
          if(verbose >= INFO) writefln("[HTTPS]  Number of SSL contexts: %d", ncontext);
          try {
            if (this.socket is null) {
              writefln("[ERROR]  SSL was not given a valid socket (null)");
              return(false);
            }

            if(verbose >= INFO) writefln("[HTTPS]  Set the socket the blocking mode");
            this.socket.blocking = this.blocking;

            if(verbose >= INFO) writeln("[HTTPS]  Creating a new ssl connection from context[0]");
            this.ssl = SSL_new(contexts[0].context); // writefln("[INFO]   SSL created, using standard certificate contexts[0].context");

            if(verbose >= INFO) writefln("[HTTPS]  Setting the socket handle I/O to SSL* object");
            this.ssl.SSL_set_fd(socket.handle());

            if(verbose >= INFO) writefln("[HTTPS]  SSL_set_accept_state");
            SSL_set_accept_state(this.ssl);

            bool handshaked = performHandshake();
            if (!handshaked) {
              writefln("[ERROR]  couldn't handshake SSL connection");
              return(false);
            }
          } catch (Exception e) {
            writefln("[ERROR]  couldn't open SSL connection : %s", e.msg);
            return(false);
          }
          try {
            if (this.socket !is null) {
              this.address = this.socket.remoteAddress();
            }
          } catch (Exception e) {
            if(verbose >= INFO) writefln("[WARN]   unable to resolve requesting origin: %s", e.msg);
          }
          if(verbose >= INFO) writeln("[HTTPS]  HTTPS connection opened");
          return(true);
        } else {
          writeln("[ERROR]  HTTPS driver failed, reason: Server has no certificates loaded");
        }
        return(false);
      } }

      // Close the connection, by shutting down the SSL and Socket object
      override void closeConnection() { synchronized {
        if (socket !is null) {
          try {
            if(socket.isAlive()) SSL_shutdown(ssl);
            socket.shutdown(SocketShutdown.BOTH);
            socket.close();
          } catch(Exception e) {
            if(verbose >= INFO) writefln("[WARN]   unable to close socket: %s", e.msg);
          }
        }
      } }

      // Is the connection alive ?, make sure we check for null
      override bool isAlive() { 
        if(socket !is null) return socket.isAlive();
        return false;
      }

      // Receive upto maxsize of bytes from the client into the input buffer
      override ptrdiff_t receive(Socket socket, ptrdiff_t maxsize = 4096){ synchronized {
        ptrdiff_t received;
        if(socket is null) return -1;
        if(!socket.isAlive()) return -1;
        if(ssl is null) return -1;
        char[] tmpbuffer = new char[](maxsize);
        if ((received = SSL_read(ssl, cast(void*) tmpbuffer, cast(int)maxsize)) > 0) {
          inbuffer.put(tmpbuffer[0 .. received]); modtime = Clock.currTime();
        }
        return(inbuffer.data.length);
      } }

      // Send upto maxsize bytes from the response to the client
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

  unittest {
    writefln("[FILE]   %s", __FILE__);
  }
}

