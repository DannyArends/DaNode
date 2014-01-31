module danode.jobrunner;

import std.stdio, std.string, std.datetime, std.file, core.thread;
import danode.structs, danode.helper, danode.jobs.finance;

void nop(ref Job j){ }

class JobRunner : core.thread.Thread {
  this(){ super(&run); }

  void run(){
    while(running){ Sleep(dur!("msecs")(150));
      for(size_t x = 0; x < jobs.length;x++){ with(jobs[x]){
        if(age() >= period && times != 0){ execute(x); }
        if(times == 0) removeJob(id);
      }}
    }
  }

  void execute(size_t x){ with(jobs[x]){
    log(format("Job executing: %s - %s [%s]", id, name, owner), "jobs.log");
    task(jobs[x]);
    if(times > 0) times--;
    t0 = now();
    executed++;
  }}

  void createJob(string name, JobFunc t=&nop, long sec=1, long n=-1, string owns="system",bool exec=false){
    jid++;
    Job j = Job(jid, name, owns, (sec * 1000), n, 0, now(), t);
    writefln("Created: %s - %s [%s] %s", jid, name, owns, exec);
    jobs ~= j;
    if(exec){ execute((jobs.length-1)); }
  }

  void removeJob(long jobId){
    Job[] njobs;
    for(size_t x = 0; x < jobs.length;x++){
      if(jobs[x].id != jobId){ 
        njobs ~= jobs[x]; 
      }else{
        completed ~= jobs[x];
      }
    }
    jobs = njobs;
  }

  @property size_t active_jobs(){ return jobs.length; }
  @property string jobs_overview(){ string s;
    s ~= "<h4>Job overview</h4>";
    s ~= format("%s completed, %s active jobs<br>", completed_jobs, active_jobs);
    s ~= "Active Jobs:<ul>";
    foreach(j; jobs){ s ~= j.asitem; }
    s ~= "</ul>Completed Jobs:<ul>";
    foreach(j; completed){ s ~= j.asitem; }
    s ~= "</ul>";
    return s;
  }
  @property size_t completed_jobs(){ return completed.length; }

  private:
    bool  running = true;
    long  jid = 0;
    Job[] jobs;
    Job[] completed;
}

