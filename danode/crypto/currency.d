module danode.crypto.currency;

import std.stdio, core.vararg, std.math, std.string, std.process, std.json, core.thread;
import danode.structs, danode.response, danode.client, danode.helper, danode.mimetypes, danode.httpstatus;
import danode.crypto.functions, danode.crypto.account;

/***********************************
 * Crypto currency structure
 */
struct Currency{
  string           name             = "The Coin";             /// Currency name
  string           code             = "coin";                 /// Currency code (should match: Cryptsy exchange code)
  string           daemon           = "coindaemond";          /// Name of the daemon
  long             blockcount       = 0;                      /// Block count
  real             difficulty       = 0.0;                    /// Current block discovery difficult
  long             hashpersec       = 0;                      /// Hashes calculated per seconds by the network
  Account[]        accounts         = [];                     /// Accounts belonging to this currency

  void init(){
    updateMiningInfo();           // Get the information from the daemons and cryptsy
    updateAccounts(false);        // Update all account information
  }

  final bool updateMiningInfo(){
    bool updated = false;
    auto exec = executeDaemon(daemon, "getmininginfo");
    if(exec.status != 0){ /* writeln("[DEBUG] No deamon: ", daemon); */ return false; }
    auto getinfo = parseJSON(exec.output);
    if(blockcount != toN(getinfo, "blocks")) updated = true;
    blockcount = toN(getinfo, "blocks");
    difficulty = toF(getinfo, "difficulty");
    hashpersec = toN(getinfo, "networkhashps");
    return(updated);
  }

  final real blocktime(){ if(hashpersec > 0){ return(difficulty * pow(2.0, 32.0) / (hashpersec/1024) / 1000); }else{ return -1; } }
  final bool hasAccount(string name){ foreach(a; accounts){ if(a.name == name) return true; } return false; }
  final int  accountIdx(string name){ foreach(int i, a; accounts){ if(a.name == name) return i; } return -1; }

  final void updateAccounts(bool verbose = true){
    auto exec = executeDaemon(daemon, "listaccounts");
    if(exec.status != 0){ /* writeln("[DEBUG] No deamon: ", daemon); */ return; }
    auto listaccounts = parseJSON(exec.output);
    foreach(string name; listaccounts.object.keys){
      int i = accountIdx(name);
      if(i < 0){
        accounts ~= Account(name, toF(listaccounts, name));
      }else{
        accounts[i].balance = toF(listaccounts, name);
      }
    }
    if(verbose) writefln("[INFO]   Created %d new accounts for %s", accounts.length, daemon);
    foreach(ref account; accounts){
      account.updateAddresses(daemon, verbose);
      account.updateTransactions(daemon, verbose);
    }
  }
}

Currency DOGECOIN = Currency("DogeCoin", "DOGE", "dogecoind");
Currency BITCOIN = Currency("Bitcoin", "BTC", "bitcoind");
Currency FEDORA = Currency("Fedoracoin", "TIPS", "fedoracoind");

