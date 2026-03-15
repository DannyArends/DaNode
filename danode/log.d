module danode.log;

import danode.imports;

enum Level { Always = 0, Verbose = 1, Trace = 2 }

shared int cv = 0;

private __gshared File serverFp;
private __gshared File acmeFp;
private __gshared File requestFp;

shared static this() {
  requestFp = stdout;
  serverFp  = stdout;
  acmeFp    = stdout;
}

void initLogs(string dir = "logs/", int verbose) {
  atomicStore(cv, verbose);
  serverFp = File(dir ~ "server.log", "a");
  requestFp = File(dir ~ "request.log", "a");
  acmeFp = File(dir ~ "acme.log", "a");
}

private void logTo(A...)(ref File fp, string tag, const string fmt, auto ref A args) {
  auto line = format("[%s] %s", tag, format(fmt, args));
  fp.writeln(line); fp.flush();
  if (atomicLoad(cv) >= 0) stdout.writeln(line);
}

void log(A...)(Level lvl, const string fmt, auto ref A args) { if (atomicLoad(cv) >= lvl) logTo(serverFp, "SRV", fmt, args); }
void acme(A...)(Level lvl, const string fmt, auto ref A args) { if (atomicLoad(cv) >= lvl) logTo(acmeFp, "ACME", fmt, args); }
void tag(A...)(Level lvl, string tag, const string fmt, auto ref A args) { if (atomicLoad(cv) >= lvl) logTo(serverFp, tag, fmt, args); }
void req(A...)(string tag, const string fmt, auto ref A args) { logTo(requestFp, tag, fmt, args); }

void error(A...)(const string fmt, auto ref A args) {
  stderr.writeln(format("[ERROR] " ~ fmt, args)); stderr.flush();
  serverFp.logTo("ERROR", fmt, args);
}

void acmeError(A...)(const string fmt, auto ref A args) {
  stderr.writeln(format("[ERROR] " ~ fmt, args)); stderr.flush();
  acmeFp.logTo("ERROR", fmt, args);
}

void abort(in string s, int exitcode = -1) { error(s); exit(exitcode); }
void expect(A...)(bool cond, string msg, auto ref A args) { if (!cond) abort(format(msg, args)); }
