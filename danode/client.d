/**
 * | <a href="index.html">Home</a>             | <a href="server.html">Server</a>              |
 *   <a href="client.html">Client</a>          | <a href="router.html">Router</a>              |
 *   <a href="cgi.html">CGI</a>                | <a href="filebuffer.html">File Buffer</a>     |
 *   <a href="structs.html">Structures</a>     | <a href="helper.html">Helper functions</a>    |
 *
 * License: Use freely for any purpose
 */
module danode.client;

import std.stdio, std.string, std.socket, std.conv, std.datetime, core.thread, core.memory;
import std.file, std.uri, std.process;
import core.sys.posix.signal;
version(SSL){
  import deimos.openssl.bio, danode.https;
}
import danode.structs, danode.httpstatus, danode.filebuffer, danode.router, danode.webconfig;
import danode.clientfunctions, danode.helper, danode.mimetypes, danode.request, danode.response;

/***********************************
 * Client class
 */
class Client : Thread {
  public:
    /***********************************
     * Construct the client using the specified server and use socket to send the response
     */
    this(Server server, Socket socket){
      _connected = now();
      _server    = server;
      _modified  = now();
      _socket    = socket;
      isDaemon(true);
      try{
        _address   = socket.remoteAddress();
      }catch(Exception e){ 
        debug writeln("[WARN] No remote address"); 
      }
      super(&run);
    }

    version(SSL){
      /***********************************
       * Construct the client using the specified server and use the SSL bio to send the response
       */
      this(Server server, BIO* bio){ 
        _connected = now();
        _server    = server;
        _modified  = now();
        _bio       = BIO_pop(bio);
        super(&run);
      }

      final BIO* getSSL(){ return(_bio); }
      final @property bool isSSL(){ return(_bio != null); } 
    }
    /***********************************
     * Main HTTP event loop
     */
    final void run(){ debug writeln("[CLIENT] Handle a request");
      signal(SIGPIPE, SIG_IGN);                                           // Ignore broken pipe errors
      version(SSL){ if(isSSL){
          if(!waitForHandShake(this, _bio)) completed = true;             // When SSL do a handshake
          if(!completed) this.setHost(_bio);                              // If handshake, who did we greet ?
      } }
      while(!completed){
        try{
          version(SSL){ if(isSSL && !hasdata) getSSLinput(this);  }       // In SSL the client reads data
          if(hasheader && hasdata){                                       // We have the header and the data
            if(_time) writefln("[TIME]   Parsed: %s", Msecs(_connected));
            _server.route(this, getWebConfig(_server, webroot));          // Route the request
            if(_time) writefln("[TIME]   Done: %s", Msecs(_connected));
            outputResponse(_response);                                    // Pretty print the response
            completed = true;
            break;
          }else if(hasheader){ checkData(this); }                         // Check header & Data
          if(isTimedOut(this))                                            // Check for timeout
            throw(new RException("Request timed out", STATUS_TIMEOUT));
          Sleep(msecs(2));
        }catch(RException e){
          outputResponse(e.response);                                     // Pretty print the HTTP errpr
          sendErrorResponse(e.response, e.msg);                           // Send the HTTP error
          completed = true;
          break;
        }catch(Exception e){
          writefln("[WARN]   %s %s %s (%s msecs)", e.msg, request.shortname, address, Msecs(connected));
          sendErrorResponse(STATUS_INTERNAL_ERROR, e.msg);
          completed = true;
          break;
        }catch(Error e){
          writefln("[ERROR]  %s %s %s (%s msecs)", e.msg, request.shortname, address, Msecs(connected));
          sendErrorResponse(STATUS_INTERNAL_ERROR, e.msg);
          completed = true;
          break;
        }
      }
      cleanup();
    }

    /***********************************
     * Pretty print the client & response after we're done
     */
    final void outputResponse(in Response response){
      writefln("%s - %s %s (%s msecs)", response.toString(this), _request.shortname, address, Msecs(connected));
    }

    /***********************************
     * Force a running CGI command to end
     */
    final void killCGI(){
      try{
        if(_cpid !is null){
          std.process.kill(_cpid, SIGKILL);
          writefln("[KILL]   %s %s (%s msecs)", request.shortname, address, Msecs(connected));
        }
      }catch(Exception e){ }
    }

    /***********************************
     * Clean the resources used by the client, and trigger a GC in this tread
     */
    final void cleanup(){
      try{
        killCGI();                                           // Shutdown any running CGI instance
        version(SSL){                                        // Free the SSL socket
          if(this.isSSL){ BIO_shutdown_wr(_bio); BIO_free_all(_bio); } 
        }
        _response.payload = null; _data = null;              // Set some of the used objects to null
        _request.path     = null; _request.headers = null;
        foreach(fn; request.files){                          // Remove any tmp files created
          if(exists(fn)) std.file.remove(fn); 
        }
        GC.collect();                                        // Run a GC collection to clean up the thread
        GC.minimize();
        if(_time) writefln("[TIME]   Cleaned: %s", Msecs(_connected));
      }catch(Error e){
        writefln("[ERROR]  onCleanup: %s", e.msg); 
      }
    }

    /***********************************
     * Send the response down the socket
     */
    final void sendResponse(bool error = false){
      slog("Response", to!string(_response.code), _request.shorturl);
      if(!_response.bodyonly) sendBytes(this, PayLoad(createResponseHeader(_response)));
      if(!_response.headeronly) sendBytes(this, _response.payload);
    }

    /***********************************
     * Set the response with payload
     */
    final void setResponse(Response r, PayLoad payload, in string mime = "text/html", in SysTime date = now(), uint maxage = 0){
      _response = r;
      _response.protocol= _request.protocol;
      _response.mime = mime;
      _response.payload = payload;
      _response.date = date;
      _response.maxage = maxage;
    }

    /***********************************
     * Send an nice HTML error response with msg
     */
    final void sendErrorResponse(Response r, in string msg, in string mime = "text/html", in SysTime date = now()){
      setResponse(r, PayLoad(_request.stdErr(r, msg)), mime);
      sendResponse(true);
      _completed = true;
    }

    /***********************************
     * Set the return to be body only
     */
    final void responseBodyOnly(){ _response.bodyonly = true; }

    /***********************************
     * Set the return to be header only
     */
    final void responseHeaderOnly(){ _response.headeronly = true; }

    /***********************************
     * Add a response header line key: value
     */
    final void addResponseHeader(string key, string value){ _response.headers[key]=value; }

    /***********************************
     * Server log an event
     */
    final void slog(string t, string c, string p){ _server.stats.log[t][c][p]++; }

    /***********************************
     * Adds incoming additional data and/or return the received data
     */
    final @property string data(string additional = ""){ synchronized(this){
      if(additional != ""){ _modified = now(); _data ~= additional; }
      return _data; 
    }}

    final @property SysTime isModified(){ _modified = now(); return _modified; }
    @property ref Socket socket(){ return _socket; }
    final @property ref Response response(){ return _response; }
    final @property ref Request request(){ return _request; }
    final @property SysTime connected() { return _connected; }
    final @property SysTime modified(){ return _modified; }
    final @property string webroot(){
      if(_webroot !is null) return _webroot;
      _webroot = getRootFolder(request.getHeader("Host"));
      return _webroot; }
    final @property bool completed(bool b = false){ if(b){_completed = b;} return(_completed); } 
    final @property bool hasdata(bool b = false){ if(b){_hasdata = b;} return(_hasdata); }
    final @property bool hasheader(){ synchronized(this){
      if((_data.indexOf("\r\n\r\n") > 0)){
        _hasheader = parseHeader(_request, _data.split("\r\n\r\n")[0]);
    } return(_hasheader); }}

    final void setPort(int port){ _port = port; }

    final @property int port(){
      try{
        if(_port != -1) return _port;
        if(_address !is null){ _port = to!int(_address.toPortString()); }else{ _port = -1; }
      }catch(Exception e){ _port = -1; }        // No port can happen
      return _port;
    }

    final void setIp(string ip){ _ip = ip; }

    final @property string ip(){
      try{
        if(_ip && _ip !is "x.x.x.x") return _ip;
        if(_address !is null){ _ip =_address.toAddrString(); }else{ _ip = "x.x.x.x"; }
      }catch(Exception e){ _ip = "x.x.x.x"; }        // No port can happen
      return _ip;
    }
    final @property string address(){ return format("%s:%d", ip(), port()); }
    final @property Pid cpid(Pid p = null){ if(p !is null){ _cpid = p; } return _cpid; }

  private:
    Request   _request = Request();       /// Private: request
    Response  _response = Response();     /// Private: response
    Socket    _socket;                    /// Private: socket
    version(SSL){
      BIO*      _bio;
    }
    Address   _address;                   /// Private  address field
    string    _ip,_webroot;
    int       _port = -1;
    SysTime   _connected, _modified;
    Pid       _cpid;
    bool      _hasheader = false, _hasdata = false, _completed = false;
    bool      _time = false;
    Server    _server;
    string    _data;
}

