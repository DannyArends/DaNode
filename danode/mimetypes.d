module danode.mimetypes;

import std.file : extension;
import std.string : toLower;

immutable string      UNSUPPORTED_FILE = "file/unknown";                            /// Unsupported file mime
immutable string      CGI_FILE         = "executable/";                             /// CGI mime prefix

pure string mime(string i){
  switch(extension(i).toLower()){
    case ".htx", ".htm", ".html", ".htmls": return "text/html";
    case ".map", ".gitignore", ".txt", ".md" : return "text/plain";
    case ".xml"  : return "text/xml";
    case ".css"  : return "text/css";
    
    case ".gif"  : return "image/gif";
    case ".ico"  : return "image/x-icon";
    case ".jpg", ".jpeg" : return "image/jpeg";
    case ".png"  : return "image/png";
    case ".tif", ".tiff" : return "image/tiff";
    case ".rgb"  : return "image/x-rgb";
    case ".svg", ".svgz" : return "image/svg-xml";
    
    case ".mid", ".midi" : return "audio/midi";
    case ".mp2", ".mp3"  : return "audio/mpeg";
    case ".ogg"  : return "audio/ogg";
    case ".wav"  : return "audio/wav";
    
    case ".mpg", ".mpe", ".mpeg" : return "video/mpeg";
    case ".qt", ".mov"  : return "video/quicktime";
    case ".avi"  : return "video/x-msvideo";
    case ".movie": return "video/x-sgi-movie";
    
    case ".bin", ".class", ".dll", ".exe"  : return "application/octet-stream";
    case ".gz"   : return "application/x-gzip";
    case ".js"   : return "application/x-javascript";
    case ".pdf"  : return "application/pdf";
    case ".rar", ".tgz"  : return "application/x-compressed";
    case ".tar"  : return "application/x-tar";
    case ".z"    : return "application/x-compress";
    case ".zip"  : return "application/x-zip-compressed";

    case ".doc", ".dot"  : return "application/msword";
    case ".docx" : return "applications/vnd.openxmlformats-officedocument.wordprocessingml.document";
    case ".dotx" : return "applications/vnd.openxmlformats-officedocument.wordprocessingml.template";

    case ".ppt"  : return "application/vnd.ms-powerpoint";
    case ".pptx" : return "application/vnd.openxmlformats-officedocument.presentationml.presentation";

    case ".xls", ".xlt", ".xla"  : return "application/vnd.ms-excel";

    case ".xlsx"  : return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
    case ".xltx"  : return "application/vnd.openxmlformats-officedocument.spreadsheetml.template";

    case ".scss" : return CGI_FILE ~ "sass -t compact"; //nested (default), compact, compressed, or expanded
    case ".cgi"  : return CGI_FILE ~ "perl";
    case ".d"    : return CGI_FILE ~ "rdmd";
    case ".pl"   : return CGI_FILE ~ "perl -X";
    case ".php"  : return CGI_FILE ~ "php5-cgi -n -C -dextension=gd.so";
    case ".py"   : return CGI_FILE ~ "pyton";
    case ".r"    : return CGI_FILE ~ "Rscript --vanilla";
    default : return UNSUPPORTED_FILE;
  }
}

