module danode.crypto.functions;

import std.stdio, core.vararg, std.math, std.string, std.process, std.json, core.thread, std.uri, std.process, std.array;
import danode.structs, danode.response, danode.client, danode.helper, danode.mimetypes, danode.httpstatus;
import danode.crypto.currency, danode.crypto.account, danode.crypto.cryptsy, danode.crypto.daemon;

string[string] getGET(string[] args){
  string[string] GET;
  foreach(arg; args){ string[] s = arg.split("="); if(s.length > 1){ GET[decode(s[0])] = decode(s[1]); } }
  return(GET);
}

immutable string[] CRYPTSYmarkets = ["LTC", "XPM", "BTC"];
immutable string marketFmt = "\t{\"name\": \"%s\",\n\t\t \"volume\": %f,\n\t\t \"price\": \"%s\"}";
immutable string currencyFmt = "{\"blockcount\": %d,\n \"difficulty\": %f,\n \"hashpersec\": %d,\n \"accounts\": %s,\n \"markets\": [%s]\n}";
immutable string accountFmt = "\t{\"name\": \"%s\",\n\t \"balance\": %f,\n\t \"addresses\": %s,\n\t \"transactions\": %s\t}";
immutable string transactionFmt = "\t\t{\"txid\": \"%s\", \"amount\": %f, \"address\": \"%s\", \"confirmations\": %d}";

// TODO: 'Secure' these functions so they cannot bring down the web server
long   toN(JSONValue v, string x){ return(v.object[x].integer); }
real   toF(JSONValue v, string x){ return(v.object[x].floating); }
string toS(JSONValue v, string x){ return(v.object[x].str); }

ProcessOutput executeDaemon(string daemon, string query = "", ...){
  string[] cmd = [daemon, query];
  for (int i = 0; i < _arguments.length; i++){
    cmd ~= va_arg!(string)(_argptr);
  }
  auto coind = execute(cmd);
  return(ProcessOutput(coind.status, coind.output));
}

string CRYPTSY(ref CryptoDaemon daemon, string coincode, string marketcode, string versus){
  return(format(marketFmt, versus, daemon.getVolume(coincode, marketcode), daemon.getLastTradePrice(coincode, marketcode))); 
}

string JSON(ref CryptoDaemon daemon, Currency currency){
  auto marketJSON = appender!string("");
  foreach(int i, string x;  CRYPTSYmarkets){ if(i > 0) marketJSON.put(",\n\t");
    if(currency.code == "BTC"){ // Flip the markets to get BTC to LTC prices
      marketJSON.put(CRYPTSY(daemon, x, currency.code, x));
    }else{ marketJSON.put(CRYPTSY(daemon, currency.code, x, x)); }
  }
  return(format(currencyFmt, currency.blockcount, currency.difficulty, currency.hashpersec, JSON(currency.accounts), marketJSON.data)); 
}

string JSON(Account[] accounts){
  auto str = appender!string("[\n");
  foreach(int i, Account account; accounts){ if(i > 0){ str ~=",\n"; } str.put(JSON(account)); }
  str.put("]\n");
  return(str.data);
}

string JSON(Account account){ return(format(accountFmt, account.name, account.balance, JSON(account.addresses), JSON(account.transactions))); }

string JSON(string[] addresses){ return(format("[\"%s\"]", join(addresses, "\", \""))); }

string JSON(in Transaction[] transactions){
  if(transactions.length == 0) return "[]\n";
  auto str = appender!string("[\n");
  foreach(int i, transaction; transactions){ if(i > 0){ str.put(",\n"); } str.put(format(transactionFmt, transaction.txid, transaction.amount, transaction.address, transaction.confirmations)); }
  str.put("]\n");
  return(str.data);
}

