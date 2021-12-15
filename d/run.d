#!/usr/bin/env rdmd

/+
    run.d 
    a script to start DaNode Web Server

    Example of executing this D script: d/run.d
    
    Known flaws: 
    * Does not produce output while running Web Server. 
    * Does not continue to run after exiting shell.
+/

import std.stdio;
import std.process;

void main()
{
   std.process.execute(["./danode/server", "-p", "8080"]).output.writeln;
   
  // Alternate Syntax
  //std.process.executeShell("./danode/server -p 8080").output.writeln;

}
