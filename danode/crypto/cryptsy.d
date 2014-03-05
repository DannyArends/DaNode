module danode.crypto.cryptsy;

import std.stdio, std.string, std.socket, std.file, std.path, std.conv, std.getopt, std.array, std.json;
import std.datetime, std.uri, std.random, core.thread, std.concurrency, std.math, core.memory;
import danode.structs, danode.response, danode.client, danode.helper, danode.mimetypes, danode.httpstatus;
import danode.crypto.functions, danode.crypto.daemon;

immutable string APIHOST = "pubapi.cryptsy.com";
immutable string APISTEM = "/api.php?method=";

/***********************************
 * A crypto market on cryptsy e.g. LTC/BTC or DOGE/BTC
 */
struct Market{
  long      marketid;           /// Cryptsy market id
  string    primarycode;        /// Primary currency code
  string    secondarycode;      /// Secondary currency code
  string    lasttradeprice;     /// Last trade price
  real      volume;             /// Trade volume
}

string queryCryptsy(string method = "marketdata", int marketid = -1){
  string    query, data;
  string[]  htmlsplit;
  TcpSocket handle;
  char      buf[1024];
  long      ret;

  query = format("%s%s", APISTEM, method);
  if(marketid > 0) query = format("%s&marketid=%d", query, marketid);

  handle = new TcpSocket();
  handle.connect(new InternetAddress(APIHOST, 80));
  handle.send(format("GET %s HTTP/1.0\r\nHost: %s\r\n\r\n", query, APIHOST));

  while((ret = handle.receive(buf)) > 0){ data ~= buf[0..ret]; }
  handle.close();

  htmlsplit = split(data,"\r\n\r\n");
  if(htmlsplit.length > 1) return(htmlsplit[1]);
  return("{\"error\" : \"Invalid return\"}");
}

int marketIdx(ref CryptoDaemon crypto, int marketid, bool verbose = true){
  foreach(int i, m; crypto.markets){ if(m.marketid == marketid) return i; } return -1;
}

real getVolume(ref CryptoDaemon crypto, string primarycode, string secondarycode = "BTC"){
  foreach(m; crypto.markets){ if(m.primarycode == primarycode && m.secondarycode == secondarycode) return m.volume; }
  return 0.0;
}

string getLastTradePrice(ref CryptoDaemon crypto, string primarycode, string secondarycode = "BTC"){
  foreach(m; crypto.markets){ if(m.primarycode == primarycode && m.secondarycode == secondarycode) return m.lasttradeprice; }
  return "0.0";
}

void updateMarketData(ref CryptoDaemon crypto, string json, bool verbose = true){
  auto marketdata = parseJSON(json);
  auto jsonmarkets = marketdata.object["return"].object["markets"].object;
  foreach(string name; jsonmarkets.keys){
    auto mi = jsonmarkets[name];
    int i = marketIdx(crypto, to!int(toS(mi,"marketid")));
    if(i >= 0){
      crypto.markets[i].lasttradeprice = toS(mi,"lasttradeprice");
      crypto.markets[i].volume = to!real(toS(mi,"volume"));
    }else{
      crypto.markets ~= Market(to!int(toS(mi,"marketid")), toS(mi,"primarycode"), toS(mi,"secondarycode"), toS(mi,"lasttradeprice"), to!real(toS(mi,"volume")));
    }
  }
//  if(verbose) writefln("[INFO]   Received information on %d markets\n%s", crypto.markets.length, crypto.markets);
}

