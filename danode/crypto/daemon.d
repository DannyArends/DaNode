module danode.crypto.daemon;

import std.stdio, core.vararg, std.math, std.string, std.process, std.json, core.thread, std.datetime;
import danode.structs, danode.response, danode.client, danode.helper, danode.mimetypes, danode.httpstatus;
import danode.crypto.account, danode.crypto.currency, danode.crypto.cryptsy, danode.crypto.functions;

/***********************************
 * Generate a crypto web page, containing all information of a currency
 */
void cryptoPage(CryptoDaemon daemon, Client client){
  string page = format("{\"error\" : \"None or unknown daemon specified\"}");
  string[string] GET = getGET(strsplit(client.request.query,"&"));
  int idx = daemon.currencyIdx(fromarr("daemon", GET));
  if(idx >= 0) page = JSON(daemon, daemon.currencies[idx]);
  client.setResponse(STATUS_OK, PayLoad(page), "text/plain");
  client.sendResponse();
}

/***********************************
 * Crypto currency daemon class, listens to multiple coind and updates the internal state
 */
class CryptoDaemon : Thread {
  Currency[]       currencies;
  Market[]         markets;
  Server           server;
  int              updateCurrencies  = 5;        // 5 second updates to wallet daemons
  int              updateMarkets     = 120;      // 120 second updates to cryptsy
  SysTime          currenciesUpdated;            // Time since daemon update
  SysTime          marketUpdated;                // Time since market update

  this(Server server, Currency[] currencies){
    this.server = server;
    this.currencies = currencies;
    foreach(ref Currency currency; this.currencies){ currency.init(); }
    currenciesUpdated = now();
    this.updateMarketData(queryCryptsy("marketdatav2"), true);
    writefln("[INFO]   Running with %d currencies", currencies.length);
    marketUpdated = now();
    super(&run);
  }

  final int currencyIdx(string daemon){ foreach(int i, currency; currencies){ if(daemon == currency.daemon){ return i; } } return -1; }

  final void run(){
    writeln("[DEBUG]  Starting main loop");
    while(server.isRunning()){
      if(secs(currenciesUpdated) >= updateCurrencies){
        foreach(ref Currency currency; currencies){
          if(currency.updateMiningInfo()){ // writefln("[INFO]   New block %s: %d, %.1f", currency.daemon, currency.blockcount, currency.difficulty);
            currency.updateAccounts();
          }
        }
        currenciesUpdated = now();
      }
      if(secs(marketUpdated) >= updateMarkets){
        writeln("[INFO]   Updating Cryptsy market information");
        this.updateMarketData(queryCryptsy("marketdatav2"), true);
        marketUpdated = now();
      }
      Sleep(msecs(500));
    }
  }
}

