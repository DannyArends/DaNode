
getGET <- function(){
  entval     <- strsplit(commandArgs(TRUE),"=")
  GET        <- unlist(lapply(entval,"[[",2))
  names(GET) <- unlist(lapply(entval,"[[",1))
  return(GET)
}

POST <- NULL; pnames <- NULL;
SERVER <- NULL; snames <- NULL;
f <- file("stdin")
open(f,"rt")
while(length(line <- readLines(f,1)) > 0) {
  elems <- strsplit(line,"=")[[1]]
  if(length(elems) >= 2){
    if(elems[1] %in% c("POST","FILE")){
      pnames <- c(pnames, elems[2])
      if(length(elems) == 3){
        POST <- c(POST, URLdecode(elems[3]))
      }else{ 
        POST <- c(POST, "") 
    } }      
    if(elems[1] == "SERVER"){
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

