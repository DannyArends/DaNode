  function getHTTP(i, link, callback){
    var xhr = new XMLHttpRequest();
    xhr.open("GET", link, true);
    xhr.onreadystatechange = function(){ if(xhr.readyState === 4){ callback(i, xhr.responseText); } };
    xhr.send(null);
  }

  Currency = function(name, symbol, daemon){
    this.name       = name;
    this.symbol     = symbol;
    this.daemon     = daemon,
    this.json,

    this.update = function(json){ 
      this.json = json;
      document.getElementById(this.name).innerHTML  = '<h4>' + this.name + ' (' + this.symbol + ')</h4><ul>';
      document.getElementById(this.name).innerHTML += '<li>Blockcount: '   + this.blockcount()      + '</li>';
      document.getElementById(this.name).innerHTML += '<li>Difficulty: '   + this.difficulty()      + '</li>';
      document.getElementById(this.name).innerHTML += '<li>Hashpersec: '   + this.hashpersec()      + '</li>';
      document.getElementById(this.name).innerHTML += '<li>Accounts: '     + this.accounts().length + '</li>';
      document.getElementById(this.name).innerHTML += '<li>Transactions: ' + this.nTransactions()   + '</li>';
      document.getElementById(this.name).innerHTML += this.marketinfo();
      document.getElementById(this.name).innerHTML += '</ul>';
    }

    this.marketinfo = function(){
      var markets = this.getmarkets();
      var html = '';
      for(var i = 0; i < markets.length; ++i){
        if(markets[i]['volume'] > 0) html += '<li>Price: ' + markets[i]['price'] + ' ' + markets[i]['name'] + '</li>';
      }
      return(html);
    }

    this.blockcount = function(){ if(this.json) return(this.json['blockcount']); },
    this.difficulty = function(){ if(this.json) return(this.json['difficulty']); },
    this.hashpersec = function(){ if(this.json) return(this.json['hashpersec']); },
    this.accounts   = function(){ if(this.json) return(this.json['accounts']); },
    this.getmarkets = function(){ if(this.json) return(this.json['markets']); },
    this.getaccount = function(name){ var accounts = this.accounts();
      for(var i = 0; i < accounts.length; ++i){ if(accounts[i]['name'] == name) return accounts[i]; }
    },
    this.nTransactions = function(){ var accounts = this.accounts(); var sum = 0;
      for(var i = 0; i < accounts.length; ++i){ sum += accounts[i]['transactions'].length; }
      return(sum);
    }
  }

  CryptoEngine = function(){
    this.currencies    = [new Currency('Bitcoin', 'BTC', 'bitcoind'), new Currency('DogeCoin','DOGE', 'dogecoind'), new Currency('Fedoracoin', 'TIPS', 'fedoracoind')],
    this.currentpage   = 'Index';
    this.lastUpdated   = 0,
    this.networkUpdate = 20000,

    this.update = function(){ this.page(this.currentpage);
      var now = new Date();
      if(now.getTime() > this.lastUpdated + this.networkUpdate){
        for(var i = 0; i < this.currencies.length; ++i){
          getHTTP(i, 'crypto?daemon=' + this.currencies[i].daemon, function(i, text){ cryptoengine.receive(i, text); });
        }
        this.lastUpdated = now.getTime();
        document.getElementById("lastupdated").innerHTML = now.toUTCString();
      }
    },

    this.page = function(name){ this.currentpage = name;
      document.getElementById('content').innerHTML = '<h2>' + name + '</h2>';
    },
    this.receive = function(i, text){ this.currencies[i].update(JSON.parse(text)); }
  }

