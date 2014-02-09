module test.stress;
import std.stdio, std.string, std.socket, std.file, std.path, std.conv, std.getopt, std.array;
import std.datetime, std.uri, std.random, core.thread, std.concurrency, std.math, core.memory;
import danode.helper, danode.client, danode.structs, danode.math;

alias std.array.join j;

class HTTPTester : core.thread.Thread {
  this(uint tid, string[] urls, uint req, ushort port = 3000){
    this.tid  = tid;
    this.urls = urls;
    this.req  = req;
    this.port = port;
    super(&run);
  }
  
  void run(){
    string htmlGET, retCode;
    string[] spliturl;
    auto st = now();
    long[][string] times;
    auto rnd = Random(tid);
    TcpSocket handle;
    foreach(url;randomCover(urls,rnd)){
      spliturl = url.split("/");
      for(uint r = 0; r < req; r++){
        handle = new TcpSocket();
        try{
          auto stt = now();
          handle.connect(new InternetAddress(spliturl[0], port));
          if(spliturl.length==1) spliturl ~= "";
          htmlGET = format("GET /%s HTTP/1.1\r\nHost: %s\r\n\r\n",encode(j(spliturl[1..$],"/")), spliturl[0]);
          writefln("[ASK] T-%s %s%s", tid, spliturl[0], strsplit(htmlGET," ")[1]);
          handle.send(htmlGET);
          while((ret = handle.receive(buf)) > 0)
            data ~= buf[0..ret];
          times[url] ~= (now() - stt).total!"msecs";
          if(data && indexOf(to!string(data)," ") > 0) retCode = strsplit(to!string(data)," ")[1];
          writefln("[%s] T-%s %s%s", retCode, tid, spliturl[0], strsplit(htmlGET," ")[1]);
          data = null;
        }catch(SocketException ex){
          writefln("[500] T-%s Failed to connect to server (%s:%d)",tid, url, port);
        }
        if(handle) handle.close();
        delete handle;
        GC.collect();
        GC.minimize();
      }
    }
    writefln("Thread %s:%s finished after %s requests to %s urls [%s secs]",getpid(), tid, req, urls.length, (now() - st).total!"seconds");
    foreach(key, time; times)
      writefln("%s  %s %s msecs", al(key,30), time, mean(time));
  }
  
  private:
    string[] urls;
    size_t   ret;
    uint     req, tid;
    ushort   port;
    char     buf[1024];
    char[]   data;
}

void main(string[] args){
  uint     req  = 5;
  uint     work = 1;
  ushort   port = 80;
  getopt(args, "req|r", &req, "work|w", &work, "port|p", &port);
  string[] urls = ["127.0.0.1"];
  foreach(loc; dirEntries("www", SpanMode.breadth))
    urls ~= "www." ~ std.array.replace(loc[4..$], "\\", "/");
  writefln("Parsed %s urls, checking using %s workers", urls.length, work);
  for(uint w = 0; w < work; w++)
    (new HTTPTester(w, urls, req, port)).start();
}
