module danode.process;

import std.stdio : EOF, File, fgetc, write, writeln, writefln, ftell;
import std.file : exists, remove;
import std.string : empty;
import std.datetime : Clock, SysTime;
import std.array : Appender, appender;
import core.thread : Thread;
import std.process : Config, Pipe, pipe, spawnShell, tryWait, wait, kill;
import danode.functions : Msecs;
import std.c.linux.linux : fcntl, F_SETFL, O_NONBLOCK;
import core.stdc.stdio : fileno;
import danode.log : NORMAL, INFO, DEBUG;

struct WaitResult {
  bool terminated;           // Is the process terminated
  int status;                // Exit status when terminated
}

int readpipe(ref Pipe pipe){
  File fp = pipe.readEnd;
  try{
    if(fp.isOpen()){
      if(nonblocking(fp)) return(fgetc(fp.getFP()));
      writeln("[WARN]   unable to create nonblocking pipe for command");
    }
  }catch(Exception e){ writefln("[WARN]   Exception during readpipe command"); }
  return(EOF);
}

bool nonblocking(ref File file){
 return(fcntl(fileno(file.getFP()), F_SETFL, O_NONBLOCK) != -1); 
}

class Process : Thread {
  private:
    string            command;              /// Command to execute
    string            path;                 /// Path of input file
    int               verbose = NORMAL;

    File              pStdIn;               /// Input file stream
    Pipe              pStdOut;              /// Output pipe
    Pipe              pStdErr;              /// Error pipe

    WaitResult        process;              /// Process try/wait results
    SysTime           starttime;            /// Time in ms since this process came alive
    SysTime           modified;             /// Time in ms since this process was modified
    long              maxtime;              /// Maximum time in ms before we kill the process

    Appender!(char[])  outbuffer;           /// Output appender buffer
    Appender!(char[])  errbuffer;           /// Error appender buffer

  public:
    this(string command, string path, int verbose = NORMAL, long maxtime = 15000) {
      this.command    = command;
      this.path       = path;
      this.verbose    = verbose;
      this.maxtime    = maxtime;
      this.starttime  = Clock.currTime();
      this.modified   = Clock.currTime();
      this.outbuffer  = appender!(char[])();
      this.errbuffer  = appender!(char[])(['\n']);
      super(&run);
    }

    final @property char[]  output(long from) { synchronized { if(errbuffer.data.length == 1){ return(outbuffer.data[from .. $]); } return errbuffer.data[from .. $]; } }   // Output/Errors so far
    final @property long    time() const { synchronized { return(Msecs(starttime)); } }                                                                                     // Time so far
    final @property long    lastmodified() const { synchronized { return(Msecs(modified)); } }                                                                              // Last time modified
    final @property bool    running() const { synchronized { return(!process.terminated); } }                                                                               // Command still running ?
    final @property int     status() const { synchronized { return(process.status); } }                                                                               // Command still running ?
    final @property long    length() const { synchronized { if(errbuffer.data.length == 1){ return(outbuffer.data.length); } return errbuffer.data.length; } }              // Length of output/error
    final @property string  inputpath() const { synchronized { return path; } }

    final void run() {
      int  ch;
      if(exists(path)){
        pStdIn          = File(path, "r");
        pStdOut         = pipe();
        pStdErr         = pipe();
        if(verbose >= INFO) writefln("[INFO]   command: %s < %s", command, path);
        auto cpid       = spawnShell(command, pStdIn, pStdOut.writeEnd, pStdErr.writeEnd, null);
        while(running && lastmodified < maxtime){
          while((ch = readpipe(pStdOut)) != EOF){ modified = Clock.currTime(); outbuffer.put(cast(char)ch); }  // Non blocking slurp of stdout
          while((ch = readpipe(pStdErr)) != EOF){ modified = Clock.currTime(); errbuffer.put(cast(char)ch); }  // Non blocking slurp of stderr
          process = cast(WaitResult) tryWait(cpid);
          Thread.yield();
        }
        if(!process.terminated){
          writefln("[WARN]   command: %s < %s did not finish in time", command, path); 
          kill(cpid, 9); 
          process = WaitResult(true, wait(cpid));
        }
        while((ch = readpipe(pStdOut)) != EOF){ modified = Clock.currTime(); outbuffer.put(cast(char)ch); }  // Non blocking slurp of stdout
        while((ch = readpipe(pStdErr)) != EOF){ modified = Clock.currTime(); errbuffer.put(cast(char)ch); }  // Non blocking slurp of stderr
        pStdIn.close();
        if(verbose >= DEBUG) writefln("[INFO]   command finished after %s msecs", time());
        if(exists(path)){ if(verbose >= DEBUG) writefln("[INFO]   removing process input file %s", path);
          import std.file : remove;
          remove(path); 
        }
      }else{ writefln("[WARN]   no input path: %s", path); process.terminated = true; }
    }
}

