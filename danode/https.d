/** danode/https.d - HTTPS driver: SSL/TLS send/receive via OpenSSL ImportC bindings
  * License: GPLv3 (https://github.com/DannyArends/DaNode) - Danny Arends **/
module danode.https;

version(SSL) {
  import danode.imports;
  import danode.includes;

  import danode.response : Response;
  import danode.log : tag, log, error, Level;
  import danode.interfaces : DriverInterface;
  import danode.ssl : checkForError, contexts;
  import danode.webconfig : serverConfig;

  class HTTPS : DriverInterface {
    private:
      char[] pending;
      SSL* ssl = null;

    public:
      this(Socket socket) { super(socket); }

      // Perform the SSL handshake
      bool performHandshake() {
        log(Level.Trace, "Performing handshake");
        int rA, rE;
        while (starttime < serverConfig.get("handshake_timeout", 5000L)) {
          rA = SSL_accept(ssl);
          if (rA == 1) return(true);    // Success
          if (rA == 0) return(false);   // Controlled failure: Not retryable

          rE = ssl.checkForError(socket, rA);
          if (rE == SSL_ERROR_SSL) return(false);
          if (rE == SSL_ERROR_WANT_READ) Thread.sleep(5.msecs);
          if (rE == SSL_ERROR_WANT_WRITE) Thread.sleep(5.msecs);
        }
        log(Level.Trace, "Handshake timeout: %d msecs", starttime);
        return(false);
      }

      // Open the connection by setting the socket to non blocking I/O, and registering the origin address
      override bool openConnection(bool blocking = false) {
        log(Level.Verbose, "Opening HTTPS connection");
        if (contexts.length > 0) {
          log(Level.Trace, "Number of SSL contexts: %d", contexts.length);
          try {
            if (!socket) { error("SSL was not given a valid socket (null)"); return(false); }

            log(Level.Trace, "Set the socket the blocking mode");
            socket.blocking = blocking;

            log(Level.Trace, "Creating a new ssl connection from context[0]");
            ssl = SSL_new(contexts[0].context);

            log(Level.Trace, "Setting the socket handle I/O to SSL* object");
            ssl.SSL_set_fd(to!int(socket.handle()));

            log(Level.Trace, "SSL_set_accept_state to server mode");
            SSL_set_accept_state(ssl);

            if (!performHandshake()) { log(Level.Verbose, "couldn't handshake SSL connection"); return(false); }
          } catch (Exception e) { error("Couldn't open SSL connection : %s", e.msg); return(false);
          }
          try {
            address = socket.remoteAddress();
          } catch (Exception e) { error("Unable to resolve requesting origin: %s", e.msg); }
          log(Level.Verbose, "HTTPS connection opened");
          return(true);
        }
        error("HTTPS driver failed: 'Server has no certificates loaded'");
        return(false);
      }

      override bool socketReady() const { return socket !is null && socket.isAlive() && ssl !is null; }

      // Close the connection, by shutting down the SSL and Socket object
      override void closeConnection() {
        try {
          if (socketReady()) { SSL_shutdown(ssl); SSL_shutdown(ssl); }
        } catch(Exception e) { error("Exception during SSL shutdown: %s", e.msg); }
        closeSocket();
      }

      override long receiveData(ref char[] buffer) { return(SSL_read(ssl, cast(void*) buffer, cast(int)buffer.length)); }

      // Send upto maxsize bytes from the response to the client
      override void send(ref Response response, Socket socket, ptrdiff_t maxsize = 4096){
        if (!socketReady()) return;
        if (sISelect(true, 0) <= 0) return;
        // SSL requires retrying with exact same buffer on WANT_WRITE
        if (pending.length == 0) pending = response.bytes(maxsize).dup;
        if (pending.length == 0) return;
        ptrdiff_t send = SSL_write(ssl, cast(void*) pending.ptr, cast(int) pending.length);
        if (send > 0) {
          log(Level.Trace, "Send result=%d index=%d length=%d", send, response.index, response.length);
          touch();
          response.index += send;
          senddata[requests] += send;
          if(response.index >= response.length && response.canComplete) response.completed = true;
          pending = [];  // clear on success, fetch next chunk next call
        }
      }

      @nogc override bool isSecure() const nothrow { return(true); }
  }

  unittest {
    tag(Level.Always, "FILE", "%s", __FILE__);
  }
}

