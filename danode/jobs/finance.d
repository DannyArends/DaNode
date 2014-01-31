module danode.jobs.finance;

import std.stdio, std.string, std.datetime, std.file, std.socket, std.conv;
import danode.structs, danode.helper;

string   DBdir = "www/financial.nl/db";
int[]    years = [2009, 2010, 2011, 2012];

string createUrl(string company="AMS:AGN", int year=2010){
  string s = "finance/historical?";
  s ~= format("q=%s&output=csv",company);
  s ~= format("&startdate=Jan+1+%s",year);
  s ~= format("&enddate=Dec+31+%s",year);
  return s;
}

struct Company{
  string            sname;
  string            exchange;
  string            name;
  double[5][string] data;
  @property tag(){ return sname ~ ":" ~ exchange; }
  @property file(int year){ return format("%s/%s_%s.txt", DBdir, tag, year); }
}

struct Prediction{
  double direction = 0.0;             // Predicted direction
  double stability = 0.0;             // Stability of prediction
}

struct Asset{
  string     tag    = "";             // Company tag
  double[2]  cost   = [0.0, 0.0];     // [Buy|Sell] Cost (Commission, etc)
  double[2]  price  = [0.0, 0.0];     // [Buy|Sell] Price
  int        nr     = 0;              // Nr of stocks purchased
  SysTime[2] date;                    // [Buy|Sell] Time
}

struct User{
  string  name;
  double  cash;
  Asset[] assets;
}

Company[] companies = 
  [
    Company("AAPL", "NASDAQ", "Apple Inc."),
    Company("GOOG", "NASDAQ", "Google Inc."),
    Company("INTC", "NASDAQ", "Intel Corporation")
  ];

User[] users;

void loadUsers(ref Job j){
  
}

void saveUsers(ref Job j){
  
}

void updateDB(ref Job j){
  string   url, outfile;
  size_t   size;
  char     buf[1024];

  if(!exists(DBdir)) mkdir(DBdir);

  foreach(year; years){
    foreach(company; companies){
      auto stt = now();
      outfile = company.file(year);
      if(!exists(outfile)){
        auto handle = new TcpSocket();
        try{
          handle.connect(new InternetAddress("www.google.com", 80));
          string req = format("GET /%s HTTP/1.0\r\n", createUrl(company.tag, year));
          req ~= "Host: www.google.com\r\n\r\n";
          handle.send(req);
          string data;
          while((size = handle.receive(buf)) > 0){
            data ~= buf[0..size];
          }
          string[] split = strsplit(data,"\r\n\r\n");
          if(split.length == 2){
            auto fp  = new File(outfile, "wt");
            fp.write(split[1]);
            fp.close();
            writefln("Data received for %s [%s]", company.name, year);
          }else{
            writefln("Malformed response received for %s [%s]", company.name, year);
          }
          writefln("Download %s - %s kb in %s msecs", company.name, data.length / 1024.0, Msecs(stt));
        }catch(SocketException ex){  writeln("Failed to connect to google finance data server"); }
        if(handle) handle.close();
      }else{  debug writefln("Company %s, year %s data is available", company.name, year); }
    }
  }
}

alias to!double tD;

void updatePredictions(ref Job j){
  auto stt = now();
  foreach(year; years){
    foreach(ref company; companies){
      string outfile = company.file(year);
      if(exists(outfile)){
        auto fp  = new File(outfile, "rt");
        string filecontent = to!string(std.file.read(outfile));
        fp.close();
        string[] lines = strsplit(filecontent,"\n");
        foreach(cnt, line; lines){
          string[] el = strsplit(line,",");
          if(cnt > 0 && el.length == 6){
            if(!inarr!(double[5], string)(el[0], company.data)){
              company.data[el[0]] = [ tD(el[1]),tD(el[2]),tD(el[3]),tD(el[4]),tD(el[5]) ];
              debug writeln(company.data[el[0]]);
            }else{ debug write("."); }
          }else{ debug writeln("Malformed line %s - %s", cnt, outfile); }
        }
        debug writefln("Company %s, year %s data is available", company.name, year);
      }else{
        writefln("Company %s, year %s data is not available", company.name, year);
      }
    }
  }
  writefln("(Re)Loaded company data in %s msecs", Msecs(stt));
  foreach(ref company; companies){

  }
}

void buySell(ref Job j){ }

