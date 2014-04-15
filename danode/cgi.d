/**
 * | <a href="index.html">Home</a>             | <a href="server.html">Server</a>              |
 *   <a href="client.html">Client</a>          | <a href="router.html">Router</a>              |
 *   <a href="cgi.html">CGI</a>                | <a href="filebuffer.html">File Buffer</a>     |
 *   <a href="structs.html">Structures</a>     | <a href="helper.html">Helper functions</a>    |
 *
 * License: Use freely for any purpose
 */
module danode.cgi;

import std.file, std.process, std.string, std.stdio, std.conv, std.datetime, std.uri, std.array, core.thread;
import std.random;
import danode.structs, danode.helper, danode.client, danode.clientfunctions;
import danode.request, danode.httpstatus, danode.response;

/***********************************
 * Read a string from pipe using the specified chunkSize
 */
string readPipe(ref Pipe pipe, in size_t chunkSize = BUFFERSIZE){
  string str;
  foreach(ubyte[] buffer; pipe.readEnd.byChunk(chunkSize)){ str ~= cast(string)buffer.idup; }
  return str;
}

/***********************************
 * Pass the GET parameters via a string to the commandline
 */
string createCmdParams(in string[string] GET){
  string str;
  foreach(k; GET.byKey()){ str ~= format(" \"%s=%s\"", k, GET[k]); }
  return str;
}

/***********************************
 * Parse the response of an CGI call to the underlying OS
 * There are three possible outcomes:
 *  - Header, and length = client.setResponse(OK, response) + BodyOnly
 *  - Header, no length -= Add content length + client.setResponse(OK, response) + BodyOnly
 *  - No header = client.setResponse(OK, response), Add header
 */
void parseResponse(ref Client client, string response , bool _verbose = true){
  client.setResponse(STATUS_OK, PayLoad(response));
  // Simple test to see if we have a valid HTTP header: Contains: HTTP/1.0 or HTTP/1.1
  if((response.indexOf("HTTP/1.0") == 0 ||  response.indexOf("HTTP/1.1") == 0 || response.indexOf("X-Powered-By:") >= 0)){
    if(response.length > 12) try{ client.response.code = to!uint(response[9 .. 12]); }catch(Exception e){}
    if(_verbose) writefln("[OK]     WebApp: '%s%s' - HEADER", client.webroot, client.request.path);
    client.response.bodyonly = true;                        // We have a header from the application
    if(response.indexOf("X-Powered-By:") >= 0){             // PHP Fast CGI output hack
     response = format("HTTP/1.0 200 OK\n%s", response);
    }
    if(response.indexOf("Content-Length:") < 0){            // If no content length is specified
      if(_verbose) writef("[WARN]   WebApp: '%s%s' - No Content-Length", client.webroot, client.request.path);
      string[] spl = strsplit(response,"\r\n\r\n");
      if(spl.length < 2) spl = strsplit(response,"\n\n");   // Malformed end of HTTP header, look for \n\n
      string msg = join(spl[1..$]);
      if(_verbose) writefln(", Best Guess: %s", msg.length);       // Add the guessed content length
      client.response.payload = PayLoad(format("%s\nContent-Length: %s\r\n\r\n%s", spl[0], msg.length, msg));
      spl = null;
    }
  } // No header is easy, just send the response as payload back, a header will be generated
  if(_verbose) writef("[OK]     WebApp: '%s%s' - NO HEADER, Generating one", client.webroot, client.request.path);
}

/***********************************
 * Execute a CGI call at path from client to the underlying OS
 */
void execute(ref Client client, string path, size_t chunkSize = BUFFERSIZE, bool _time = false){
  client.storeParams(client.webroot);
  if(_time) writefln("[TIME]  Parameters stored: %s", Msecs(client.connected));
  string interpreter     = whichInterpreter(path);
  string fullpath        = strrepl(format("%s%s", client.webroot, client.request.path),"//","/");
  client.request.cgicmd  = format("%s %s", interpreter, fullpath);
  client.request.cgicmd ~= createCmdParams(client.request.GET);
  auto pStdIn  = File(client.request.files[0], "r");
  writefln("[CGIEXEC] %s", client.request.files[0]);
  auto pStdOut = pipe(), pStdErr = pipe();
  if(_time) writefln("[TIME]  Spawning: %s", Msecs(client.connected));
  client.cpid  = spawnShell(client.request.cgicmd, pStdIn, pStdOut.writeEnd, pStdErr.writeEnd);
  auto process = tryWait(client.cpid);
  int sleep;
  while(!process.terminated){
    sleep   = uniform(2, 14);
    process = tryWait(client.cpid);
    client.isModified();
    client.isTimedOut(client.cpid);           // Throws its way out of trouble, while killing the thread
    Sleep(sleep.msecs);
    //writefln("[TIME]  Sleeping: %s %s", Msecs(client.connected), sleep.msecs);
  }
  if(_time) writefln("[TIME]  CGI execution done: %s", Msecs(client.connected));
  if(process.status != 0){
    string etxt = readPipe(pStdErr, chunkSize);
    etxt ~= readPipe(pStdOut, chunkSize);
    etxt = strrepl(format(errPageFmt, client.request.cgicmd, client.request.files[0], etxt), "\n", "<br>");
    throw(new RException(etxt, STATUS_INTERNAL_ERROR));
  }else{
    client.parseResponse(readPipe(pStdOut, chunkSize));
    if(interpreter.strsplit(" ")[0] == "sass") client.response.mime = "text/css";
  }
  client.sendResponse();
  if(_time) writefln("[TIME]  Response send: %s", Msecs(client.connected));
}

