module danode.log;

import danode.imports;

enum Level { Always = 0, Verbose = 1, Trace = 2 }

shared int cv = 0;
private __gshared Mutex logM;

shared static this() { logM  = new Mutex(); }

private void logTo(A...)(ref File fp, string tag, const string fmt, auto ref A args) {
  synchronized(logM) { fp.writeln(format("[%s] %s", tag, format(fmt, args))); }
}

void log(A...)(Level lvl, const string fmt, auto ref A args) {
  if(atomicLoad(cv) >= lvl) stdout.logTo("LOG", fmt, args);
}
void tag(A...)(Level lvl, const string tag, const string fmt, auto ref A args) {
  if(atomicLoad(cv) >= lvl) stdout.logTo(tag, fmt, args);
}

void error(A...)(const string fmt, auto ref A args) { stderr.logTo("ERR", fmt, args); }
void acmeError(A...)(const string fmt, auto ref A args) { stdout.logTo("SSL", fmt, args); }

void abort(in string s, int exitcode = -1) { error(s); exit(exitcode); }
void expect(A...)(bool cond, string msg, auto ref A args) { if (!cond) abort(format(msg, args)); }
