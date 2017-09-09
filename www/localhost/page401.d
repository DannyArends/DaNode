#!rdmd -O
import std.stdio, std.compiler;
import std.string : format, indexOf, split, strip, toLower;
import api.danode;

void main(string[] args){
  setGET(args);
  writeln("HTTP/1.1 401 Page Not Found");
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
  writeln("   Page Not found !");
  writeln("  </body>");
  writeln("</html>");
}

