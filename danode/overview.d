module danode.overview;

import std.stdio, std.string, std.file, std.conv;
import danode.structs, danode.webconfig, danode.httpstatus, danode.filebuffer, danode.helper, danode.client;

void serverPage(Server server, Client client){
  string page;
  if(client.request.path == "/log"){
    page = server.summaryLog(client.request);
  }else if(client.request.path == "/web"){
    page = server.webLog(client.request);
  }else{
    page = logHeader("Server overview");
    with(server.stats){
      page ~= format("# of connections: %s<br>", nconnections);
      page ~= format("# of errors: %s too busy, %s timed out<br>", ntoobusy, ntimedout);
    }
    with(server.filebuffer){
      page ~= format("%s files buffered (%s Mb)<br>", items, size);
    }
  }
  client.setResponse(STATUS_OK, PayLoad(page));
  client.sendResponse();
}

string webLog(Server server, Request request){
  string page = logHeader("Web Log");
  foreach(root; getRootFolders()){
    string[string] config = server.getWebConfig(root); 
    page ~= format("<b>%s</b><br> - web.config: <font color='%s'>%s</font><br>%s<hr>",  root,
            (config.length > 1)? "green": "orange", (config.length > 1)? "found": "missing",
            summaryLog(server, request, root, "web"));
  }
  return page;
}

string logHeader(string name, int size = 4, bool links = true){
  return "<h"~to!string(size)~">" ~ name ~ "</h"~to!string(size)~">" ~ 
    "<a href='/'>Overview</a> || <a href='/log'>Log</a> || <a href='/web'>Web</a><br><br>"; 
}

string browseDir(Client client, string path){ with(client){
  string dircontent = format("<html><head><title>DaNode directory browser: %s</title></head><body>", path);
  dircontent ~= format("<h3>%s</h3><small><ul>",path);
  foreach (DirEntry e; dirEntries(path, SpanMode.shallow)){ 
    string fn = e.name[(path.length)..$]; // Short name
    dircontent ~= format("<li><a href='%s'>%s</a> - %.2f kB</li>", fn, fn, e.size/1024.0);
  }
  dircontent ~= format("</ul></small></body></html>");
  return dircontent;
}}

string summaryLog(Server server, Request request, string mfilter = "", string href = "log"){
  string page;
  if(mfilter != ""){ page ~= "- Summary Log " ~ mfilter ~ "<br>";  }else{
    page ~= logHeader("Summary Log " ~ mfilter);
  }
  page ~= "<small>";
  with(server.stats){
    foreach(k; log.byKey()){ int ksum = 0;
    foreach(l; log[k].byKey()){ int lsum = 0;
    foreach(m; log[k][l].byKey()){
      if(mfilter == "" || m.indexOf(mfilter) != -1){
        if(fromarr("k", request.GET) == k && fromarr("l",request.GET) == l){
          page ~= format("-%s-%s:%s [%s]<br>", k, l, m, log[k][l][m]);
        }
        ksum += log[k][l][m];
        lsum += log[k][l][m];
      }
    } // foreach(m)
    if(fromarr("k", request.GET) == k && lsum > 0)
      page ~= format("-%s-<a href='/%s?k=%s&l=%s'>%s</a> [%s]<br>",k,href,k,l,l,lsum);
    } // foreach(l)
    if(ksum > 0) page ~= format("-<a href='/%s?k=%s'>%s</a> [%s]<br>", href, k, k, ksum);
    } // foreach(k)
  }
  return page ~ "</small>";
}

