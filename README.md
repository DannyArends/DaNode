DaNode - A secure, small footprint web server written in D
----------------------------------------------------------
master: [![D](https://github.com/DannyArends/DaNode/actions/workflows/d.yml/badge.svg?branch=master)](https://github.com/DannyArends/DaNode/actions/workflows/d.yml)
licence: [![license](https://img.shields.io/github/license/DannyArends/DaNode.svg?style=flat)](https://github.com/DannyArends/DaNode/blob/master/LICENSE.txt)

DaNode is a web server written in the [D programming language](https://dlang.org/) that can host websites in **ANY** language that can output to *stdout*. It supports multiple domains, SSL via [ImportC](https://dlang.org/spec/importc.html) with support for [Server Name Indication](https://en.wikipedia.org/wiki/Server_Name_Indication) (SNI) and [ACME](https://en.wikipedia.org/wiki/Automatic_Certificate_Management_Environment) automatic certificate renewal.

*Battle tested in production for over 12 years, including hosting my own [personal website](https://www.dannyarends.nl/).*

### Main features

- Host websites in **ANY** language that has a *stdout*
- Minimal footprint - code, CPU and RAM
- HTTPS with SNI, TLS 1.2+ and ACME auto-renew
- Static files support ETag, gzip and range requests
- Streams large file uploads directly to disk
- Native APIs: PHP, Python, D, R - or [add your own](api/)

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
nohup authbind danode/server -b 100 -v 0 > server.log 2>&1 &
```
Start the server with a backlog (-b) of 100 simultaneous connection (per port), and less log output (-v 0).

```
--port        -p      # HTTP port to listen on (integer)
--backlog     -b      # Backlog of clients supported simultaneously per port (integer)
--ssl                 # Location of SSL certificates folder (string)
--sslKey              # Server private key filename (string)
--accountKey          # Let's Encrypt account key filename (string)
--wwwRoot             # Server www root folder holding website domains (string)
--verbose     -v      # Verbose level, logs on STDOUT (integer)
```

### server.config

Place a `server.config` file in your `wwwRoot` folder to tune server behaviour:

```
max_header_size   = 32768       # Max HTTP header size in bytes (default 32KB)
max_request_size  = 2097152     # Max POST body size in bytes (default 2MB)
max_upload_size   = 104857600   # Max multipart upload size in bytes (default 100MB)
max_cgi_output    = 10485760    # Max CGI output size in bytes (default 10MB)
cgi_timeout       = 4500        # CGI script timeout in ms (default 4500ms)
max_sse_time      = 60000       # Max SSE connection lifetime in ms (default 60s)
pool_size         = 200         # Worker thread pool size (default 200)
serverinfo        = DaNode/1.0  # Server header string
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
Add the following lines in your web.config file to redirect to the index.php file, and 
allow the webserver to execute the php script, and redirect the incomming requests to 
the index.php page:

```
allowcgi = yes
redirect = index.php
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

### Contributing

Want to contribute? Great! Contribute to this repo by starring ⭐ or forking 🍴, and feel 
free to start an issue first to discuss idea's before sending a pull request. You're also 
welcome to post comments on commits.

### License

Written by Danny Arends and released as [GPLv3](LICENSE.txt).
