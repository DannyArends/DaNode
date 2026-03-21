/** danode/files.d - Static file serving, gzip compression, ETag, and range requests
  * License: GPLv3 (https://github.com/DannyArends/DaNode) - Danny Arends **/
module danode.files;

import danode.imports;
import danode.statuscode : StatusCode;
import danode.mimetypes : mime, UNSUPPORTED_FILE;
import danode.payload : Payload, PayloadType, Message;
import danode.log : log, tag, error, Level;
import danode.functions : htmltime;
import danode.request : Request;
import danode.response : Response, notModified;
import danode.filesystem : FilePayload, FileStream, isCGI;

// Should the file be compressed ?
bool isCompressible(string mime) {
  return mime.startsWith("text/") || mime == "application/json" || mime == "application/javascript" || mime == "image/svg+xml";
}

// Serve a static file from the disc, send encrypted when requested and available
void serveStaticFile(ref Response response, in Request request, FilePayload reqFile) {
  log(Level.Trace, "serving a static file");
  string etag = format(`"%s"`, md5UUID(reqFile.filePath ~ reqFile.mtime.toISOString()));

  // Send not modified if ETag matches (this adds the etag in the response)
  if (request.ifNoneMatch == etag || request.ifModified >= reqFile.mtime()) { return response.notModified(reqFile.mimetype, etag); }
  if (reqFile.needsupdate()) { reqFile.buffer(); }  // File might need to be buffered

  // Add the ETag to every response (both range and normal files)
  response.customheader("ETag", etag);
  if (request.hasRange) { return(response.serveRangeFile(request, reqFile)); }

  if (request.acceptsEncoding("gzip") && reqFile.hasEncodedVersion && isCompressible(reqFile.mimetype)) {
    log(Level.Verbose, "will serve %s with gzip encoding", request.path);
    reqFile.gzip = true;
    response.customheader("Content-Encoding", "gzip");
  }
  response.payload = new FileStream(reqFile);
  if (!reqFile.gzip) response.customheader("Accept-Ranges", "bytes");
  response.ready = true;
}

// Serve a File Range from a static file on disc
void serveRangeFile(ref Response response, in Request request, FilePayload reqFile) {
  long[2] r = request.range();
  long total = reqFile.fileSize();
  long start = r[0];
  long end = r[1] < 0 ? total - 1 : r[1];
  if (start >= total || end >= total || start > end) {
    response.payload = new Message(StatusCode.RangeNotSatisfiable);
    response.customheader("Content-Range", format("bytes */%d", total));
  } else {
    response.customheader("Content-Range", format("bytes %d-%d/%d", start, end, total));
    response.customheader("Accept-Ranges", "bytes");
    response.rangeStart = start;
    response.rangeEnd = end;
    response.isRange = true;
    response.payload = new FileStream(reqFile);
    log(Level.Trace, "serveRangeFile: serving %d bytes", end - start + 1);
  }
  response.ready = true;
}

unittest {
  import danode.interfaces : StringDriver;
  import danode.router : Router, runRequest;

  tag(Level.Always, "FILE", "%s", __FILE__);

  auto router = new Router("./www/", Address.init);
  StringDriver res;

  // Route 1: 304 Not Modified
  res = router.runRequest("GET /index.html HTTP/1.1\nHost: localhost\nIf-Modified-Since: " ~ htmltime(Clock.currTime + 1.hours) ~ "\n\n");
  assert(res.lastStatus == StatusCode.NotModified, format("Expected 304, got %d", res.lastStatus.code));

  // Route 2: Range request
  res = router.runRequest("GET /test.pdf HTTP/1.1\nHost: localhost\nRange: bytes=0-1023\n\n");
  assert(res.lastStatus == StatusCode.PartialContent, format("Expected 206, got %d", res.lastStatus.code));

  // Route 3: Gzip compression
  res = router.runRequest("GET /index.html HTTP/1.1\nHost: localhost\nAccept-Encoding: gzip\n\n");
  assert(res.lastStatus == StatusCode.Ok, format("Expected 200, got %d", res.lastStatus.code));
  assert(res.lastHeaders.get("Content-Encoding", "") == "gzip", "Expected gzip Content-Encoding header");
  assert(res.lastBody.length >= 2 && res.lastBody[0] == 0x1f && res.lastBody[1] == 0x8b, "Expected gzip magic bytes 1f 8b");

  // Route 4: ETag - not modified
  res = router.runRequest("GET /index.html HTTP/1.1\nHost: localhost\n\n");
  string etag = res.lastHeaders.get("ETag", "");
  assert(etag.length > 0, "Expected ETag header in response");

  res = router.runRequest("GET /index.html HTTP/1.1\nHost: localhost\nIf-None-Match: " ~ etag ~ "\n\n");
  assert(res.lastStatus == StatusCode.NotModified, format("Expected 304, got %d", res.lastStatus.code));
}

