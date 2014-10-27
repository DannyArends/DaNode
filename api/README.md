# APIs

The APIs provide access to POST and GET data in hosted CGI applications.

## PHP
See a working example [HERE](../www/localhost/php.php)

```PHP
     <?php include 'api/danode.php'; ?>
```

## PERL
See a working example [HERE](../www/localhost/perl.pl)

```Perl
     use api::danode;
```

## D
See a working example  [HERE](../www/localhost/dmd.d)

```D
     import api.danode;
     
     void main(string[] args){
       setGET(args);              // Set the GET variables from the cmd args
     }
```

## R
See a working example  [HERE](../www/localhost/rscript.r)

```R
     source("api/danode.r")
```
