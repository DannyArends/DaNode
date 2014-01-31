#!perl -w
use strict;
use api::danode;
use HTML::Perlinfo;

print "HTTP/1.1 200 OK\n";
print "Content-Type: text/html; charset=utf-8\n\n";
perlinfo();
