HTTP-SERVER 'DaNode'

STRUCTURE

The DaNode server is designed to handle multiple websites independant and simultaneously. The DaNode 
front-end routes incomming HTTP requests to the correct web folder. It allows for multiple index pages 
and executes scripts in other languages (PHP, Python, D and R). Results from CGI scripts are parsed 
back into the DaNode system, (e.g. check errors, infinite loops) and send to the requesting client.

                                  ┊┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┊    HTTP response
      HTTP request ━━━━━━━┓       ┊Client                          ┊          ║
                          ┃       ┊                ┏━━━━━ CGI ━━━━━━━━━━━━━━━━╢
                       Server ━━━━━━ Router ═══════╡               ┊          ║
                                  ┊    ┃           ┗━━ FileBuffer ━━━━━━━━━━━━╢
     HTTPS request ━━━━━ SSL ━━━━━━━━━━┛                           ┊          ║
                                  ┊┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┊   HTTPS response


API's

             GET   POST    SERVER    FILE     CONFIG
     PHP     V     V       V         ?        V
     PYTHON  V     V
     D       V     V       V         ?
     R       V     V

EXAMPLES

See the www/ folder for an example web sites, running under http://localhost/. To create a new website 
running under http://domain.xxx/ create a new folder called: www/domain.xxx directory, and redirect the 
domain using the .hosts file. An example to create a simple PHP enabled web site:

    mkdir www/domain.xxx
    touch www/domain.xxx/index.php

Then add some html content to the index page, optionally you can create a web.config file:

    touch www/domain.xxx/web.config

Add optional configuration settings to the web.config file, if you want to use PHP, you have to manually 
enable the cgi execution in this file. An example:

    shorturl     = yes
    allowcgi     = yes
    redirecturl  = index.php
    coindaemon   = no

If you don't own the domain, redirect the domain to your local IP address using the hosts file

    sudo nano /etc/hosts

Then add the lines to this file:

    127.0.0.1   domain.xxx
    127.0.0.1   www.domain.xxx

Open a browser and navigate to: http://www.domain.xxx, you should now see the content of your html file

TESTS

     PHP, PYTHON, D, R

ADVANCED

  - WEBSITE-CONFIG
   - Sub-domain redirecting, such as www.test.nl -> test.nl
   - Directory browsing
   - Custom index page
   - Server overview page at http://127.0.0.1/

  - FILEBUFFER
   - Buffer small files and serve from memory
   - Stream large downloads using a flexible buffer

  - CRYPTOCOIN
   - Integration of crypto currency facade inside the web server
   - A crypto buffer that sends requests to the daemon
   - Tested: Bitcoin, DogeCoin and FedoraCoin (TIPS)
   - Example in www/localhost/crypto.html

LICENCE

(c) 2010-2014 Danny Arends

