module danode.crypto.account;

import std.stdio, core.vararg, std.math, std.string, std.process, std.json, core.thread, std.array;
import danode.structs, danode.response, danode.client, danode.helper, danode.mimetypes, danode.httpstatus;
import danode.crypto.functions;

/***********************************
 * Crypto currency account structure
 */
struct Account{
  string          name             = "ANONYMOUS";         /// Name of the account
  real            balance          = 0.0;                 /// Current balance
  string[]        addresses        = [];                  /// Addresses belonging to this account
  Transaction[]   transactions     = [];                  /// Transctions done by the above addresses

  final bool hasAddress(string address){ foreach(a; addresses){ if(a == address) return true; } return false; }
  final int transactionIdx(string txid){ foreach(int i, t; transactions){ if(t.txid == txid) return i; } return -1; }

  final void updateAddresses(string daemon, bool verbose = true){
    auto exec = executeDaemon(daemon, "getaddressesbyaccount", name);
    if(exec.status != 0){ /* writeln("[DEBUG] No deamon: ", daemon); */ return; }
    auto addressesbyaccount = parseJSON(exec.output);
    int i = 0;
    foreach(JSONValue address; addressesbyaccount.array){
      if(!hasAddress(address.str)){ addresses ~= address.str; i++; }
    }
    if(verbose && i > 0) writefln("[INFO]   Updated %d addresses for %s", i, daemon);
  }

  final void updateTransactions(string daemon, bool verbose = true, uint from = 0, uint to = 5000, uint maxconfirmations = 100){
    auto exec = executeDaemon(daemon, "listtransactions", name, format("%d",to), format("%d", from));
    if(exec.status != 0){ /* writeln("[DEBUG] No deamon: ", daemon); */ return; }
    auto transactionsbyaccount = parseJSON(exec.output);
    int n = 0;
    int u = 0;
    foreach(JSONValue transaction; transactionsbyaccount.array){
      string txid = toS(transaction,"txid");
      int idx = transactionIdx(txid);
      if(idx < 0){
        transactions ~= Transaction(txid, toF(transaction,"amount"), toS(transaction,"address"), toN(transaction,"confirmations")); n++; 
      }else{
        if(transactions[idx].confirmations < maxconfirmations && transactions[idx].confirmations != toN(transaction,"confirmations")){
          transactions[idx].confirmations = toN(transaction,"confirmations"); u++;
        }
      }
    }
    if(verbose && (n > 0)) writefln("[INFO]   Transactions %s, account: %s, %d new, %d updated", daemon, name, n, u);
  }

  final string getTransactions(){
    auto str = appender!string("");
    foreach(int i, Transaction transaction; transactions){
      if(i > 0) str.put(", ");
      str.put(format("{\"txid\": \"%s\", \"amount\": %f, \"address\":\"%s\", \"confirmations\": %d}", transaction.txid, transaction.amount, transaction.address, transaction.confirmations));
    }
    return(str.data);
  }
}

