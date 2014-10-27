#!rdmd -O
import std.stdio, std.compiler, std.datetime;
import api.danode;

alias core.thread.Thread.sleep  Sleep;

void main(string[] args){ setGET(args);
  Sleep(15.seconds);
}

