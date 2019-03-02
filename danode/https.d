module danode.https;

version(SSL) {
  import deimos.openssl.ssl;
  import deimos.openssl.err;

  import danode.imports;
  import danode.functions : Msecs;
  import danode.response : Response;
  import danode.log : NORMAL, INFO, DEBUG;
  import danode.interfaces : DriverInterface;
  import danode.log : custom, warning, error;
  import danode.ssl;

  class HTTPS : DriverInterface {
    private:
      SSL* ssl = null;

    public:
      this(Socket socket, bool blocking = false) {
        custom(3, "HTTPS", "HTTPS constructor");
        this.socket = socket;
        this.blocking = blocking;
        this.systime = Clock.currTime(); // Time in ms since this process came alive
        this.modtime = Clock.currTime(); // Time in ms since this process was modified
      }

      // Perform the SSL handshake
      bool performHandshake() {
        custom(2, "HTTPS", "performing handshake");
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
        custom(2, "HTTPS", "handshake: %s", handshaked);
        return(handshaked);
      }

      // Open the connection by setting the socket to non blocking I/O, and registering the origin address
      override bool openConnection() { synchronized {
        custom(1, "HTTPS", "Opening HTTPS connection");
        if (ncontext > 0) {
          custom(1, "HTTPS", "Number of SSL contexts: %d", ncontext);
          try {
            if (this.socket is null) {
              error("SSL was not given a valid socket (null)");
              return(false);
            }

            custom(1, "HTTPS", "set the socket the blocking mode");
            this.socket.blocking = this.blocking;

            custom(1, "HTTPS", "creating a new ssl connection from context[0]");
            this.ssl = SSL_new(contexts[0].context);

            custom(1, "HTTPS", "setting the socket handle I/O to SSL* object");
            this.ssl.SSL_set_fd(socket.handle());

            custom(1, "HTTPS", "SSL_set_accept_state to server mode");
            SSL_set_accept_state(this.ssl);

            bool handshaked = performHandshake();
            if (!handshaked) {
              error("couldn't handshake SSL connection");
              return(false);
            }
          } catch (Exception e) {
            error("couldn't open SSL connection : %s", e.msg);
            return(false);
          }
          try {
            if (this.socket !is null) {
              this.address = this.socket.remoteAddress();
            }
          } catch (Exception e) {
            warning("unable to resolve requesting origin: %s", e.msg);
          }
          custom(1, "HTTPS", "HTTPS connection opened");
          return(true);
        } else {
          error("HTTPS driver failed, reason: Server has no certificates loaded");
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
            warning("unable to close socket: %s", e.msg);
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
        if(socket is null) return -1;
        if(!socket.isAlive()) return -1;
        if(ssl is null) return -1;

        ptrdiff_t received;
        char[] tmpbuffer = new char[](maxsize);
        if ((received = SSL_read(ssl, cast(void*) tmpbuffer, cast(int)maxsize)) > 0) {
          inbuffer.put(tmpbuffer[0 .. received]); modtime = Clock.currTime();
        }
        if(received > 0) custom(3, "HTTPS", "received %d bytes of data", received);
        return(inbuffer.data.length);
      } }

      // Send upto maxsize bytes from the response to the client
      override void send(ref Response response, Socket socket, ptrdiff_t maxsize = 4096){ synchronized {
        if(socket is null) return;
        if(!socket.isAlive()) return;
        if(ssl is null) return;

        auto slice = response.bytes(maxsize);
        ptrdiff_t send = SSL_write(ssl, cast(void*) slice, cast(int) slice.length);
        if(send >= 0) {
          if(send > 0) modtime = Clock.currTime();
          response.index += send; senddata[requests] += send;
          if(response.index >= response.length) response.completed = true;
        }
        if(send > 0) custom(3, "HTTPS", "send %d bytes of data", send);
      } }

      override bool isSecure() { return(true); }
  }

  unittest {
    custom(0, "FILE", "%s", __FILE__);
  }
}

