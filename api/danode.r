
getGET <- function(){
  qs <- Sys.getenv("QUERY_STRING")
  if(qs == "") return(setNames(character(0), character(0)))
  params <- strsplit(qs, "&")[[1]]
  entval <- strsplit(params, "=", fixed=TRUE)
  GET        <- sapply(entval, function(x) if(length(x) > 1) URLdecode(x[2]) else "")
  names(GET) <- sapply(entval, function(x) x[1])
  return(GET)
}

POST <- NULL; pnames <- NULL;
SERVER <- NULL; snames <- NULL;
f <- file("stdin")
open(f,"rt")
while(length(line <- readLines(f,1)) > 0) {
  elems <- strsplit(line,"=")[[1]]
  if(length(elems) >= 2){
    if(elems[1] %in% c("P","F")){
      pnames <- c(pnames, elems[2])
      if(length(elems) == 3){
        POST <- c(POST, URLdecode(elems[3]))
      }else{ 
        POST <- c(POST, "") 
    } }
    if(elems[1] == "S"){
      snames <- c(snames, elems[2])
      if(length(elems) == 3){
        SERVER <- c(SERVER, URLdecode(elems[3]))
      }else{ 
        SERVER <- c(SERVER, "") 
    } }
  }
}
names(POST) <- pnames
names(SERVER) <- snames

toS <- function(args){
  return(paste("['",paste(names(args),args,collapse="','",sep="':'"),"']",sep=""))
}

GET  <- getGET()

