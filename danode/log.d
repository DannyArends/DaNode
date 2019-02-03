module danode.log;

import danode.imports;
import danode.interfaces : ClientInterface;
import danode.request : Request;
import danode.response : Response;
import danode.functions;
import danode.httpstatus;

extern(C) __gshared int cverbose;         // Verbose level of C-Code

immutable int NOTSET = -1, NORMAL = 0, INFO = 1, TRACE = 2, DEBUG = 3;

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
      cverbose = verbose;
      if (exists(requestLog) && overwrite) { // Request log
        writefln("[WARN]   overwriting log: %s", requestLog); 
        remove(requestLog);
      }
      RequestLogFp = File(requestLog, "a");

      if (exists(perfLog) && overwrite) { // Performance log
        writefln("[WARN]   overwriting log: %s", perfLog);
        remove(perfLog);
      }
      PerformanceLogFp = File(perfLog, "a");
    }

    @property @nogc int verbose(int verbose = NOTSET) const nothrow {
      if(verbose != NOTSET) {
        if(cverbose >= INFO) printf("[INFO]   Changing verbose level from %d to %d\n", cverbose, verbose);
        cverbose = verbose;
      }
      return(cverbose); 
    }

    void updatePerformanceStatistics(in ClientInterface cl, in Request rq, in Response rs) {
      string key = format("%s%s", rq.shorthost, rq.uripath);
      if(!statistics.has(key)) statistics[key] = Info();    // Unknown key, create new Info statistics object
      // Fill run-time statistics
      statistics[key].responses[rs.statuscode]++;
      statistics[key].starttimes.put(rq.starttime.toUnixTime());
      statistics[key].timings.put(Msecs(rq.starttime));
      statistics[key].keepalives.put(rs.keepalive);
      statistics[key].ips[((rq.track)? cl.ip : "DNT")]++;
      if (cverbose == TRACE) {
        PerformanceLogFp.writefln("%s = [%s] %s", key, rs.statuscode, statistics[key]);
        PerformanceLogFp.flush();
      }
    }

    void logRequest(in ClientInterface cl, in Request rq, in Response rs) {
      if (cverbose >= NORMAL) {
        RequestLogFp.writefln("[%d]    %s %s:%s %s%s %s %s", rs.statuscode, htmltime(), cl.ip, cl.port, rq.shorthost, rq.uri, Msecs(rq.starttime), rs.payload.length);
        RequestLogFp.flush();
      }
    }
}

