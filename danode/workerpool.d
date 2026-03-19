/** danode/workerpool.d - Fixed thread pool: connection dispatch, per-IP tracking, worker lifecycle
  * License: GPLv3 (https://github.com/DannyArends/DaNode) - Danny Arends **/
module danode.workerpool;

import danode.imports;
import danode.client     : Client;
import danode.interfaces : DriverInterface;
import danode.router     : Router;
import danode.log        : log, error, Level;

immutable int MAX_CLIENTS = 2048;         /// Maximum number of queued connections before dropping
immutable int MAX_CLIENTS_PER_IP = 32;    /// Maximum concurrent connections per remote IP
immutable int POOL_SIZE = 200;            /// Number of pre-allocated worker threads

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
      foreach (i; 0 .. POOL_SIZE) {
        auto t = new Thread(&workerLoop, 256 * 1024);
        t.isDaemon = true;
        t.start();
        workers ~= t;
      }
      log(Level.Always, "WorkerPool started with %d threads", POOL_SIZE);
    }

    /* Enqueue a new connection driver for handling by the next available worker.
       Returns false if the connection should be rejected (rate limit or capacity exceeded). */
    bool push(DriverInterface driver, string ip, bool isLoopback) {
      synchronized(mutex) {
        if (!isLoopback && nAlivePerIP.get(ip, 0L) >= MAX_CLIENTS_PER_IP) return(false);
        if (queue.length >= MAX_CLIENTS) return(false);
        queue ~= driver;
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
      foreach (i; 0 .. POOL_SIZE) sem.notify();   // wake all workers to exit
      foreach (t; workers) t.join();
      log(Level.Always, "WorkerPool stopped");
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
          queue  = queue[1 .. $];
        }

        string ip = driver.ip;
        synchronized(mutex) { nAlivePerIP[ip]++; }
        try {
          auto client = new Client(router, driver);
          client.run();
        } catch(Exception e) { error("WorkerPool: Client exception [%s]: %s", ip, e.msg);
        } catch(Error e) { error("WorkerPool: Client error [%s]: %s",     ip, e.msg); }
        synchronized(mutex) {
          if (ip in nAlivePerIP && nAlivePerIP[ip] > 0) nAlivePerIP[ip]--;
          if (nAlivePerIP[ip] == 0) nAlivePerIP.remove(ip);
        }
      }
    }
}

