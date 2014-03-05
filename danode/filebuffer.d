/**
 * | <a href="index.html">Home</a>             | <a href="server.html">Server</a>              |
 *   <a href="client.html">Client</a>          | <a href="router.html">Router</a>              |
 *   <a href="cgi.html">CGI</a>                | <a href="filebuffer.html">File Buffer</a>     |
 *   <a href="structs.html">Structures</a>     | <a href="helper.html">Helper functions</a>    |
 *
 * License: Use freely for any purpose
 */
module danode.filebuffer;

import std.stdio, std.string, std.conv, std.datetime, std.file;
import danode.structs, danode.response, danode.client, danode.helper, danode.mimetypes, danode.httpstatus;

/***********************************
 * FileBuffer class
 */
class FileBuffer{
  /***********************************
   * Constructor: when verbose is true, debug is printed
   */
  this(bool verbose = false){ this.verbose = verbose; }

  /***********************************
   * Add bf under key path to the buffer
   */
  final void add(string path, BFile bf){ synchronized{
    bf.btime = now();
    bf.mime  = toMime(path);
    buffer[path] = bf;
  }}

  /***********************************
   * Get the BFile structure stored at path from buffer
   */
  final BFile get(string path){ synchronized{
    if(verbose) writefln("[BUFFER]   From buffer '%s'", path);
    return buffer[path];
  }}

  /***********************************
   * Does the buffer contain path
   */
  final bool has(string path){ synchronized{
    return inarr!(BFile,string)(path, buffer);
  }}

  /***********************************
   * Loads a file at path into a PayLoad structure
   */
  final PayLoad loadFile(in string path, int maxSize = 1*MBYTE){
    PayLoad content;
    if(exists(path) && isFile(path)){
      if(getSize(path) <= maxSize){ if(verbose) writefln("[BUFFER] Adding '%s'", path);
        void[] fcontent = fileread(path);
        BFile f = BFile(fcontent);        // Small files get buffered, return the content
        content = PayLoad(cast(string)(f.content));
        add(path, f);
        fcontent = null;
      }else{                              // Create a file payload for return;
        if(verbose) writefln("[BUFFER] Streaming '%s'", path);
        content = PayLoad(path, PayLoadType.FILE);
      }
    }
    return content;
  }
  
  /***********************************
   * Send file at path to client (either from buffer or directly from disk)
   */
  final void sendFile(ref Client client, string path){
    if(has(path) && !needUpdate(path)){
      BFile bf = get(path);
      client.setResponse(STATUS_OK, PayLoad(cast(string)bf.content), bf.mime, bf.btime, 120);
    }else{
      client.setResponse(STATUS_OK, loadFile(path), toMime(path), timeLastModified(path), 120);
    }
    client.sendResponse();
  }

  /***********************************
   * Number of buffered items
   */
  final @property size_t items(){return buffer.length; }

  /***********************************
   * Size of the buffer in MegaBytes
   */
  final @property double size(){
    long size = 0; 
    foreach(key; buffer.byKey()){ size += buffer[key].content.length; }
    return (cast(int)(cast(double)size/cast(double)MBYTE * 100)) / 100.0;
  }

  /***********************************
   * Does the current buffer for path needs to be update ?
   */
  final @property bool needUpdate(string path){
    if(timeLastModified(path) >= buffer[path].btime){ return true; } return false;
  }

  private:
    BFile[string]  buffer;
    bool           verbose = false;
}

