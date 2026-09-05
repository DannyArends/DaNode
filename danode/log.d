/** danode/log.d - Logging infrastructure: levels, tagged output, error reporting
  * License: GPLv3 (https://github.com/DannyArends/DaNode) - Danny Arends **/
module danode.log;

import danode.imports;

enum Level { Always = 0, Verbose = 1, Trace = 2 }

private shared Level cv = Level.Always;
private __gshared Mutex logMutex;
private Mutex logM() { return initOnce!logMutex(new Mutex()); }
private void logTo(A...)(ref File fp, string tag, const string fmt, auto ref A args) { synchronized(logM()) { fp.writefln("[%s] " ~ fmt, tag, args); } }

@nogc void set(int level) nothrow { try{ atomicStore(cv, cast(Level)(level)); }catch(Exception e){ } }
@nogc Level getVerbose() nothrow { return(atomicLoad(cv)); }

void log(A...)(Level lvl, const string fmt, auto ref A args) { tag(lvl, "LOG", fmt, args); }
void tag(A...)(Level lvl, const string tag, const string fmt, auto ref A args) { if(atomicLoad(cv) >= lvl) stdout.logTo(tag, fmt, args); }
void error(A...)(const string fmt, auto ref A args) { stderr.logTo("ERR", fmt, args); }
void abort(in string s, int exitcode = -1) { error(s); exit(exitcode); }
void expect(A...)(bool cond, string msg, auto ref A args) { if (!cond) abort(format(msg, args)); }

