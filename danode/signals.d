/** danode/signals.d - POSIX signal handling: SIGPIPE suppression & clean shutdown via SIGTERM, SIGINT
  * License: GPLv3 (https://github.com/DannyArends/DaNode) - Danny Arends **/
module danode.signals;

import danode.imports;

shared bool shutdownSignal = false;

version(Posix) {
  import core.sys.posix.sys.resource;
  import core.sys.posix.signal : signal, SIGPIPE, SIGTERM, SIGINT;
  import core.sys.posix.unistd : write;

  import danode.log : getVerbose, log, Level;

  extern(C) @nogc nothrow void handleSignal(int signal) {
    switch (signal) {
      case SIGPIPE:
        if(getVerbose() >= Level.Trace) write(2, cast(const(void*)) "[SIG]    Broken pipe caught, and ignored\n\0".ptr, 41);
        break;
     case SIGTERM, SIGINT:
        if(getVerbose() >= Level.Trace) write(2, cast(const(void*)) "[SIG]    SIGTERM/SIGINT\n\0".ptr, 24);
        atomicStore(shutdownSignal, true);
        break;
      default:
        if(getVerbose() >= Level.Trace) write(2, cast(const(void*)) "[SIG]    Caught\n\0".ptr, 16);
        break;
    }
  }
}

version(Windows) {
  import core.sys.windows.wincon : SetConsoleCtrlHandler, CTRL_C_EVENT, CTRL_BREAK_EVENT, CTRL_CLOSE_EVENT;
  import core.sys.windows.windef : BOOL, DWORD, TRUE, FALSE;

  extern(Windows) BOOL handleConsoleCtrl(DWORD ctrlType) nothrow {
    switch (ctrlType) {
      case CTRL_C_EVENT, CTRL_BREAK_EVENT, CTRL_CLOSE_EVENT: atomicStore(shutdownSignal, true); return TRUE;
      default: return FALSE;
    }
  }
}

void registerExitHandler(){
  version(Windows){ SetConsoleCtrlHandler(&handleConsoleCtrl, TRUE); }
  version(Posix) {
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
