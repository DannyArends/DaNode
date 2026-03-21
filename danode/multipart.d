/** danode/multipart.d - Streaming multipart/form-data parser
  * License: GPLv3 (https://github.com/DannyArends/DaNode) - Danny Arends **/
module danode.multipart;

import danode.imports;

import danode.request : Request;
import danode.post : PostItem, PostType;
import danode.log : log, tag, error, Level;

enum MPState { INIT, HEADER, BODY }

struct MultipartParser {
  string            boundary;               /// "--boundary"
  string            uploadDir;              /// directory for .up files
  MPState           state = MPState.INIT;   /// State of the parser
  char[]            tail;                   /// leftover bytes from previous chunk (boundary detection)
  File              outfile;                /// current open output file
  string            currentPath;            /// current .up file path
  string            currentMime;            /// current part mime type
  string            currentName;            /// current field name
  string            currentFname;           /// current filename
  Appender!(char[]) hdrbuf;                 /// accumulating part header bytes
  bool              done = false;           /// final boundary seen
  string            delim;                  /// "\r\n--boundary", cached
  Appender!(char[]) valuebuf;               /// accumulates plain field value

  this (string boundary, string uploadDir) {
    this.boundary = boundary;
    this.uploadDir = uploadDir;
    this.delim = "\r\n" ~ boundary;
  }

  @property bool isActive() const { return boundary.length > 0; }

  bool feed(ref Request request, const(char)[] chunk) {
    char[] data = tail ~ chunk;    // Prepend any leftover tail from previous chunk
    tail = [];

    while (data.length > 0 && !done) {
      final switch (state) {
        case MPState.INIT:          // Find opening boundary
          ptrdiff_t i = indexOf(data, boundary ~ "\r\n");
          if (i < 0) { return(saveTail(data));  }
          data = data[i + boundary.length + 2 .. $];
          state = MPState.HEADER;
          break;
        case MPState.HEADER:        // Accumulate until \r\n\r\n
          hdrbuf.put(data);
          ptrdiff_t i = indexOf(cast(string)hdrbuf.data, "\r\n\r\n");
          if (i < 0) { tail = []; return(false); }
          data = hdrbuf.data[i + 4 .. $].dup;
          hdrbuf.shrinkTo(i);
          parsePartHeader(request);
          hdrbuf.clear();
          state = MPState.BODY;
          break;
        case MPState.BODY:          // Look for \r\n--boundary
          ptrdiff_t i = indexOf(data, delim);
          if (i < 0) { // No boundary found - write all but tail
            ptrdiff_t keep = 0;
            foreach_reverse (k; 1 .. min(delim.length, data.length) + 1) {
              if (data[$ - k .. $] == delim[0 .. k]) { keep = k; break; }
            }
            ptrdiff_t safe = cast(ptrdiff_t)data.length - keep;
            if (safe > 0) { writeChunk(data[0 .. safe]); }
            return(saveTail(data[safe .. $]));
          }
          if (i + delim.length + 2 > data.length) { tail = data[i .. $].dup; if (i > 0) writeChunk(data[0 .. i]); return(false); }
          // Boundary found - write up to it and close part
          writeChunk(data[0 .. i]);
          closePart(request);
          data = data[i + delim.length .. $];
          if (data.length < 2) { return saveTail(data); }
          if (data[0..2] == "--") { return(done = true); }
          if (data[0..2] == "\r\n") { data = data[2..$]; }
          else { return saveTail(data); }
          state = MPState.HEADER;
      }
    }
    return done;
  }

  private bool saveTail(char[] d) { tail = d.dup; return false; }

  private void parsePartHeader(ref Request request) {
    string header = to!string(hdrbuf.data);
    currentName  = extractQuoted(header, "name");
    currentFname = extractQuoted(header, "filename");
    currentMime  = "application/octet-stream";
    foreach (line; header.split("\r\n")) {
      if (line.toLower.startsWith("content-type:")) { currentMime = strip(line[line.indexOf(":")+1 .. $]); break; }
    }
    if (currentFname.length > 0) {
      currentPath = uploadDir ~ md5UUID(format("%s-%s", request.id, currentName)).toString() ~ ".up";
      try { outfile = File(currentPath, "wb"); } 
      catch(Exception e) { error("MultipartParser: failed to open '%s': %s", currentPath, e.msg); }
      log(Level.Verbose, "MPART: [I] streaming file %s -> %s", currentFname, currentPath);
    }
  }

  private void writeChunk(const(char)[] chunk) {
    if (currentFname.length > 0 && outfile.isOpen()) {
      try { outfile.rawWrite(chunk); } catch(Exception e) { error("MultipartParser: write failed: %s", e.msg); }
    } else if (currentFname.length == 0 && currentName.length > 0) { valuebuf.put(chunk); }
  }

  private void closePart(ref Request request) {
    if (currentFname.length > 0) {
      if (outfile.isOpen()) outfile.close();
      long sz = currentPath.exists ? currentPath.getSize() : 0;
      request.postinfo[currentName] = PostItem(PostType.File, currentName, currentFname, currentPath, currentMime, sz);
      log(Level.Verbose, "MPART: [I] closed file %s, %d bytes", currentPath, sz);
      currentPath = ""; currentFname = ""; currentMime = "";
    } else if (currentName.length > 0) {  // Plain input field -accumulated valuebuf
      request.postinfo[currentName] = PostItem(PostType.Input, currentName, "", to!string(valuebuf.data));
      valuebuf.clear();
    }
    currentName = "";
  }
}

// Extract value from: name="value" or filename="value"
pure string extractQuoted(string s, string key) nothrow {
  ptrdiff_t i = s.indexOf(key ~ "=\"");
  if (i < 0) return("");
  i += key.length + 2;
  ptrdiff_t j = s.indexOf("\"", i);
  return(j > i ? s[i .. j] : "");
}

unittest {
  import danode.request : Request;
  import danode.filesystem : FileSystem;

  tag(Level.Always, "FILE", "%s", __FILE__);

  // extractQuoted
  assert(extractQuoted("name=\"hello\"", "name") == "hello", "extractQuoted must get name");
  assert(extractQuoted("filename=\"test.txt\"", "filename") == "test.txt", "extractQuoted must get filename");
  assert(extractQuoted("name=\"\"", "name") == "", "extractQuoted empty value");
  assert(extractQuoted("nothing here", "name") == "", "extractQuoted missing key");
  
  // Helper to build a multipart body
  string buildMultipart(string boundary, string[2][] textFields, string[3][] fileFields) {
    string body;
    foreach (f; textFields) {
      body ~= "--" ~ boundary ~ "\r\n";
      body ~= "Content-Disposition: form-data; name=\"" ~ f[0] ~ "\"\r\n\r\n";
      body ~= f[1] ~ "\r\n";
    }
    foreach (f; fileFields) {
      body ~= "--" ~ boundary ~ "\r\n";
      body ~= "Content-Disposition: form-data; name=\"" ~ f[0] ~ "\"; filename=\"" ~ f[1] ~ "\"\r\n";
      body ~= "Content-Type: application/octet-stream\r\n\r\n";
      body ~= f[2] ~ "\r\n";
    }
    body ~= "--" ~ boundary ~ "--\r\n";
    return body;
  }

  FileSystem fs = new FileSystem("./www/");
  string uploadDir = fs.localroot("localhost") ~ "/";
  string boundary = "testboundary123";

  // Test 1: single text field
  {
    Request r;
    r.id = md5UUID("test1");
    auto parser = MultipartParser("--" ~ boundary, uploadDir);
    string body = buildMultipart(boundary, [["name", "danny"]], []);
    bool result = parser.feed(r, body);
    assert(result, "single text field must complete");
  }

  // Test 2: single file upload
  {
    Request r;
    r.id = md5UUID("test2");
    auto parser = MultipartParser("--" ~ boundary, uploadDir);
    string body = buildMultipart(boundary, [], [["file", "test.txt", "hello world"]]);
    assert(parser.feed(r, body), "single file must complete");
    assert("file" in r.postinfo, "file must be in postinfo");
    assert(r.postinfo["file"].type == PostType.File, "must be File type");
    assert(r.postinfo["file"].filename == "test.txt", "filename must match");
    assert(r.postinfo["file"].size == "hello world".length, "size must match");
    // cleanup
    if (r.postinfo["file"].value.exists) remove(r.postinfo["file"].value);
  }

  // Test 3: mixed text + file
  {
    Request r;
    r.id = md5UUID("test3");
    auto parser = MultipartParser("--" ~ boundary, uploadDir);
    string body = buildMultipart(boundary, [["name", "danny"]], [["file", "data.bin", "binarydata"]]);
    assert(parser.feed(r, body), "mixed must complete");
    assert(r.postinfo["name"].value == "danny", "text field must parse");
    assert(r.postinfo["file"].type == PostType.File, "file field must parse");
    if (r.postinfo["file"].value.exists) remove(r.postinfo["file"].value);
  }

  // Test 4: cross-chunk boundary detection - feed 1 byte at a time
  {
    Request r;
    r.id = md5UUID("test4");
    auto parser = MultipartParser("--" ~ boundary, uploadDir);
    string body = buildMultipart(boundary, [["field", "value"]], []);
    bool done = false;
    foreach (i; 0 .. body.length) {
      done = parser.feed(r, body[i..i+1]);
      if (done) break;
    }
    assert(done, "byte-by-byte feed must complete");
  }

  // Test 5: binary file with = and \r\n in content
  {
    Request r;
    r.id = md5UUID("test5");
    auto parser = MultipartParser("--" ~ boundary, uploadDir);
    string binaryContent = "data=with=equals\r\nand newlines\r\nmore data";
    string body = buildMultipart(boundary, [], [["bin", "binary.bin", binaryContent]]);
    assert(parser.feed(r, body), "binary content must complete");
    assert(r.postinfo["bin"].size == binaryContent.length, "binary size must match");
    string written = cast(string) read(r.postinfo["bin"].value);
    assert(written == binaryContent, "binary content must be preserved exactly");
    if (r.postinfo["bin"].value.exists) remove(r.postinfo["bin"].value);
  }
}