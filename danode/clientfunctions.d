/**
 * | <a href="index.html">Home</a>             | <a href="server.html">Server</a>              |
 *   <a href="client.html">Client</a>          | <a href="router.html">Router</a>              |
 *   <a href="cgi.html">CGI</a>                | <a href="filebuffer.html">File Buffer</a>     |
 *   <a href="structs.html">Structures</a>     | <a href="helper.html">Helper functions</a>    |
 *
 * License: Use freely for any purpose
 */
module danode.clientfunctions;

import std.stdio, std.string, std.conv, std.process, std.file, core.memory, std.datetime, std.uri, std.array;
version(SSL){
  import deimos.openssl.bio;
}
import danode.httpstatus, danode.client, danode.helper, danode.structs;
import danode.request, danode.filebuffer, danode.mimetypes, danode.response, danode.multipart;

/***********************************
 * Is the client still alive ?
 */
bool isTimedOut(Client client){
  return(secs(client.connected) >= TIMEOUT[CONNECTED] && secs(client.modified) >= TIMEOUT[MODIFIED]);
}

/***********************************
 * Is the client cgi still alive ?
 */
void isTimedOut(Client client, in Pid cpid){
  long t = secs(client.connected());
  if(t >= TIMEOUT[FORCGI]){
    throw(new RException("CGI request timed out", STATUS_TIMEOUT));
  }
}

/***********************************
 * Send bytes to the client
 */
void sendBytes(ref Client client, in PayLoad msg, in size_t READBUFFER = BUFFERSIZE){
  int nbytes = 0, sections = 0, send = 0;
  ubyte[] buffer, slice;
  File* fp;

  if(msg.type == PayLoadType.FILE){     // Open file and buffer
    fp = new File(msg,"rb"); 
    buffer = new ubyte[](READBUFFER);
  }
  while(nbytes < msg.length && !client.completed){
    if(msg.type == PayLoadType.STRING){
      slice = cast(ubyte[])msg[nbytes..$];
    }else if(msg.type == PayLoadType.FILE){
      fp.seek(nbytes);
      slice = fp.rawRead(buffer);
    }
    if(client.socket) send = to!int(client.socket.send(slice));
    version(SSL){
      if(client.isSSL){
        send = to!int(BIO_write(client.getSSL(), slice.ptr, to!int(slice.length)));
      }
    }

    if(send >= 0){
      nbytes += send;
      sections++;
      client.isModified();
    }
    if(client.isTimedOut()) throw(new RException("Request timed out (Sending)", STATUS_TIMEOUT));
  }
  if(msg.type == PayLoadType.FILE){    // Close file, buffer and slice
    buffer = null;
    slice = null;
    fp.close();
  }
  version(SSL){ if(client.isSSL){ BIO_flush(client.getSSL()); } }
  debug writefln("[SEND]   %s | %s bytes in %s sections", nbytes, msg.length, sections);
}

/***********************************
 * Send a timeout response to client
 */
void sendTimeOut(ref Client client){
  writef("[TIME]   %s (%s,%s): ", client.address, Msecs(client.connected), Msecs(client.modified));
  writefln("(H/D/C) - %s/%s/%s", client.hasheader, client.hasdata, client.completed);
  client.sendErrorResponse(STATUS_TIMEOUT, "Request timed out");
  client.completed=true;
  client.cleanup();
}

/***********************************
 * Send a moved permanently response to client
 */
void sendMovedPermanent(ref Client client, string to){
  client.setResponse(STATUS_MOVED_PERMANENTLY, PayLoad(""));
  client.addResponseHeader("location", to);
  client.responseHeaderOnly();
  client.sendResponse();
}

/***********************************
 * Check the data we received from client
 */
bool checkData(ref Client client, size_t MAXURILENGTH = 2*KBYTE){ with(client){
  debug writefln("[CLIENT] Parsing %d bytes of data", data.length);
  if(request.path.length > MAXURILENGTH)
    throw(new RException(format("Requested URI is too long"), STATUS_URI_TOO_LONG));
  if(request.method == "GET"){
    hasdata = true;
  }else if(request.method == "POST"){
    string contenttype = request.getHeader("Content-Type");
    if(contenttype.indexOf(MPHEADER) >= 0 || contenttype.indexOf(XFORMHEADER) >= 0){
      if(contenttype.indexOf(MPHEADER) >= 0)
        request.multipartid = strsplit(contenttype, "boundary=")[1];
      if(Msecs(modified) > 35){ hasdata = true; }
    }else{
      hasdata = true;
    }
  }else{
    throw(new RException(format("Method %s not allowed", request.method), STATUS_METHOD_NOT_ALLOWED));
  }
  return hasdata;
}}

/***********************************
 * Server parameters to insert into the response header to send to the client
 */
string writeServerParams(Client client, in string path){ with(client){
 /* writefln("%s\n\n", format(serverArgsFmt, SERVER_INFO, client.webroot, encodeComponent(request.dpp), encodeComponent(request.protocol), 
  encodeComponent(ip), port, encodeComponent(request.method), toLower(encodeComponent(request.url)), 
  encodeComponent(strrepl("./" ~ webroot ~ request.path,"//","/")), encodeComponent(request.getHeader("Accept")))); */

 /* return format(serverArgsFmt, SERVER_INFO, "", "", "", 
  "", "", "", "", 
 "", ""); */

  return format(serverArgsFmt, SERVER_INFO, client.webroot, toLower(encodeComponent(request.dpp)), encodeComponent(request.protocol), 
  encodeComponent(ip), port, encodeComponent(request.method), toLower(encodeComponent(request.dpp)), 
  encodeComponent(strrepl("./" ~ webroot ~ request.path,"//","/")), encodeComponent(request.getHeader("Accept")));
}}

string writeCookies(Client client){ with(client){
  debug writefln("[COOKIE]  Start parsing client %s", client.address());
  string str = "";
  if(inarr("Cookie", request.headers)){
    foreach(s; request.headers["Cookie"].strsplit("; ")){
      debug writefln("[COOKIE]  Found: %s = %s", client.address(), strip(chomp(s)));
      str ~= format("COOKIE=%s\n", strip(chomp(s)) );
    }
  }
  debug writefln("[COOKIE]  Done parsing %s", client.address());
  return str;
} }

/***********************************
 * Store post parameters
 */
void storeParams(ref Client client, in string path){ with(client){
  client.request.files = [freeFile(client.webroot,"cgi", client.port, ".in")];
  auto fp  = File(client.request.files[0], "w");
  debug writefln("[PARAMS]  Start parsing/writing  client %s", client.address());
  fp.writeln(writeServerParams(client, path));              // Write Server information
  fp.writeln(writeCookies(client));                         // Write Cookies

  if(request.method == "POST"){                             // Save POST data
    string reqdata = client.data();                         // Get the full request
    if(request.getHeader("Content-Type").indexOf(XFORMHEADER) >= 0){
      debug writeln("[POST]    XForm Header");
      reqdata = reqdata.strsplit("\r\n\r\n")[1];            // Safe ? Because we client.haveData
      foreach(s; reqdata.strsplit("&")){
        fp.writefln("POST=%s", strip(chomp(s)));
        writefln("[POST] Post Requested Header: %s", strip(chomp(s)));
      }
    }
    if(request.getHeader("Content-Type").indexOf(MPHEADER) >= 0){
      debug writeln("[POST]     Multipart Header");
      foreach(int i, part; strsplit(reqdata, request.multipartid)){
        if(i > 0) fp.saveMultiPart(client.request.files, path, part);
      }
    }
  }
  fp.close();
  debug writefln("[PARAMS]  Done %s", client.address());
}}

