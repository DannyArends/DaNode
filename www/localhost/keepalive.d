#!rdmd -O
import std.stdio, std.compiler;
import std.file : copy;
import std.array : Appender, appender;
import std.string : format, indexOf, split, strip, toLower;
import api.danode;

void main(string[] args){
  setGET(args);

  Appender!(char[]) htmlpage;  // Build the output before writing the headers

  htmlpage.put("<html>");
  htmlpage.put("  <head>");
  htmlpage.put("    <title>DaNode 'user defined' CGI (D) test script</title>");
  htmlpage.put("    <meta name='author' content='Danny Arends'>");
  htmlpage.put("  </head>");
  htmlpage.put("  <body>");
  htmlpage.put("    DaNode 'user defined' CGI (D) test script<br/>");
  htmlpage.put(format("    Server: <small>%s</small><br/>", SERVER));
  htmlpage.put(format("    Config: <small>%s</small><br/>", CONFIG));
  htmlpage.put("    <form action='keepalive.d' method='post' enctype='multipart/form-data'>");
  htmlpage.put("    <table>");
  htmlpage.put(format("     <tr><td><a href='keepalive.d?test=GET&do'>GET</a>:  </td><td> %s</td></tr>", GET));
  htmlpage.put(format("     <tr><td>POST: </td><td> %s</td></tr>", POST));
  htmlpage.put(format("     <tr><td>FILES: </td><td> %s</td></tr>", FILES));
  htmlpage.put("      <tr><td>Test: </td><td> <input name='test' type='text'></td></tr>");
  htmlpage.put("      <tr><td>File: </td><td> <input name='file' type='file'></td></tr>");
  htmlpage.put("      <tr><td>&nbsp;</td><td> <input type='submit' value='POST'></td></tr>");
  htmlpage.put("    </table>");
  htmlpage.put("    </form>");

  foreach(file; FILES){  // Handle any files that being uploaded
    string to = format("%s/%s", SERVER["DOCUMENT_ROOT"], FILES["file"].name);     // Choose a folder (here: root of the web folder) to save the uploads
    copy(FILES["file"].loc, to);                                                  // Copy the tmp upload file
    htmlpage.put(format("Uploaded: %s to %s", FILES["file"].loc, to));            // Add a message to the HTML
  }

  htmlpage.put("  </body>");
  htmlpage.put("</html>");

  // Write headers
  writeln("HTTP/1.1 200 OK");
  writeln("Content-Type: text/html; charset=utf-8");
  writeln("Connection: Keep-Alive");                        // If Keep-Alive
  writefln("Content-Length: %s", htmlpage.data.length);     //   Content.Length == Required, and should be correct !
  writefln("Server: %s", SERVER["SERVER_SOFTWARE"]);
  writefln("X-Powered-By: %s %s.%s\n", std.compiler.name, version_major, version_minor);

  // Write html output
  writeln(htmlpage.data);
}

