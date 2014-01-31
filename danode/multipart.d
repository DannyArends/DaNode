/**
 * | <a href="index.html">Home</a>             | <a href="server.html">Server</a>              |
 *   <a href="client.html">Client</a>          | <a href="router.html">Router</a>              |
 *   <a href="cgi.html">CGI</a>                | <a href="filebuffer.html">File Buffer</a>     |
 *   <a href="structs.html">Structures</a>     | <a href="helper.html">Helper functions</a>    |
 *
 * License: Use freely for any purpose
 */
module danode.multipart;

import std.stdio, std.string, std.socket, std.regex, std.uri, std.conv, std.array, std.file;
import danode.structs;

/***********************************
 * Write the file contents of a multipart request to disk
 */
long writeFile(in string path, in string data){
  auto ufp = new File(path, "wb");
  ufp.rawWrite(data);
  ufp.close();
  return(getSize(path));
}

/***********************************
 * Parse multipart request into File fp
 */
void saveMultiPart(File fp, ref string[] fns, in string path, in string part){
  debug writeln("Parsing a multipart item");
  string dir = path ~ UPLOADDIR;
  if(part.indexOf(MPDESCR) > 0){
    string left = part[(part.indexOf(MPDESCR)+MPDESCR.length)..$];
    string name = left[0 .. left.indexOf("\"")];
    left = left[(left.indexOf("\"") + 1) .. $];
    left = left[0 .. left.indexOf("--")];
    if(left.indexOf("filename") > 0){ // Its a file
      left = left[(left.indexOf("filename") + 10) .. $];
      if(left[0 .. left.indexOf("\"")] != ""){
        string fname = left[0 .. left.indexOf("\"")];  // Name of the file
        string fullpath = dir ~ fname;
        left = left[(left.indexOf("Content-Type:")) .. $];
        left = left[(left.indexOf("\n")+3) .. ($-2)];
        if(!exists(dir)) mkdirRecurse(dir);
        long fsize = writeFile(fullpath, left);
        fp.writefln("FILE=%s=%s%s", name, UPLOADDIR, fname);
        fns ~= fullpath;  // Add the full path, so the webserver will delete it in cleanup
        writefln("[MPART]  File '%s': %s upload to: %s [%s bytes]", name, fname, fullpath, fsize);
      }else{ fp.writefln("FILE=%s=ERROR", name); }
    }else{ fp.writefln("POST=%s=%s", name, encodeComponent(strip(chomp(left)))); }
  }
  debug writeln("Finished parsing a multipart item.");
}

