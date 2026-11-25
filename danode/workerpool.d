/** danode/workerpool.d - Fixed thread pool: connection dispatch, per-IP tracking, worker lifecycle
  * License: GPLv3 (https://github.com/DannyArends/DaNode) - Danny Arends **/
module danode.workerpool;

import danode.imports;
import danode.client : Client;
import danode.interfaces : DriverInterface;
import danode.router : Router;
import danode.log : log, error, Level;
import danode.webconfig : serverConfig;

class WorkerPool {
  private:
    Router            router;         /// Shared router instance passed to each Client
    Thread[]          workers;        /// Fixed array of pre-allocated worker threads
    Mutex             mutex;          /// Guards queue, stopped, and nAlivePerIP
    DriverInterface[] queue;          /// Pending connection queue, protected by mutex
    long[string]      nAlivePerIP;    /// Active connection count per remote IP, protected by mutex
    bool              stopped;        /// Set to true on shutdown; workers exit their loop when seen
    Semaphore         sem;            /// Counts pending items in queue; workers block on wait()

  public:
    this(Router router) {
      this.router  = router;
      this.mutex   = new Mutex();
      this.sem     = new Semaphore(0);
      foreach (i; 0 .. serverConfig.get("pool_size", 200)) {
        auto t = new Thread(&workerLoop, 256 * 1024);
        t.isDaemon = true;
        t.start();
        workers ~= t;
      }
      log(Level.Always, "WorkerPool started with %d threads", serverConfig.get("pool_size", 200));
    }

    /* Enqueue a new connection driver for handling by the next available worker.
       Returns false if the connection should be rejected (rate limit or capacity exceeded). */
    bool push(DriverInterface driver, string ip, bool isLoopback) {
      synchronized(mutex) {
        if (!isLoopback && nAlivePerIP.get(ip, 0L) >= serverConfig.get("max_clients_per_ip", 32)) return(false);
        if (queue.length >= serverConfig.get("max_clients", 2048)) return(false);
        queue ~= driver;
        nAlivePerIP[ip]++;
      }
      sem.notify();
      return true;
    }

    // Total number of connections currently being handled across all workers
    @property long nAlive() { synchronized(mutex) { return(nAlivePerIP.byValue.sum); } }

    // Number of connections waiting in the queue for a free worker
    @property long queued() { synchronized(mutex) { return(queue.length); } }

    // Trigger a filesystem rescan on the router (called by the server)
    void scan() { router.scan(); }

    // Signal all workers to exit and join them
    void stop() {
      synchronized(mutex) { if (stopped) { return; } stopped = true; }
      foreach (i; 0 .. workers.length) sem.notify();   // wake all workers to exit
      foreach (t; workers) t.join();
      log(Level.Trace, "WorkerPool stopped");
    }

  private:
    // Worker thread body: blocks on semaphore, dequeues one connection, runs it to completion.
    void workerLoop() {
      while (true) {
        sem.wait();

        DriverInterface driver;
        synchronized(mutex) {
          if (stopped) return;
          if (queue.length == 0) continue;   // spurious notify from stop()
          driver = queue[0];
          queue = queue[1 .. $];
        }
        try {
          auto client = new Client(router, driver);
          client.run();
          client.destroy();
        } catch(Exception e) { error("WorkerPool: Client exception [%s]: %s", driver.ip, e.msg);
        } catch(Error e) { error("WorkerPool: Client error [%s]: %s",     driver.ip, e.msg); }
        synchronized(mutex) { if (auto n = driver.ip in nAlivePerIP) { if (--(*n) <= 0) nAlivePerIP.remove(driver.ip); } }
        driver = null;
        if (GC.stats().usedSize > 32 * 1_048_576) { GC.collect(); GC.minimize(); }
      }
    }
}

unittest {
  import danode.interfaces : StringDriver;
  import danode.log : tag;
  tag(Level.Always, "FILE", "%s", __FILE__);
  auto pool = new WorkerPool(new Router("./www/", Address.init));
  assert(pool.push(new StringDriver("GET /test.txt HTTP/1.1\nHost: localhost\n\n"), "0.0.0.0", false), "push must accept");
  foreach (_; 0 .. 200) { if (pool.nAlive == 0) break; Thread.sleep(10.msecs); }
  assert(pool.nAlive == 0, "per-IP count must drop to 0 once the client finishes");
  pool.stop();
}

