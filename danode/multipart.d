/** danode/server.d - Entry point: socket setup, connection acceptance, rate limiting
  * License: GPLv3 (https://github.com/DannyArends/DaNode) - Danny Arends **/
module danode.multipart;

import danode.imports;

import danode.request : Request;
import danode.post : PostItem, PostType;
import danode.log : log, tag, error, Level;

enum MPState { INIT, HEADER, BODY }

struct MultipartParser {
  string        boundary;       /// "--boundary"
  string        uploadDir;      /// directory for .up files
  MPState       state = MPState.INIT;
  char[]        tail;           /// leftover bytes from previous chunk (boundary detection)
  File          outfile;        /// current open output file
  string        currentPath;    /// current .up file path
  string        currentMime;    /// current part mime type
  string        currentName;    /// current field name
  string        currentFname;   /// current filename
  Appender!(char[]) hdrbuf;     /// accumulating part header bytes
  bool          done = false;   /// final boundary seen

  @property bool isActive() const { return boundary.length > 0; }

  bool feed(ref Request request, const(char)[] chunk) {
    // Prepend any leftover tail from previous chunk
    char[] data = tail ~ chunk;
    tail = [];

    while (data.length > 0 && !done) {
      final switch (state) {
        case MPState.INIT:          // Find opening boundary
          ptrdiff_t i = indexOf(data, boundary ~ "\r\n");
          if (i < 0) { tail = data.dup; return(false); }
          data = data[i + boundary.length + 2 .. $];
          state = MPState.HEADER;
          break;

        case MPState.HEADER:        // Accumulate until \r\n\r\n
          ptrdiff_t i = indexOf(data, "\r\n\r\n");
          if (i < 0) { hdrbuf.put(data); tail = []; return(false); }
          hdrbuf.put(data[0 .. i]);
          data = data[i + 4 .. $];
          // Parse headers
          parsePartHeader(request);
          hdrbuf.clear();
          state = MPState.BODY;
          break;

        case MPState.BODY:          // Look for \r\n--boundary
          string delim = "\r\n" ~ boundary;
          ptrdiff_t i = indexOf(data, delim);
          if (i < 0) { // No boundary found - write all but tail
            ptrdiff_t safe = cast(ptrdiff_t)data.length - cast(ptrdiff_t)delim.length;
            if (safe > 0) { writeChunk(data[0 .. safe]); data = data[safe .. $]; }
            tail = data.dup;
            return(false);
          }
          // Boundary found - write up to it and close part
          writeChunk(data[0 .. i]);
          closePart(request);
          data = data[i + delim.length .. $];
          // Check for final boundary (--)  or next part (\r\n)
          if (data.length >= 2 && data[0..2] == "--") { return(done = true); }
          if (data.length >= 2 && data[0..2] == "\r\n") { data = data[2..$]; }
          state = MPState.HEADER;
          break;
      }
    }
    return done;
  }

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
      try { outfile.rawWrite(chunk); }catch(Exception e) { error("MultipartParser: write failed: %s", e.msg); }
    }
  }

  private void closePart(ref Request request) {
    if (currentFname.length > 0) {
      if (outfile.isOpen()) outfile.close();
      long sz = currentPath.exists ? currentPath.getSize() : 0;
      request.postinfo[currentName] = PostItem(PostType.File, currentName, currentFname, currentPath, currentMime, sz);
      log(Level.Verbose, "MPART: [I] closed file %s, %d bytes", currentPath, sz);
      currentPath = ""; currentFname = ""; currentMime = "";
    } else if (currentName.length > 0) {  // Plain input field - body was accumulated in tail, store as value
      request.postinfo[currentName] = PostItem(PostType.Input, currentName, "", to!string(hdrbuf.data));
    }
    currentName = "";
  }
}

// Extract value from: name="value" or filename="value"
pure string extractQuoted(string s, string key) nothrow {
  ptrdiff_t i = s.indexOf(key ~ "=\"");
  if (i < 0) return "";
  i += key.length + 2;
  ptrdiff_t j = s.indexOf("\"", i);
  return j > i ? s[i .. j] : "";
}

unittest {
  tag(Level.Always, "FILE", "%s", __FILE__);

  // extractQuoted
  assert(extractQuoted("name=\"hello\"", "name") == "hello", "extractQuoted must get name");
  assert(extractQuoted("filename=\"test.txt\"", "filename") == "test.txt", "extractQuoted must get filename");
  assert(extractQuoted("name=\"\"", "name") == "", "extractQuoted empty value");
  assert(extractQuoted("nothing here", "name") == "", "extractQuoted missing key");
}
