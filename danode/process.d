module danode.process;

import danode.imports;
import danode.functions : Msecs;
import danode.log : NORMAL, INFO, DEBUG;
version(Posix) {
  import core.sys.posix.fcntl : fcntl, F_SETFL, O_NONBLOCK;
}

struct WaitResult {
  bool terminated;           // Is the process terminated
  int status;                // Exit status when terminated
}

int readpipe(ref Pipe pipe, int verbose = NORMAL){
  File fp = pipe.readEnd;
  try{
    if(fp.isOpen()){
      if(!nonblocking(fp) && verbose >= DEBUG) writeln("[WARN]   unable to create nonblocking pipe for command");
      return(fgetc(fp.getFP()));
    }
  }catch(Exception e){
    writefln("[WARN]   Exception during readpipe command: %s", e.msg);
    fp.close();
  }
  return(EOF);
}

bool nonblocking(ref File file) {
  version(Posix) {
    return(fcntl(fileno(file.getFP()), F_SETFL, O_NONBLOCK) != -1); 
  }else{
    return(false);
  }
}

class Process : Thread {
  private:
    string            command;              /// Command to execute
    string            inputfile;            /// Path of input file
    int               verbose = NORMAL;
    bool              completed = false;

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
    this(string command, string inputfile, int verbose = NORMAL, long maxtime = 4500) {
      this.command    = command;
      this.inputfile  = inputfile;
      this.verbose    = verbose;
      this.maxtime    = maxtime;
      this.starttime  = Clock.currTime();
      this.modified   = Clock.currTime();
      this.outbuffer  = appender!(char[])();
      this.errbuffer  = appender!(char[])(['\n']);
      super(&run);
    }

     // Output/Errors so far
    final @property const(char)[] output(ptrdiff_t from) const { 
      synchronized {
        if (errbuffer.data.length == 1 && from >= 0 && from <= outbuffer.data.length) {
          return outbuffer.data[from .. $];
        }
        if(from >= 0 && from <= errbuffer.data.length){
          return errbuffer.data[from .. $]; 
        }
        return [];
      }
    }

    // Runtime so far
    final @property long time() const {
      synchronized { return(Msecs(starttime)); }
    }

    // Last time modified
    final @property long lastmodified() const {
      synchronized { return(Msecs(modified)); }
    }

    // Command still running ?
    final @property bool running() const { 
      synchronized { return(!process.terminated); }
    }

    // Command finished ?
    final @property bool finished() const { 
      synchronized { return(this.completed); }
    }

    // Exit status
    final @property int status() const {
      synchronized { return(process.status); }
    }

    // Length of output/error
    final @property long length() const { 
      synchronized { if(errbuffer.data.length == 1){ return(outbuffer.data.length); } return errbuffer.data.length; }
    }

    // Execute the process
    final void run() {
      try {
        int  ch;
        if( ! exists(inputfile) ) {
          writefln("[WARN]   no input path: %s", inputfile);
          this.process.terminated = true;
          this.completed = true;
          return;
        }
        pStdIn = File(inputfile, "r");
        pStdOut = pipe();
        pStdErr = pipe();
        if(verbose >= INFO) writefln("[INFO]   command: %s < %s", command, inputfile);
        auto cpid       = spawnShell(command, pStdIn, pStdOut.writeEnd, pStdErr.writeEnd, null);
        while(running && lastmodified < maxtime){
          while((ch = readpipe(pStdOut)) != EOF){ modified = Clock.currTime(); outbuffer.put(cast(char)ch); }  // Non blocking slurp of stdout
          while((ch = readpipe(pStdErr)) != EOF){ modified = Clock.currTime(); errbuffer.put(cast(char)ch); }  // Non blocking slurp of stderr
          process = cast(WaitResult) tryWait(cpid);
          Thread.yield();
        }
        if(!process.terminated){
          writefln("[WARN]   command: %s < %s did not finish in time", command, inputfile); 
          kill(cpid, 9); 
          process = WaitResult(true, wait(cpid));
        }
        while((ch = readpipe(pStdOut)) != EOF){ modified = Clock.currTime(); outbuffer.put(cast(char)ch); }  // Non blocking slurp of stdout
        while((ch = readpipe(pStdErr)) != EOF){ modified = Clock.currTime(); errbuffer.put(cast(char)ch); }  // Non blocking slurp of stderr
        pStdIn.close();
        if(verbose >= DEBUG) writefln("[DEBUG]  command finished %d after %s msecs", status(), time());
        if(verbose >= DEBUG) writefln("[DEBUG]  removing process input file %s", inputfile);
        remove(inputfile);
        this.completed = true;
      } catch(Exception e) {
        writefln("[WARN]   process.d, exception: '%s'", e.msg);
      }
    }
}

