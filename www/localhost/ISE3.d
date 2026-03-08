import std.datetime : dur, msecs;
import core.thread : Thread;

void main() {
  while (true) {
    Thread.sleep(dur!"msecs"(10));
  }
}

