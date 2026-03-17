#!/usr/bin/env rdmd
import std.stdio;
import core.thread;

void main() {
    writeln("Content-Type: text/event-stream");
    writeln("Cache-Control: no-cache");
    writeln("Connection: keep-alive");
    writeln();
    foreach (i; 0 .. 10) {
        writefln("data: tick %d\n", i);
        stdout.flush();
        Thread.sleep(dur!"seconds"(1));
    }
}

