import std.stdio;
import core.thread;

void main() {
  writeln("Content-Type: text/event-stream");
  writeln("Cache-Control: no-cache");
  writeln();
  foreach (i; 0 .. 3) {
    writefln("data: tick %d\n", i);
    stdout.flush();
    Thread.sleep(dur!"msecs"(100));
  }
}

