DaNode - A secure and small footprint web server for D 
------------------------------------------------------
master: [![D](https://github.com/DannyArends/DaNode/actions/workflows/d.yml/badge.svg?branch=master)](https://github.com/DannyArends/DaNode/actions/workflows/d.yml)
licence: [![license](https://img.shields.io/github/license/DannyArends/DaNode.svg?style=flat)](https://github.com/DannyArends/DaNode/blob/master/LICENSE.txt)

Web server written in the [D programming language](https://dlang.org/) to 
host server side web applications (written in any programming language) on multiple domains. 
It provides encrypted HTTP content over SSL using 
[Server Name Identification](https://en.wikipedia.org/wiki/Server_Name_Indication), 
and has been battle tested in production for over 5 years hosting several of my 
web domains, such as my own [personal website](https://www.dannyarends.nl/).

Written because I was looking for a quick way of sharing 
[Rscript](https://www.r-project.org/about.html) output with other researchers at 
different universities. Once working I wanted to use other programming languages as 
well and added generic support for other languages. Use any language to 
write your SSL encrypted homepage, why not
[brainfuck](https://en.wikipedia.org/wiki/Brainfuck), however 
[Ada](https://en.wikipedia.org/wiki/Ada), 
[R](https://www.r-project.org) or 
[PHP](https://en.wikipedia.org/wiki/PHP) are also fine.

The web servers main features / aims summarized:
- Support server side web applications written in any programming language
- SSL/HTTPs support by [openSSL](https://www.openssl.org/) and [Deimos bindings](https://github.com/D-Programming-Deimos/openssl)
- [Server Name Identification](https://en.wikipedia.org/wiki/Server_Name_Indication) by using multiple free [Let's encrypt](https://letsencrypt.org/) certificates
- Small footprint: Code, CPU and RAM
- API support for PHP, Python, D, R, or add your own in: [api/](api/)
- [Example](www/localhost/) web applications, including [PHP](www/localhost/php.php), [Perl](www/localhost/perl.pl), [D](www/localhost/keepalive.d), [R](www/localhost/rscript.r), [brainfuck](www/localhost/test.bf) and [Ada](www/localhost/test.ada).

##### Get DaNode

Install the DMD compiler from [https://dlang.org/](https://dlang.org/download.html)

Clone the source code from Github

    git clone https://github.com/DannyArends/DaNode.git
    cd DaNode

Build DaNode using the dub package manager

    dub build

Another option is to compile using the compile script

    ./sh/compile

Start the web server at a specific port (e.g. 8080)

    ./danode/server -p 8080

Confirm that the web server is running by going to: http://localhost:8080/

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
of 100 simultaneous connection (per port), and produces more log output (-v 2).

          --port      -p       HTTP port to listen on (integer)
          --backlog   -b       Backlog of clients supported simultaneously per port (integer)
          --keyoff    -k       Keyboard input via STDIN (boolean)
          --certDir            Location of folder with SSL certificates (string)
          --keyFile            Server private key location (string)
          --wwwRoot            Server www root folder holding website domains (string)
          --verbose   -v       Verbose level, logs on STDOUT (integer)

##### Example websites

See the [www/](www/) folder for a number of example web sites. After compiling the web 
server, run the web server and the [www/localhost/](www/localhost/) folder is available 
at http://localhost/ or http://127.0.0.1/ from the browser. For the other examples in 
the [www/](www/) folder you will have to update your hosts file.

##### Create a PHP enabled website

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

##### Update the hosts file

If you do not own the domain name you want to host, use the /etc/hosts file to redirect 
requests from the domain name to your local IP address using the hosts file:

    sudo nano /etc/hosts

Then add the following lines to this hostfile using your favourite editor:

    127.0.0.1   domain.xxx
    127.0.0.1   www.domain.xxx

Save the file with these lines added, then open a browser and navigate to: 
http://www.domain.xxx, you should now see the content of your php / html file.

##### Supported back-end languages

Languages with supported APIs: PHP, PYTHON, D, R

See: [api/README.md](api/README.md)

##### Contributing

Want to contribute? Great! Contribute to DaNode by starring or forking on Github, 
and feel free to start an issue or sending a pull request.

Fell free to also post comments on commits.

Or be a maintainer, and adopt (the documentation of) a function.

##### License

DaNode is written by Danny Arends and is released under the GNU GENERAL PUBLIC 
LICENSE Version 3 (GPLv3). See [LICENSE.txt](LICENSE.txt).

