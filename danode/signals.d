/** danode/signals.d - POSIX signal handling: SIGPIPE suppression
  * License: GPLv3 (https://github.com/DannyArends/DaNode) - Danny Arends **/
module danode.signals;

__gshared bool shutdownSignal = false;

version(Posix) {
  import danode.imports;

  import core.sys.posix.sys.resource;
  import core.sys.posix.signal : signal, SIGPIPE, SIGTERM, SIGINT;
  import core.sys.posix.unistd : write;

  import danode.log : cv, log, Level;

  extern(C) @nogc nothrow void handleSignal(int signal) {
    switch (signal) {
      case SIGPIPE:
        if(atomicLoad(cv) > 1) write(2, cast(const(void*)) "[SIG]    Broken pipe caught, and ignored\n\0".ptr, 41);
        break;
     case SIGTERM, SIGINT:
        if(atomicLoad(cv) > 1) write(2, cast(const(void*)) "[SIG]    SIGTERM/SIGINT\n\0".ptr, 24);
        atomicStore(shutdownSignal, true);
        break;
      default:
        if(atomicLoad(cv) > 1) write(2, cast(const(void*)) "[SIG]    Caught\n\0".ptr, 16);
        break;
    }
  }

  void setupPosix() {
    rlimit rl;
    getrlimit(RLIMIT_NOFILE, &rl);
    rl.rlim_cur = rl.rlim_max;
    auto res = setrlimit(RLIMIT_NOFILE, &rl);
    log(Level.Always, "FD limit: %d [%d]", rl.rlim_cur, res);
    signal(SIGPIPE, &handleSignal);
    signal(SIGTERM, &handleSignal);
    signal(SIGINT,  &handleSignal);
  }
}

