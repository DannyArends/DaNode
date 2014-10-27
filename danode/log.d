module danode.log;

import std.array, std.stdio, std.string, std.conv, std.datetime, std.file, std.math;
import danode.client : Client;
import danode.request : Request;
import danode.response : Response;
import danode.functions;
import danode.httpstatus;

immutable int NOTSET = -1, NORMAL = 0, INFO = 1, DEBUG = 2;

struct Info {
  long[StatusCode]      responses;
  Appender!(long[])     starttimes;
  Appender!(long[])     timings;
  Appender!(bool[])     keepalives;
  long[string]          useragents;
  long[string]          ips;

  string toString(){ return(format("%s %s %s %s %s %s", responses, starttimes.data, timings.data, keepalives.data, useragents, ips)); }
}

class Log {
  private:
    string          path        = "requests.log";
    int             level       = NORMAL;
    File            requests;

  public:
    Info[string]    statistics;

    this(int verbose = NORMAL, bool overwrite = false){
      this.verbose = verbose;
      if(exists(path) && overwrite){
        writefln("[WARN]   overwriting log: %s", path); 
        remove(path);
      }
      requests = File(path, "a");
    }

    @property int verbose(int verbose = NOTSET) { if(verbose != NOTSET){ level = verbose; } return(level); }

    void write(Client cl, Response rs){
      Request   rq  = cl.lastrequest;
      string    key = format("%s%s", rq.shorthost, rq.uripath);

      if(!statistics.has(key)) statistics[key] = Info();    // Unknown key, create new Info statistics object

      // Fill run-time statistics
      statistics[key].responses[rs.statuscode]++;
      statistics[key].starttimes.put(rq.starttime.toUnixTime());
      statistics[key].timings.put(Msecs(rq.starttime));
      statistics[key].keepalives.put(rs.keepalive);
      statistics[key].ips[((rq.track)? cl.ip : "DNT")]++;

      // First to file
      if(level >= INFO)  requests.writefln("[%d]    %s %s:%s %s%s %s %s|%s", rs.statuscode, htmltime(), cl.ip, cl.port, rq.shorthost, rq.uri, Msecs(rq.starttime), rs.header.length, rs.payload.length);

      // Write the request to the requests file
      requests.flush();
    }
}


