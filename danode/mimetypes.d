module danode.mimetypes;
import std.stdio, std.string, std.path : extension;
import danode.structs;

pure string toMime(string i){
  switch(extension(i).toLower()){
    case ".htx"  : return "text/html";
    case ".htm"  : return "text/html";
    case ".html" : return "text/html";
    case ".htmls": return "text/html";
    case ".txt"  : return "text/plain";
    case ".md"   : return "text/plain";
    case ".xml"  : return "text/xml";
    case ".css"  : return "text/css";
    
    case ".gif"  : return "image/gif";
    case ".ico"  : return "image/x-icon";
    case ".jpg"  : return "image/jpeg";
    case ".jpeg" : return "image/jpeg";
    case ".png"  : return "image/png";
    case ".tif"  : return "image/tiff";
    case ".tiff" : return "image/tiff";
    case ".rgb"  : return "image/x-rgb";
    case ".svg"  : return "image/svg-xml";
    case ".svgz" : return "image/svg-xml";
    
    case ".mid"  : return "audio/midi";
    case ".midi" : return "audio/midi";
    case ".mp2"  : return "audio/mpeg";
    case ".mp3"  : return "audio/mpeg";
    case ".ogg"  : return "audio/ogg";
    case ".wav"  : return "audio/wav";
    
    case ".mpg"  : return "video/mpeg";
    case ".mpe"  : return "video/mpeg";
    case ".mpeg" : return "video/mpeg";
    case ".qt"   : return "video/quicktime";
    case ".mov"  : return "video/quicktime";
    case ".avi"  : return "video/x-msvideo";
    case ".movie": return "video/x-sgi-movie";
    
    case ".bin"  : return "application/octet-stream";
    case ".class": return "application/octet-stream";
    case ".dll"  : return "application/octet-stream";
    case ".exe"  : return "application/octet-stream";
    case ".gz"   : return "application/x-gzip";
    case ".js"   : return "application/x-javascript";
    case ".pdf"  : return "application/pdf";
    case ".rar"  : return "application/x-compressed";
    case ".tar"  : return "application/x-tar";
    case ".tgz"  : return "application/x-compressed";
    case ".z"    : return "application/x-compress";
    case ".zip"  : return "application/x-zip-compressed";

    case ".doc"  : return "application/msword";
    case ".dot"  : return "application/msword";
    case ".docx" : return "applications/vnd.openxmlformats-officedocument.wordprocessingml.document";
    case ".dotx" : return "applications/vnd.openxmlformats-officedocument.wordprocessingml.template";

    case ".ppt"  : return "application/vnd.ms-powerpoint";
    case ".pptx" : return "application/vnd.openxmlformats-officedocument.presentationml.presentation";

    case ".xls"  : return "application/vnd.ms-excel";
    case ".xlt"  : return "application/vnd.ms-excel";
    case ".xla"  : return "application/vnd.ms-excel";

    case ".xlsx"  : return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
    case ".xltx"  : return "application/vnd.openxmlformats-officedocument.spreadsheetml.template";

    case ".gitignore" : return "text/plain";

    case ".scss" : return CGI_FILE ~ "sass -t compact"; //nested (default), compact, compressed, or expanded
    case ".cgi"  : return CGI_FILE ~ "perl";
    case ".d"    : return CGI_FILE ~ "rdmd";
    case ".pl"   : return CGI_FILE ~ "perl";
    case ".php"  : return CGI_FILE ~ "php5-cgi -n -C -dextension=gd.so -q -f";
    case ".py"   : return CGI_FILE ~ "pyton";
    case ".r"    : return CGI_FILE ~ "Rscript";
    default: return UNSUPPORTED_FILE;
  }
}

