#!perl -w
use strict;
use api::danode;

print "HTTP/1.1 200 OK\n";
print "Content-Type: text/html; charset=utf-8\n\n";
print "<html>";
print "  <head>";
print "    <title>DaNode 'user defined' CGI (perl) test script</title>";
print "    <meta name='author' content='Danny Arends'>";
print "  </head>";
print "  <body>";
print "  DaNode 'user defined' CGI (perl) test script<br>";
print "    <form action='perl.pl' method='post' enctype='multipart/form-data'>";
print "    <table>";
print "     <tr><td><a href='perl.pl?test=GET'>GET</a>:</td><td> ".toS($_GET)."</td></tr>";
print "     <tr><td>POST:</td><td>".toS($_POST)."</td></tr>";
print "      <tr><td>Test:</td><td> <input name='test' type='text'></td></tr>";
print "      <tr><td>File:</td><td> <input name='file' type='file'></td></tr>";
print "      <tr><td>&nbsp;</td><td><input type='submit' value='POST'></td></tr>";
print "    </table>";
print "    </form>";
print "  </body>";
print "</html>";
