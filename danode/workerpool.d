/** danode/workerpool.d - Fixed thread pool: connection dispatch, per-IP tracking, worker lifecycle
  * License: GPLv3 (https://github.com/DannyArends/DaNode) - Danny Arends **/
module danode.workerpool;

import danode.imports;
import danode.client     : Client;
import danode.interfaces : DriverInterface;
import danode.router     : Router;
import danode.log        : log, error, Level;

immutable int MAX_CLIENTS = 2048;
immutable int MAX_CLIENTS_PER_IP = 32;
immutable int POOL_SIZE = 200;

class WorkerPool {
  private:
    Router            router;
    Thread[]          workers;
    DriverInterface[] queue;
    Mutex             mutex;
    Semaphore         sem;
    bool              stopped;

  public:
    long[string]      nAlivePerIP;   // protected by mutex

    this(Router router) {
      this.router  = router;
      this.mutex   = new Mutex();
      this.sem     = new Semaphore(0);
      foreach (i; 0 .. POOL_SIZE) {
        auto t = new Thread(&workerLoop, 256 * 1024);
        t.isDaemon = true;
        t.start();
        workers ~= t;
      }
      log(Level.Always, "WorkerPool started with %d threads", POOL_SIZE);
    }

    bool push(DriverInterface driver, string ip, bool isLoopback) {
      synchronized(mutex) {
        if (!isLoopback && nAlivePerIP.get(ip, 0L) >= MAX_CLIENTS_PER_IP) return(false);
        if (queue.length >= MAX_CLIENTS) return(false);
        queue ~= driver;
      }
      sem.notify();
      return true;
    }

    @property long nAlive() { synchronized(mutex) { return nAlivePerIP.byValue.sum; } }
    @property long queued() { synchronized(mutex) { return queue.length; } }
    void scan() { router.scan(); }


    void stop() {
      synchronized(mutex) { stopped = true; }
      foreach (i; 0 .. POOL_SIZE) sem.notify();   // wake all workers to exit
      foreach (t; workers) t.join();
      log(Level.Always, "WorkerPool stopped");
    }

  private:
    void workerLoop() {
      while (true) {
        sem.wait();

        DriverInterface driver;
        synchronized(mutex) {
          if (stopped) return;
          if (queue.length == 0) continue;   // spurious notify from stop()
          driver = queue[0];
          queue  = queue[1 .. $];
        }

        string ip = driver.ip;
        synchronized(mutex) { nAlivePerIP[ip]++; }
        try {
          auto client = new Client(router, driver);
          client.run();
        } catch(Exception e) { error("WorkerPool: client exception [%s]: %s", ip, e.msg);
        } catch(Error e) { error("WorkerPool: client error [%s]: %s",     ip, e.msg); }
        synchronized(mutex) {
          if (ip in nAlivePerIP && nAlivePerIP[ip] > 0) nAlivePerIP[ip]--;
          if (nAlivePerIP[ip] == 0) nAlivePerIP.remove(ip);
        }
      }
    }
}
