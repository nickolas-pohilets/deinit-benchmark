# deinit-benchmark

Performance cost of async deinit vs regular deinit is linear (about 500-700ns per object) for small number of objects, but after certain threshold (about 2K queued objects) starts to grow quadratically. I don't have a good explanation for this.

After replacing std::set<> with llvm::DesnseSet<> in TaskLocal::copyTo(), the cost of copying task-locals values when scheduling async deinit is now 35ns per value. Before that it was `O(n*log(n))` with numbers of about 50ns/value for 10 values, and 80ns/item for 1000 values.

Fast path of the isolated deinit has additional cost of about 20ns per object when (not) copying task-local values, and 30-35ns when (not) resetting task-local values. Benchmark deallocates large tree of objects isolated on the same actor. Only the root objects hops (slow path), the rest are released already on the correct actor (fast path). In copying scenario fast path does not touch task-locals at all, so it is faster. In the resetting scenario fast path does not insert a barrier node because task-locals are already empty after the hop, but checking if task-locals are empty apparently costs additional 10-15ns.

Slow path of the isolated deinit with reseting task-local values costs about 130ns



