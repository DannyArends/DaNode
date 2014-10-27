/**
 * | <a href="index.html">Home</a>             | <a href="server.html">Server</a>              |
 *   <a href="client.html">Client</a>          | <a href="router.html">Router</a>              |
 *   <a href="cgi.html">CGI</a>                | <a href="filebuffer.html">File Buffer</a>     |
 *   <a href="structs.html">Structures</a>     | <a href="helper.html">Helper functions</a>    |
 *
 * License: Use freely for any purpose
 */
module danode.keyboard;

import std.stdio : writefln;
import std.c.stdio, core.thread;

char getKeyBlock(){
  return(cast(char)fgetc(stdin));
}

class KeyHandler : Thread{
    this(){ super(&run); }

    void run(){
      printf( "[INFO]    Keyboard handler running.\n" );
      while(getKeyBlock() != 'q'){}
    }
}

