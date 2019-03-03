module danode.process;

import danode.imports;
import danode.functions : Msecs;
import danode.log : custom, warning, trace;
version(Posix) {
  import core.sys.posix.fcntl : fcntl, F_SETFL, O_NONBLOCK;
}

struct WaitResult {
  bool terminated;           // Is the process terminated
  int status;                // Exit status when terminated
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
    bool              completed = false;
    bool              removeInput = true;

    File              fStdIn;               /// Input file stream
    File              fStdOut;               /// Output file stream
    File              fStdErr;               /// Error file stream

    Pipe              pStdOut;              /// Output pipe
    Pipe              pStdErr;              /// Error pipe

    WaitResult        process;              /// Process try/wait results
    SysTime           starttime;            /// Time in ms since this process came alive
    SysTime           modified;             /// Time in ms since this process was modified
    long              maxtime;              /// Maximum time in ms before we kill the process

    Appender!(char[])  outbuffer;           /// Output appender buffer
    Appender!(char[])  errbuffer;           /// Error appender buffer

  public:
    this(string command, string inputfile, bool removeInput = true, long maxtime = 4500) {
      this.command = command;
      this.inputfile = inputfile;
      this.removeInput = removeInput;
      this.maxtime = maxtime;
      this.starttime = Clock.currTime();
      this.modified = Clock.currTime();
      this.outbuffer = appender!(char[])();
      this.errbuffer = appender!(char[])();
      super(&run);
    }

     // Output/Errors so far
    final @property const(char)[] output(ptrdiff_t from) const { 
      synchronized {
        if (errbuffer.data.length == 0 && from >= 0 && from <= outbuffer.data.length) {
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
      if (errbuffer.data.length == 0) { return(outbuffer.data.length); }
      return errbuffer.data.length; 
    }

    // Read from a pipe
    void readpipe(ref File fp, ref Appender!(char[]) buffer) {
      try {
        int ch;
        while ((ch = fgetc(fp.getFP())) != EOF && lastmodified < maxtime) { 
          modified = Clock.currTime(); 
          buffer.put(cast(char) ch);
        }  // Non blocking slurp of stdout
      } catch (Exception e) {
        warning("exception during readpipe command: %s", e.msg);
        fp.close();
      }
    }

    // Execute the process
    // check the input path, and create a pipe:StdIn to the input file
    // create 2 pipes for the external process stdout & stderr
    // execute the process and wait until maxtime has finished or the process returns
    // inputfile is removed when the run() returns succesfully, on error, it is kept
    final void run() {
      try {
        int  ch;
        if( ! exists(inputfile) ) {
          warning("no input path: %s", inputfile);
          this.process.terminated = true;
          this.completed = true;
          return;
        }
        fStdIn = File(inputfile, "r");
        pStdOut = pipe(); pStdErr = pipe();
        custom(1, "PROC", "command: %s < %s", command, inputfile);
        auto cpid = spawnShell(command, fStdIn, pStdOut.writeEnd, pStdErr.writeEnd, null);

        fStdOut = pStdOut.readEnd;
        if(!nonblocking(fStdOut) && fStdOut.isOpen()) custom(2, "WARN", "unable to create nonblocking stdout pipe for command");

        fStdErr = pStdErr.readEnd;
        if(!nonblocking(fStdErr) && fStdErr.isOpen()) custom(2, "WARN", "unable to create nonblocking error pipe for command");

        while (running && lastmodified < maxtime) {
          this.readpipe(fStdOut, outbuffer);  // Non blocking slurp of stdout
          this.readpipe(fStdErr, errbuffer);  // Non blocking slurp of stderr
          process = cast(WaitResult) tryWait(cpid);
          Thread.sleep(msecs(1));
        }
        if(!process.terminated){
          warning("command: %s < %s did not finish in time", command, inputfile); 
          kill(cpid, 9); 
          process = WaitResult(true, wait(cpid));
        }
        trace("command finished %d after %s msecs", status(), time());

        this.readpipe(fStdOut, outbuffer);  // Non blocking slurp of stdout
        this.readpipe(fStdErr, errbuffer);  // Non blocking slurp of stderr
        trace("All output processed after %s msecs", time());

        // Close the file handles
        fStdIn.close(); fStdOut.close(); fStdErr.close();

        trace("removing process input file %s ? %s", inputfile, removeInput);
        if(removeInput) remove(inputfile);

        this.completed = true;

      } catch(Exception e) {
        warning("process.d, exception: '%s'", e.msg);
      }
    }
}

unittest {
  custom(0, "FILE", "%s", __FILE__);
  auto p = new Process("rdmd www/localhost/dmd.d", "test/dmd.in", false);
  p.start();
  while(!p.finished){ Thread.sleep(msecs(5)); }
  custom(0, "TEST", "status of output: %s", p.status());
  custom(0, "TEST", "length of output: %s", p.length());
  custom(0, "TEST", "time of output: %s", p.time());
}

