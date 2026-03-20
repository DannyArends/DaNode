/** danode/process.d - External process management: spawn, pipe, timeout, drain stdout/stderr
  * License: GPLv3 (https://github.com/DannyArends/DaNode) - Danny Arends **/
module danode.process;

import danode.imports;

import danode.functions : Msecs;
import danode.log : log, tag, error, Level;
import danode.webconfig : serverConfig;

struct WaitResult {
  bool terminated; /// Is the process terminated
  int status; /// Exit status when terminated
}

/* Set a filestream to nonblocking mode, if not Posix, use winbase.h */
bool nonblocking(ref File file) {
  version(Posix) {
    import core.sys.posix.fcntl : fcntl, F_SETFL, O_NONBLOCK;

    return(fcntl(fileno(file.getFP()), F_SETFL, O_NONBLOCK) != -1); 
  }else{
    import core.sys.windows.winbase;

    auto x = PIPE_NOWAIT;
    return(SetNamedPipeHandleState(file.windowsHandle(), &x, null, null) != 0);
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
    string[]          command;              /// Command to execute
    string            inputfile;            /// Path of input file
    string[string]    environ;
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
    this(string[] command, string inputfile, string[string] environ, bool removeInput = true) {
      this.command = command;
      this.inputfile = inputfile;
      this.environ = environ;
      this.removeInput = removeInput;
      this.maxtime = serverConfig.get("cgi_timeout", 4500L);
      this.starttime = Clock.currTime();
      this.modified = Clock.currTime();
      this.outbuffer = appender!(char[])();
      this.errbuffer = appender!(char[])();
      super(&run);
    }

     // Query Output/Errors from 'from' to the end, if the outbuffer contains any output this will be served
     // from is checked to be in-range of the outbuffer/errbuffer, if not an empty array is returned
    final @property const(char)[] output(ptrdiff_t from) const { synchronized {
      if (outbuffer.data.length > 0 && from >= 0 && from <= outbuffer.data.length) { return outbuffer.data[from .. $]; }
      if (from >= 0 && from <= errbuffer.data.length) { return errbuffer.data[from .. $]; }
      return [];
    } }

    // Runtime of the thread in mseconds
    final @property long time() const { synchronized { return(Msecs(starttime)); } }

    // Last time the process was modified (e.g. data on stdout/stderr)
    final @property long lastmodified() const { synchronized { return(Msecs(modified)); } }

    final @property bool timedOut() const { synchronized { return(Msecs(modified) >= maxtime); } }

    // Is the external process still running ?
    final @property bool running() const { synchronized { return(!process.terminated); } }

    // Did our internal thread finish processing the external process, etc ?
    final @property bool finished() const { synchronized { return(this.completed); } }

    // Returns the 'flattened' exit status of the external process 
    // ( -1 = non-0 exit code, 0 = succes, 1 = still running )
    final @property int status() const { synchronized {
      if (running) return 1;
      if (process.status == 0) return 0;
      return -1;
    } }

    // Length of output, if the outbuffer contains any data, the outbuffer will be prefered (errors are silenced)
    final @property long length() const { synchronized { 
      if (outbuffer.data.length > 0) { return(outbuffer.data.length); }
      return errbuffer.data.length; 
    } }

    // Read a character from a filestream and append it to buffer
    void readpipe(ref File file, ref Appender!(char[]) buffer) {
      try {
        char[4096] tmp;
        auto fp = file.getFP();
        ptrdiff_t n;
        while (lastmodified < maxtime && buffer.data.length < serverConfig.get("max_cgi_output", 10 * 1024 * 1024)) {
          n = fread(tmp.ptr, 1, tmp.sizeof, fp);
          if (n > 0) {
            modified = Clock.currTime();
            buffer.put(tmp[0 .. n]);
          } else {
            break;
          }
        }
      } catch (Exception e) { error("Exception during readpipe command: %s", e); file.close();
      } catch (Error e) { error("Error during readpipe command: %s", e); file.close();
      }
    }

    // Drain both stdout & stderr
    void drainPipes() { readpipe(fStdOut, outbuffer); readpipe(fStdErr, errbuffer); }

    @property void notifyovertime() { maxtime = -1; }

    // Execute the process
    // check the input path, and create a pipe:StdIn to the input file
    // create 2 pipes for the external process stdout & stderr
    // execute the process and wait until maxtime has finished or the process returns
    // inputfile is removed when the run() returns succesfully, on error, it is kept
    final void run() {
      try {
        if( !exists(inputfile) ) {
          log(Level.Verbose, "no input path: %s", inputfile);
          this.process.terminated = true;
          this.completed = true;
          return;
        }
        fStdIn = File(inputfile, "r");
        pStdOut = pipe(); pStdErr = pipe();
        log(Level.Verbose, "command: %s < %s", command, inputfile);
        import std.process : Config;
        auto cpid = spawnProcess(command, fStdIn, pStdOut.writeEnd, pStdErr.writeEnd, environ, Config.none, environ.get("PWD", "."));

        fStdOut = pStdOut.readEnd;
        if(!nonblocking(fStdOut) && fStdOut.isOpen()) log(Level.Trace, "unable to create nonblocking stdout pipe for command");

        fStdErr = pStdErr.readEnd;
        if(!nonblocking(fStdErr) && fStdErr.isOpen()) log(Level.Trace, "unable to create nonblocking error pipe for command");

        while (running && lastmodified < maxtime) {
          drainPipes();
          process = cast(WaitResult) tryWait(cpid);
          Thread.sleep(msecs(1));
        }
        if (!process.terminated) {
          log(Level.Verbose, "command: %s < %s did not finish in time [%s msecs]", command, inputfile, time()); 
          killProcess(cpid, 9);
          process = WaitResult(true, wait(cpid));
        }
        log(Level.Verbose, "command finished %d after %s msecs", status(), time());
        drainPipes();

        log(Level.Trace, "Output %d & %d processed after %s msecs", outbuffer.data.length, errbuffer.data.length, time());
        if (errbuffer.data.length > 0) log(Level.Verbose, "stderr: %s", errbuffer.data);

        // Close the file handles
        fStdIn.close(); fStdOut.close(); fStdErr.close();

        log(Level.Trace, "removing process input file %s ? %s", inputfile, removeInput);
        if(removeInput) remove(inputfile);
      } catch(Exception e) { error("process.d, exception: '%s'", e.msg); }
      this.completed = true;
    }
}

unittest {
  tag(Level.Always, "FILE", "%s", __FILE__);

  string nulldev = "/dev/null";
  version(Windows) nulldev = "NUL";

  auto p = new Process(["rdmd", "www/localhost/sse.d"], nulldev, null, false);
  p.start();
  while(!p.finished){ Thread.sleep(msecs(5)); }
  assert(p.status() == 0, "process must exit 0");
  assert(p.length() > 0, "process must produce output");
  assert(p.time() > 0,   "process must have run time");
}

