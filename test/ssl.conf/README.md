# Generate a private key
openssl genrsa -des3 -out .ssl/server.key 1024

# Set the passphrase into the key, so the start of the webserver doesn't ask for it
cp .ssl/server.key .ssl/server.key.org
openssl rsa -in .ssl/server.key.org -out .ssl/server.key

# Certificate Signing Request, use our config
openssl req -new -key .ssl/server.key -out .ssl/localhost.csr -config ./test/ssl.conf/localhost.cnf
openssl req -new -key .ssl/server.key -out .ssl/dannyarends.nl.csr -config ./test/ssl.conf/dannyarends.nl.cnf
openssl req -new -key .ssl/server.key -out .ssl/wordpress.test.csr -config ./test/ssl.conf/wordpress.test.cnf

# View what is requested:
# openssl req -text -noout -in localhost.csr

# Sign the key yourself get a 3650 day certificate
openssl x509 -req -days 3650 -in .ssl/localhost.csr -signkey .ssl/server.key -out .ssl/localhost.crt -extfile ./test/ssl.conf/localhost.cnf -extensions v3_req
openssl x509 -req -days 3650 -in .ssl/dannyarends.nl.csr -signkey .ssl/server.key -out .ssl/dannyarends.nl.crt -extfile ./test/ssl.conf/dannyarends.nl.cnf -extensions v3_req
openssl x509 -req -days 3650 -in .ssl/wordpress.test.csr -signkey .ssl/server.key -out .ssl/wordpress.test.crt -extfile ./test/ssl.conf/wordpress.test.cnf -extensions v3_req
