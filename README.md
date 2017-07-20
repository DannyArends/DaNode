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

Download and compile the web server:

    git clone https://github.com/DannyArends/DaNode.git
    cd DaNode

Build DaNode using the dub package manager:

    dub build

or, compile using the compile script:

    ./sh/compile

Then, start the web server at a specific port (e.g. 8080) type:

    ./danode/server -p 8080

Confirm that the web server is running by going to: http://127.0.0.1:8080/

##### Enable HTTPs support

To compile the server with HTTPS support (binds to port 443), use dub and specify 
the _ssl_ configuration:

    dub build --config=ssl

or, compile using the compile script:

    ./sh/compile ssl

Start the web server on port 80 and 443:

    ./danode/server

After starting the server, confirm that the web server is running by going to http://127.0.0.1/ 
and https://127.0.0.1/ and make sure you have enough user rights to bind port 80 and 443, a server 
private key and domain certificates are required. I use Let's Encrypt to secure my own homepage. 
Setup instructions for Let's Encrypt can be found in the [sh/letsEncrypt](sh/letsEncrypt) file.

##### Troubleshooting: [ERROR]  unable to bind socket on port 80

Starting the server on port 80 and 443 might fail, when you do not have appropriate 
rights on the system. First check if you can start the server on another port:

    ./danode/server -p 8080

I use _nohup_ and _authbind_ to start the web server in deamon (background) mode at port 80, and 443 (SSL). 
First, install _nohup_ and _authbind_ via your package manager, configure _authbind_ to allow 
connections to port 80 (and 443, when using the ssl version), then start the webserver by running:

    ./sh/run

##### Command-line parameters

The content of the ./sh/run shell script:

    nohup authbind danode/server -k -b 100 -v 2 > server.log 2>&1 &

This starts the server, does not allow for keyboard command (-k) has a backlog (-b) 
of 100 simultaneous connection (per port), and produces more log output (-v 2)

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

If you do not own the domain name you want to host, use the /etc/hosts file to redirect 
requests from the domain name to your local IP address using the hosts file:

    sudo nano /etc/hosts

Then add the following lines to this hostfile using your favourite editor:

    127.0.0.1   domain.xxx
    127.0.0.1   www.domain.xxx

Save the file with these lines added, then open a browser and navigate to: 
http://www.domain.xxx, you should now see the content of your php / html file.

###### Supported API overview

Languages with supported APIs: PHP, PYTHON, D, R

See: [api/README.md](api/README.md)

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

##### Contributing

Want to contribute? Great! Contribute to DaNode by starring or forking on Github, 
and feel free to start an issue or sending a pull request.

Fell free to also post comments on commits.

Or be a maintainer, and adopt (the documentation of) a function.

##### LICENCE

(c) 2010-2016 Danny Arends

