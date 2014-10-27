#!rdmd -O
import std.stdio, std.compiler;
import api.danode;

void main(string[] args){
  getGET(args);
  writeln("HTTP/1.1 200 OK");
  writeln("Content-Type: text/html; charset=utf-8");
  writefln("Server: %s", SERVER["SERVER_SOFTWARE"]);
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
  writeln("      <tr><td>Test: </td><td> <input name='test' type='text'></td></tr>");
  writeln("      <tr><td>File: </td><td> <input name='file' type='file'></td></tr>");
  writeln("      <tr><td>&nbsp;</td><td> <input type='submit' value='POST'></td></tr>");
  writeln("    </table>");
  writeln("    </form>");
  writeln("  </body>");
  writeln("</html>");
}

