#!rdmd -O
import std.stdio, std.compiler;
import std.string : format, indexOf, split, strip, toLower;
import api.danode;

void main(string[] args){
  setGET(args);
  writeln("HTTP/1.1 200 OK");
  writeln("Content-Type: text/html; charset=utf-8");
  writeln("Connection: Keep-Alive");                        // This is wrong, to test if the server handles it correctly
  writefln("Server: %s", SERVER["SERVER_SOFTWARE"]);        // Keep-Alive MUST be specified with a Content-Length
  writefln("X-Powered-By: %s %s.%s\n", std.compiler.name, version_major, version_minor);

  writeln("<html>");
  writeln("  <head>");
  writeln("    <title>DaNode 'user defined' CGI (D) test script</title>");
  writeln("    <meta name='author' content='Danny Arends'>");
  writeln("  </head>");
  writeln("  <body>");
  writeln("    DaNode 'user defined' CGI (D) test script<br/>");
  writefln("    Server: <small>%s</small><br/>", SERVER);
  writefln("    Config: <small>%s</small><br/>", CONFIG);
  writeln("    <form action='dmd.d' method='post' enctype='multipart/form-data'>");
  writeln("    <table>");
  writefln("     <tr><td><a href='dmd.d?test=GET&do'>GET</a>:  </td><td> %s</td></tr>", GET);
  writefln("     <tr><td>POST: </td><td> %s</td></tr>", POST);
  writefln("     <tr><td>FILES: </td><td> %s</td></tr>", FILES);
  writeln("      <tr><td>Test: </td><td> <input name='test' type='text'></td></tr>");
  writeln("      <tr><td>File: </td><td> <input name='file' type='file'></td></tr>");
  writeln("      <tr><td>&nbsp;</td><td> <input type='submit' value='POST'></td></tr>");
  writeln("    </table>");
  writeln("    </form>");

  foreach(file; FILES){  // Handle any files that being uploaded
    string to = format("%s/%s", SERVER["DOCUMENT_ROOT"], FILES["file"].name);     // Choose a folder (here: root of the web folder) to save the uploads
    move_upload_file(FILES["file"].loc, to);                                      // Move the uploaded file to somewhere
    writefln("Uploaded: %s to %s", FILES["file"].loc, to);                        // Add a message to the HTML
  }

  writeln("  </body>");
  writeln("</html>");
}

