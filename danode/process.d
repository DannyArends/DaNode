module danode.process;

import danode.imports;
import danode.functions : Msecs;
import danode.log : custom, warning, trace;
version(Posix) {
  import core.sys.posix.fcntl : fcntl, F_SETFL, O_NONBLOCK;
}

struct WaitResult {
  bool terminated; /// Is the process terminated
  int status; /// Exit status when terminated
}

/* Set a filestream to nonblocking mode, if not Posix, use winbase.h */
bool nonblocking(ref File file) {
  version(Posix) {
    return(fcntl(fileno(file.getFP()), F_SETFL, O_NONBLOCK) != -1); 
  }else{
    import core.sys.windows.winbase;
    auto x = PIPE_NOWAIT;
    auto res = SetNamedPipeHandleState(file.windowsHandle(), &x, null, null);
    return(res != 0);
  }
}

version(Posix) {
  alias kill killProcess;
}else{
  /* Windows hack: Spawn a new process to kill the still running process */
  void killProcess(Pid pid, uint signal) { executeShell(format("taskkill /F /T /PID %d", pid.processID)); }
}

/* The Process class provides external process communication via pipes, to the web language interpreter
   process runs as a thread inside the web server. Output of the running process should be queried via 
   the output() function. When there is any output on the stderr of the process (stored in errbuffer), 
   the error buffer will be served. only if the error buffer is empty, will outbuffer be served. */
class Process : Thread {
  private:
    string            command;              /// Command to execute
    string            inputfile;            /// Path of input file
    bool              completed = false;
    bool              removeInput = true;

    File              fStdIn;               /// Input file stream
    File              fStdOut;              /// Output file stream
    File              fStdErr;              /// Error file stream

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

     // Query Output/Errors from 'from' to the end, if the errbuffer contains any output this will be served
     // from is checked to be in-range of the err/outbuffer, if not an empty array is returned
    final @property const(char)[] output(ptrdiff_t from) const { 
      synchronized {
        if (outbuffer.data.length > 0 && from >= 0 && from <= outbuffer.data.length) {
          return outbuffer.data[from .. $];
        }
        if (from >= 0 && from <= errbuffer.data.length) {
          return errbuffer.data[from .. $]; 
        }
        return [];
      }
    }

    // Runtime of the thread in mseconds
    final @property long time() const {
      synchronized { return(Msecs(starttime)); }
    }

    // Last time the process was modified (e.g. data on stdout/stderr)
    final @property long lastmodified() const {
      synchronized { return(Msecs(modified)); }
    }

    // Is the external process still running ?
    final @property bool running() const { 
      synchronized { return(!process.terminated); }
    }

    // Did our internal thread finish processing the external process, etc ?
    final @property bool finished() const { 
      synchronized { return(this.completed); }
    }

    // Returns the 'flattened' exit status of the external process 
    // ( -1 = non-0 exit code, 0 = succes, 1 = still running )
    final @property int status() const { 
      synchronized { 
        if (running) return 1;
        if (process.status == 0) return 0;
        return -1;
      }
    }

    // Length of output, if the errbuffer contains any data, the errbuffer will be used
    final @property long length() const { synchronized { 
      if (outbuffer.data.length > 0) { return(outbuffer.data.length); }
      return errbuffer.data.length; 
    } }

    // Read a character from a filestream and append it to buffer
    // TODO: Use another function an read more bytes at the same time
    void readpipe (ref File file, ref Appender!(char[]) buffer) {
      try {
        int ch;
        auto fp = file.getFP();
        while ((ch = fgetc(fp)) != EOF && lastmodified < maxtime) { 
          modified = Clock.currTime(); 
          buffer.put(cast(char) ch);
        }
      } catch (Exception e) {
        warning("exception during readpipe command: %s", e.msg);
        file.close();
      }
    }
    
    @property void notifyovertime() { maxtime = -1; }

    
    // Execute the process
    // check the input path, and create a pipe:StdIn to the input file
    // create 2 pipes for the external process stdout & stderr
    // execute the process and wait until maxtime has finished or the process returns
    // inputfile is removed when the run() returns succesfully, on error, it is kept
    final void run() {
      try {
        int  ch;
        if( !exists(inputfile) ) {
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
        if (!process.terminated) {
          warning("command: %s < %s did not finish in time [%s msecs]", command, inputfile, time()); 
          killProcess(cpid, 9);
          process = WaitResult(true, wait(cpid));
        }
        trace("command finished %d after %s msecs", status(), time());

        this.readpipe(fStdOut, outbuffer);  // Non blocking slurp of stdout
        this.readpipe(fStdErr, errbuffer);  // Non blocking slurp of stderr
        trace("Output %d & %d processed after %s msecs", outbuffer.data.length, errbuffer.data.length, time());

        // Close the file handles
        fStdIn.close(); fStdOut.close(); fStdErr.close();

        trace("removing process input file %s ? %s", inputfile, removeInput);
        //if(removeInput) remove(inputfile);

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

