DaNode a small webserver written in the D programming language
--------------------------------------------------------------

master: [![Build Status](https://travis-ci.org/DannyArends/DaNode.svg?branch=master)](https://travis-ci.org/DannyArends/DaNode)

development: [![Build Status](https://travis-ci.org/DannyArends/DaNode.svg?branch=development)](https://travis-ci.org/DannyArends/DaNode)

##### STRUCTURE

The DaNode server is designed to handle multiple websites independent and simultaneously. 
The DaNode front-end routes incoming HTTP requests to the correct web folder. It allows 
for multiple index pages and executes scripts in other languages (PHP, Python, D and R). 
Results from CGI scripts monitored and parsed back into the DaNode web server, (e.g. 
possible header errors, infinite execution of scripts) and results are send to the 
requesting client via HTTP.

##### GETTING DaNode

Download and compile the webserver:

    git clone https://github.com/DannyArends/DaNode.git
    cd DaNode
    ./sh/compile

To start the webserver at a specific port type:

    ./danode/server -p 8080

Confirm that the webserver is running by going to: http://127.0.0.1:8080/

To compile the server with https support (binds to port 443), use the following command:

    ./sh/compile ssl

To start the web server at port 80, I use nohup and authbind. First, install nohup and 
authbind and configure authbind to allow connections to port 80 (and 443, when using the ssl
version), then start the webserver by running:

    ./sh/run

Confirm that the webserver is running by going to http://127.0.0.1/ and https://127.0.0.1/

##### EXAMPLE WEBSITES

See the [www/](www/) folder for a number of example web sites. After compiling the web 
server, run the web server and the [www/localhost/](www/localhost/) folder is available 
at http://localhost/ or http://127.0.0.1/ from the browser. For the other examples in 
the [www/](www/) folder you will have to update your hosts file.

##### CREATE A PHP ENABLED WEBSITE

To create a simple PHP enabled web site first download and install DaNode, the next 
step is to create a directory for the new website, by executing the following commands 
from the DaNode directory:

    mkdir www/domain.xxx
    touch www/domain.xxx/index.php

Add some php / html content to the index page, and create a web.config file:

    touch www/domain.xxx/web.config

Add the following configuration settings to the web.config file, if you want to use 
scripting languages such as PHP, you have to manually allow the execution of cgi file. 
Add the following lines in your web.cofig file to redirect to the index.php file, and 
allow the webserver to execute the php script, and redirect the incomming requests to 
the index.php page:

    allowcgi     = yes
    redirecturl  = index.php

###### UPDATE THE HOSTS FILE

If you do not own the domain you wish to host for, redirect the domain to your local 
IP address using the hosts file:

    sudo nano /etc/hosts

Then add the following lines to this hostfile using your favourite editor:

    127.0.0.1   domain.xxx
    127.0.0.1   www.domain.xxx

Save the file with these lines added, then open a browser and navigate to: 
http://www.domain.xxx, you should now see the content of your php / html file.


##### Languages with web API supported

     PHP, PYTHON, D, R

###### webAPI's overview

             GET   POST    COOKIES     SERVER    FILE     CONFIG
     PHP     V     V       V           V         V        V
     PYTHON  V     V
     D       V     V       V           V         V
     R       V     V                   V         V

For more information see: [api/README.md](api/README.md)

##### Advanced config options

  - WEBSITE-CONFIG
   - Sub-domain redirecting, such as http://www.test.nl to http://test.nl
   - Directory browsing
   - Custom index and error pages
   - Executing different languages and the API
   - Server overview page at http://127.0.0.1/

  - FILEBUFFER
   - Small files are buffered and served from memory
   - Stream large downloads using a flexible resizable buffer

LICENCE

(c) 2010-2014 Danny Arends

