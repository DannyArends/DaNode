module danode.signals;

version(Posix) {
  import core.sys.posix.unistd : write;
  import core.sys.posix.signal : SIGPIPE;

  import danode.log : cverbose;

  extern(C) @nogc nothrow void handle_signal(int signal) {
    switch (signal) {
      case SIGPIPE:
        if(cverbose) write(2, cast(const(void*)) "[SIG]    Broken pipe caught, and ignored\n\0".ptr, 41);
        break;
      default:
        if(cverbose) write(2, cast(const(void*)) "[SIG]    Caught\n\0".ptr, 17);
        break;
    }
  }
}

