module danode.mimetypes;

import danode.imports;

immutable string      UNSUPPORTED_FILE = "file/unknown";                            /// Unsupported file mime
immutable string      CGI_FILE         = "executable/";                             /// CGI mime prefix

pure string mime(string i) {
  switch(extension(i).toLower()){
    case ".htx", ".htm", ".html", ".htmls": return "text/html";
    case ".map", ".gitignore", ".txt", ".md", ".log", ".list" : return "text/plain";
    case ".xml"  : return "text/xml";
    case ".css"  : return "text/css";
    case ".csv"  : return "text/csv";
    case ".ics"  : return "text/calendar";
    case ".rtx"  : return "text/richtext";
    case ".vcard"  : return "text/vcard";
    
    case ".eml", "mime"  : return "message/rfc822";
    
    case ".bmp"  : return "image/bmp";
    case ".gif"  : return "image/gif";
    case ".ico"  : return "image/x-icon";
    case ".jpg", ".jpeg" : return "image/jpeg";
    case ".png"  : return "image/png";
    case ".tif", ".tiff" : return "image/tiff";
    case ".rgb"  : return "image/x-rgb";
    case ".sgi" : return "image/sgi";
    case ".svg", ".svgz" : return "image/svg+xml";
    case ".psd" : return "image/vnd.adobe.photoshop";
    
    case ".3ds" : return "image/x-3ds";
    case ".mid", ".midi" : return "audio/midi";
    case ".mp2", ".mp3"  : return "audio/mpeg";
    case ".ogg"  : return "audio/ogg";
    case ".wav"  : return "audio/wav";
    case ".aac"  : return "audio/aac";
    
    case ".mpg", ".mpe", ".mpeg", "m1v", "m2v" : return "video/mpeg";
    case ".qt", ".mov"  : return "video/quicktime";
    case ".avi"  : return "video/x-msvideo";
    case ".mp4", "mp4v", "mpg4" : return "video/mp4";
    case ".movie": return "video/x-sgi-movie";
    case ".webm": return "video/webm";
    
    case ".bin", ".class", ".dll", ".exe",".rdata"  : return "application/octet-stream";
    case ".apk"  : return "application/vnd.android.package-archive";
    case ".ecma"  : return "application/ecmascript";
    case ".epub"  : return "application/epub+zip";
    case ".azw"  : return "application/vnd.amazon.ebook";
    case ".gz"   : return "application/x-gzip";
    case ".js"   : return "application/x-javascript";
    case ".pdf"  : return "application/pdf";
    case ".rar", ".tgz"  : return "application/x-compressed";
    case ".tar"  : return "application/x-tar";
    case ".z"    : return "application/x-compress";
    case ".zip"  : return "application/x-zip-compressed";
    case ".bz"   : return "application/x-bzip";
    case ".bz2"  : return "application/x-bzip2";
    case ".jar"  : return "application/java-archive";

    case ".bib", ".bibtex"  : return "application/x-bibtex";
    case ".doc", ".dot"  : return "application/msword";
    case ".rtf"  : return "application/rtf";
    case ".docx" : return "applications/vnd.openxmlformats-officedocument.wordprocessingml.document";
    case ".dotx" : return "applications/vnd.openxmlformats-officedocument.wordprocessingml.template";

    case ".ppt"  : return "application/vnd.ms-powerpoint";
    case ".pptx" : return "application/vnd.openxmlformats-officedocument.presentationml.presentation";

    case ".xls", ".xlt", ".xla"  : return "application/vnd.ms-excel";

    case ".xlsx"  : return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
    case ".xltx"  : return "application/vnd.openxmlformats-officedocument.spreadsheetml.template";

    case ".comp"  : return "x-shader/x-compute";
    case ".vert"  : return "x-shader/x-vertex";
    case ".frag"  : return "x-shader/x-fragment";
    case ".geom"  : return "x-shader/x-geometry";

    case ".eot"  : return "application/vnd.ms-fontobject";
    case ".ttf"  : return "font/ttf";
    case ".woff"  : return "font/woff";
    case ".woff2"  : return "font/woff2";

    case ".pem-certificate-chain"  : return "application/pem-certificate-chain";
    case ".pgp-encrypted"  : return "application/pgp-encrypted";
    case ".pgp-signature"  : return "application/pgp-signature";

    case ".x-x509-ca-cert"  : return "application/x-x509-ca-cert";
    case ".x-x509-ca-ra-cert"  : return "application/x-x509-ca-ra-cert";
    case ".x-x509-next-ca-cert"  : return "application/x-x509-next-ca-cert";

    case ".scss" : return CGI_FILE ~ "sass -t compact"; //nested (default), compact, compressed, or expanded
    case ".cgi"  : return CGI_FILE ~ "perl";
    case ".d"    : return CGI_FILE ~ "rdmd";
    case ".pl"   : return CGI_FILE ~ "perl -X";
    case ".php", ".fphp" : return CGI_FILE ~ "php-cgi -C";
    case ".py"   : return CGI_FILE ~ "pyton";
    case ".r"    : return CGI_FILE ~ "Rscript --vanilla";
    case ".bf"   : return CGI_FILE ~ "bf";
    case ".ada"  : return CGI_FILE ~ "gnatmake";
    default : return UNSUPPORTED_FILE;
  }
}

