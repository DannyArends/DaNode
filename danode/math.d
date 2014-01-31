module danode.math;

import std.stdio, std.conv : to;

pure T mean(T)(in T[] r){ 
  T mean = cast(T)0;
  foreach(int i, T e;r){ mean += (e - mean) / (i + 1); } 
  return mean; 
}

pure T var(T)(in T[] r){ return (ss!T(r)/(r.length-1)); }
pure T sd(T)(in T[] r){ return sqrt(var!T(r)); }

pure T ss(T)(in T[] r){
  T mean = mean(r);
  T sumofsquares = 0;
  foreach(e;r){ sumofsquares += (e - mean)^^2; }
  return sumofsquares;
}

