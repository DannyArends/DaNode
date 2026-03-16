DaNode - A secure and small footprint web server for D
------------------------------------------------------
master: [![D](https://github.com/DannyArends/DaNode/actions/workflows/d.yml/badge.svg?branch=master)](https://github.com/DannyArends/DaNode/actions/workflows/d.yml)
licence: [![license](https://img.shields.io/github/license/DannyArends/DaNode.svg?style=flat)](https://github.com/DannyArends/DaNode/blob/master/LICENSE.txt)

Web server written in the [D programming language](https://dlang.org/) to host websites written in **ANY** programming language that can 
output to *stdout*. DaNode handles on multiple domains. DaNode supports hosting multiple domains, and provides encryption over SSL using 
[Server Name Identification](https://en.wikipedia.org/wiki/Server_Name_Indication), SSL certificates are automatically renewed via the 
[ACME protocol](https://en.wikipedia.org/wiki/Automatic_Certificate_Management_Environment).

*DaNode has been battle tested in production for over 12 years, including hosting my own [personal website](https://www.dannyarends.nl/).*

Written because I was looking for a quick way of sharing [Rscript](https://www.r-project.org/about.html) output with other researchers at 
different universities. owever, shortly after I wanted to use other programming languages as well, so I made the server able to serve 
**ANY** programming language. DaNode makes it easy to any language to write an SSL encrypted website, use any language to write your SSL 
encrypted homepage, why not [brainfuck](https://en.wikipedia.org/wiki/Brainfuck)? However, more common languages such as 
[Ada](https://en.wikipedia.org/wiki/Ada), [R](https://www.r-project.org) or [PHP](https://en.wikipedia.org/wiki/PHP) are also fine.

### Main features

- Build your website in **ANY** programming language that can output to *stdout*
- SSL/HTTPs support by [openSSL 3.0](https://www.openssl.org/) through [ImportC](https://dlang.org/spec/importc.html)
- [Server Name Identification](https://en.wikipedia.org/wiki/Server_Name_Indication) by using free [Let's encrypt](https://letsencrypt.org/) certificates
- Automatic certificate renewal via the [ACME protocol](https://en.wikipedia.org/wiki/Automatic_Certificate_Management_Environment)
- Modern [TLS](https://en.wikipedia.org/wiki/Transport_Layer_Security) - TLS 1.2 minimum, but TLS 1.3 preference
- Small footprint: Code, CPU and RAM
- [Partial Content](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Range_requests) allows streaming video, audio
- API support for PHP, Python, D, R, or add your own in: [api/](api/)
- [Example](www/localhost/) web applications, including [PHP](www/localhost/php.php), [Perl](www/localhost/perl.pl), [D](www/localhost/keepalive.d), [R](www/localhost/rscript.r), [brainfuck](www/localhost/test.bf) and [Ada](www/localhost/test.ada).

### Get DaNode

Install the DMD compiler from [https://dlang.org/](https://dlang.org/download.html) and clone the source code from Github

```
git clone --recursive https://github.com/DannyArends/DaNode.git
cd DaNode
```
Build DaNode using the dub package manager

```
dub build
```

Another option is to compile using the compile script

```
./sh/compile
```

Start the web server at a specific port (e.g. 8080)

```
./bin/server -p 8080
```

Confirm that the web server is running by going to: http://localhost:8080/

### Enable HTTPs support

To compile the server with HTTPS support (binds to port 443), first compile openSSL in 
the [deps](./deps/) folder, see the [guide](./deps/README.md). After that use dub and 
specify the _ssl_ configuration:

```
dub build --config=ssl
```

or, compile using the compile script:

```
./sh/compile ssl
```

Start the web server on port 80 and 443:

```
./bin/server
```

After starting the server, confirm that the web server is running by going to http://127.0.0.1/ 
and https://127.0.0.1/ and make sure you have enough user rights to bind port 80 and 443, a server 
private key and domain certificates are required. I use Let's Encrypt to secure my own homepage. 
Setup instructions for Let's Encrypt can be found in the [sh/letsEncrypt](sh/letsEncrypt) file.

### Troubleshooting: [ERROR]  unable to bind socket on port 80

Starting the server on port 80 and 443 might fail, when you do not have appropriate 
rights on the system. First check if you can start the server on another port:

```
./danode/server -p 8080
```

I use _nohup_ and _authbind_ to start the web server in deamon (background) mode at port 80, and 443 (SSL). 
First, install _nohup_ and _authbind_ via your package manager, configure _authbind_ to allow 
connections to port 80 (and 443, when using the ssl version), then start the webserver by running:

```
./sh/run
```

### Command-line parameters

The content of the [./sh/run](sh/run) shell script:

```
nohup authbind danode/server -k -b 100 -v 2 > server.log 2>&1 &
```

This starts the server, does not allow for keyboard command (-k) has a backlog (-b) 
of 100 simultaneous connection (per port), and produces more log output (-v 2).

```
--port      -p       HTTP port to listen on (integer)
--backlog   -b       Backlog of clients supported simultaneously per port (integer)
--keyoff    -k       Keyboard input via STDIN (boolean)
--certDir            Location of folder with SSL certificates (string)
--keyFile            Server private key location (string)
--wwwRoot            Server www root folder holding website domains (string)
--verbose   -v       Verbose level, logs on STDOUT (integer)
```

### Example websites

See the [www/](www/) folder for a number of example web sites. After compiling the web 
server, run the web server and the [www/localhost/](www/localhost/) folder is available 
at http://localhost/ or http://127.0.0.1/ from the browser. For the other examples in 
the [www/](www/) folder you will have to update your hosts file.

### Create a PHP enabled website

To create a simple PHP enabled web site first download and install DaNode, the next 
step is to create a directory for the new website, by executing the following commands 
from the DaNode directory:

```
mkdir www/domain.xxx
touch www/domain.xxx/index.php
```

Add some php / html content to the index page, and create a web.config file:

```
touch www/domain.xxx/web.config
```

Add the following configuration settings to the web.config file, if you want to use 
scripting languages such as PHP, you have to manually allow the execution of cgi file. 
Add the following lines in your web.cofig file to redirect to the index.php file, and 
allow the webserver to execute the php script, and redirect the incomming requests to 
the index.php page:

```
allowcgi     = yes
redirecturl  = index.php
```

### Update the hosts file

If you do not own the domain name you want to host, use the /etc/hosts file to redirect 
requests from the domain name to your local IP address using the hosts file:

```
sudo nano /etc/hosts
```

Then add the following lines to this hostfile using your favourite editor:

```
127.0.0.1   domain.xxx
127.0.0.1   www.domain.xxx
```

Save the file with these lines added, then open a browser and navigate to: 
http://www.domain.xxx, you should now see the content of your php / html file.

### Supported back-end languages

Languages with supported APIs: PHP, PYTHON, D, R

See: [api/README.md](api/README.md)

### Contributing

Want to contribute? Great! Contribute to this repo by starring ⭐ or forking 🍴, and feel 
free to start an issue first to discuss idea's before sending a pull request. You're also 
welcome to post comments on commits.

### License

Written by Danny Arends and released as [GPLv3](LICENSE.txt).
