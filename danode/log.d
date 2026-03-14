module danode.log;

import danode.imports;
import danode.interfaces : ClientInterface;
import danode.request : Request;
import danode.response : Response;
import danode.functions;
import danode.statuscode : StatusCode;

shared int cverbose;

immutable int NOTSET = -1, NORMAL = 0, INFO = 1, TRACE = 2, DEBUG = 3;

/* Verbose level control of stdout */
void write(T)(const T fmt) { if(atomicLoad(cverbose) > 0) stdout.write(fmt); }

/* Write an warning string to stdout */
void warning(A...)(const string fmt, auto ref A args) { if(atomicLoad(cverbose) >= 0) writefln("[WARN]   " ~ fmt, args); }

/* Informational level of debug to stdout */
void info(A...)(const string fmt, auto ref A args) { if(atomicLoad(cverbose) >= 1) stdout.writefln("[INFO]   " ~ fmt, args); }

/* Informational level of debug to stdout */
void custom(A...)(const int lvl, const string pre, const string fmt, auto ref A args) {
  if(atomicLoad(cverbose) >= lvl) { stdout.writefln("[%s]%s" ~ fmt, pre, " ".replicate(max(1, 7 - pre.length)), args); }
}

/* Trace level debug to stdout */
void trace(A...)(const string fmt, auto ref A args) { if(atomicLoad(cverbose) >= 2) stdout.writefln("[TRACE]  " ~ fmt, args); }

/* Write an error string to stderr */
void error(A...)(const string fmt, auto ref A args) { stderr.writefln("[ERROR]  " ~ fmt, args); }

/* Abort with error code, default: -1 */
void abort(in string s, int exitcode = -1){
  error(s);
  exit(exitcode);
}

/* Expect condition cond, otherwise abort the process */
void expect(A...)(bool cond, string msg, auto ref A args) { if (!cond) abort(format(msg, args), -1); }

struct Info {
  long[StatusCode]      responses;
  Appender!(long[])     starttimes;
  Appender!(long[])     timings;
  Appender!(bool[])     keepalives;
  long[string]          useragents;
  long[string]          ips;

  void toString(scope void delegate(const(char)[]) sink, FormatSpec!char fmt) const {
    sink(format("%s %d %.2f", responses, timings.data[($-1)], mean(timings.data)));
  }
}

class Log {
  private:
    File RequestLogFp;
    File PerformanceLogFp;
    Info[string] statistics;

  public:
    this(int verbose = NORMAL, string requestLog = "request.log", string perfLog = "perf.log", bool overwrite = false) {
      atomicStore(cverbose, verbose);

      // Initialize the request log
      if (exists(requestLog) && overwrite) {
        warning("overwriting log: %s", requestLog); 
        remove(requestLog);
      }
      RequestLogFp = File(requestLog, "a");

      // Initialize the performance log
      if (exists(perfLog) && overwrite) {
        warning("overwriting log: %s", perfLog);
        remove(perfLog);
      }
      PerformanceLogFp = File(perfLog, "a");
    }

    // Set verbose level of the application
    @property @nogc int verbose(int verbose = NOTSET) const nothrow {
      if (verbose != NOTSET) {
        printf("[INFO]   changing verbose level from %d to %d\n", atomicLoad(cverbose), verbose);
        atomicStore(cverbose, verbose);
      }
      return(atomicLoad(cverbose));
    }

    // Update the performance statistics
    void updatePerformanceStatistics(in ClientInterface cl, in Request rq, in Response rs) {
      string key = format("%s%s", rq.shorthost, rq.uripath);
      if(!statistics.has(key)) statistics[key] = Info();    // Unknown key, create new Info statistics object
      // Fill run-time statistics
      statistics[key].responses[rs.statuscode]++;
      statistics[key].starttimes.put(rq.starttime.toUnixTime());
      statistics[key].timings.put(Msecs(rq.starttime));
      statistics[key].keepalives.put(rs.keepalive);
      statistics[key].ips[((rq.track)? cl.ip : "DNT")]++;
      if (atomicLoad(cverbose) == TRACE) {
        PerformanceLogFp.writefln("%s = [%s] %s", key, rs.statuscode, statistics[key]);
        PerformanceLogFp.flush();
      }
    }

    // Log the responses to the request
    void logRequest(in ClientInterface cl, in Request rq, in Response rs) {
      string uri;
      try { uri = decodeComponent(rq.uri); } catch (Exception e) { uri = rq.uri; }
      long bytes = rs.isRange ? (rs.rangeEnd - rs.rangeStart + 1) : rs.payload.length;
      string s = format("[%d]    %s %s:%s %s%s %s %s", rs.statuscode, htmltime(), cl.ip, cl.port, rq.shorthost, uri.replace("%", "%%"), Msecs(rq.starttime), bytes);
      RequestLogFp.writeln(s);
      custom(-1, "REQ", s);
      RequestLogFp.flush();
    }
}

