#!rdmd -O
import std.stdio, std.compiler, std.datetime;
import core.thread : Thread;
import api.danode;

void main(string[] args){ setGET(args);
  Thread.sleep(dur!"seconds"(12));
}

