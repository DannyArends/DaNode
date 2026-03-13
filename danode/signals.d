module danode.signals;

version(Posix) {
  import core.sys.posix.unistd : write;
  import core.sys.posix.signal : SIGPIPE;

  import danode.imports;
  import danode.log : cverbose;

  extern(C) @nogc nothrow void handle_signal(int signal) {
    switch (signal) {
      case SIGPIPE:
        if(atomicLoad(cverbose) > 1) write(2, cast(const(void*)) "[SIG]    Broken pipe caught, and ignored\n\0".ptr, 41);
        break;
      default:
        if(atomicLoad(cverbose) > 1) write(2, cast(const(void*)) "[SIG]    Caught\n\0".ptr, 17);
        break;
    }
  }
}

