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

See the www/ folder for some example web sites/applications. To add a new domain simply create a 
new folder in the www/ folder to create an empty website.

TESTS

     PHP, PYTHON, D, R

ADVANCED

  - WEBSITE-CONFIG
   - Directory browsing
   - Custom index page

  - FILEBUFFER
   - Buffer small files and serve from memory

LICENCE

(c) 2010-2014 Danny Arends

