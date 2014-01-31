# APIs

The APIs provide access to POST and GET data in hosted CGI applications.

## PHP

```PHP
     <?php include 'api/danode.php'; ?>
```

## PERL

```Perl
     use api::danode;
```

## D

```D
     import api.danode;
     
     void main(string[] args){
       auto GET  = getGET(args);
       auto POST = getPOST();
     }
```

## R

```R
     source("api/danode.r")
```
