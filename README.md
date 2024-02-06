# deinit-benchmark

## Summary

Performance cost of async deinit vs regular deinit is linear (about 500-700ns per object) for small number of objects, but after certain threshold (about 2K queued objects) starts to grow quadratically. I don't have a good explanation for this.

After replacing std::set<> with llvm::DesnseSet<> in TaskLocal::copyTo(), the cost of copying task-locals values when scheduling async deinit is now 35ns per value. Before that it was `O(n*log(n))` with numbers of about 50ns/value for 10 values, and 80ns/item for 1000 values.

Fast path of the isolated deinit has additional cost of about 20ns per object when (not) copying task-local values, and 30-35ns when (not) resetting task-local values. Benchmark deallocates large tree of objects isolated on the same actor. Only the root objects hops (slow path), the rest are released already on the correct actor (fast path). In copying scenario fast path does not touch task-locals at all, so it is faster. In the resetting scenario fast path does not insert a barrier node because task-locals are already empty after the hop, but checking if task-locals are empty apparently costs additional 10-15ns.

Slow path of the isolated deinit with resetting task-local values costs about 140ns

## Experiments

### Setup

#### [deinit-benchmark.swift](./deinit-benchmark.swift)

Source code of the benchmark driver.

#### [run-benchmark.sh](./run-benchmark.sh)

Wrapper script which compiles, codesigns, and runs benchmark driver with appropriate runtime libraries.

```shell
$ ./run-benchmark.sh --help
Usage: deinit-benchmark BENCHMARK_NAME INPUTS_FILE [--ballast=N]
```

Benchmark driver measures specified benchmark for numbers of task-local values and objects given in `INPUTS_FILE`.
Using shared inputs allows results of different runs to be comparable between each other.

Two times are being reported:

* **Scheduling** - how long was the thread initiating destruction blocked.
* **Total** - time from initiating destruction, to the completion of the deinit body of the last object.

Benchmark driver outputs results to stdout, with a header recording parameters and showing column names:

```
# isolated_hop_copy_tree data/inputs-5K.txt --ballast=0
#
# schedule(ns) total(ns)
6584	8269500
5750	13276667
6000	4129208
...
```

For benchmarks where no hopping occurs, these two times should be almost identical.

Benchmarks come in array and tree variants. Array variants allow to cleanly measure costs of scheduling, while tree variants attempt to better mimic real-world scenarios.

All benchmarks use a single strong reference as a task-local value.

#### [gen-points.py](./gen-points.py)

This utility script can be used to generate inputs of desired configuration:
```shell
$ ./gen-points.py --help
usage: gen-points.py [-h] [-v MIN:MAX] [-o MIN:MAX] points

positional arguments:
  points

options:
  -h, --help            show this help message and exit
  -v MIN:MAX, --values MIN:MAX
                        Range of number of task-local values (default: 0:200)
  -o MIN:MAX, --objects MIN:MAX
                        Range of number of objects (default: 1:5000)

$ ./gen-points.py 1000 > data/inputs-1K.txt
$ ./gen-points.py 5000 > data/inputs-5K.txt 
```

Ranges are interpreted as closed intervals. It is possible to specify `MIN`=`MAX` to pin parameter to a specific value.
Otherwise values are generated randomly with linear distribution.

#### [regression.py](./regression.py)

Script for analyzing benchmark results by attempting to perform multi-variable linear regression:

```shell
$ ./regression.py --help
usage: regression.py [-h] [-d BASELINE] [-p PARAMS] [-y PHASES] [--min-values MIN_VALUES] [--max-values MAX_VALUES] [--min-objects MIN_OBJECTS] [--max-objects MAX_OBJECTS]
                     inputs dataset

positional arguments:
  inputs
  dataset

options:
  -h, --help            show this help message and exit
  -d BASELINE, --diff BASELINE
                        Apply regression to difference between dataset and baseline (default: None)
  -p PARAMS, --params PARAMS
                        Parameters for fit against. Comma-separated list of vo2,vo,v,o2,o,1 (default: vo,v,o,1)
  -y PHASES, --phases PHASES
                        Values for fit against. Comma-separated list of S,T - Scheduling, Total (default: S,T)
  --min-values MIN_VALUES
  --max-values MAX_VALUES
  --min-objects MIN_OBJECTS
  --max-objects MAX_OBJECTS
```

By default it attempts to fit the data against all possible parameters, and may produce overfitting models.
It is often helpful to manually limit parameters. E.g. `./regression.py dataset -p vo` will perform linear regression assuming costs are proportional to number of task-local **v**alues times number of **o**bjects.

Additionally it is possible to filter phases being analyzed. `./regression.py dataset -y T -p vo` will show only results for the **Total** phase.

To isolate incremental cost of new features, it is possible to perform regression against difference of two datasets. Baseline dataset can be specified using `--diff` parameter.

### Isolated deinit

#### 0. Baseline

```shell
$ ./run-benchmark.sh data/inputs-5K.txt nonisolated_array > data/nonisolated_array-5K.txt
$ ./run-benchmark.sh data/inputs-5K.txt nonisolated_tree > data/nonisolated_tree-5K.txt
$ ./regression.py data/inputs-5K.txt data/nonisolated_array-5K.txt -p o -y T
Total: 64⋅o, R² = 0.9950, Adjusted R² = 0.9950
$ ./regression.py data/inputs-5K.txt data/nonisolated_tree-5K.txt -p o -y T
Total: 63⋅o, R² = 0.6515, Adjusted R² = 0.6515
```

Deinitializing objects with regular deinit costs about 64ns. Of course, this varies depending on the stored properties and body of the `deinit`,
but this number is useful as a baseline for other benchmarks, which all have the same stored properties and `deinit` body.

#### 1. Fast path - copy

```shell
$ ./run-benchmark.sh data/inputs-5K.txt isolated_no_hop_copy_array > data/isolated_no_hop_copy_array-5K.txt
$ ./run-benchmark.sh data/inputs-5K.txt isolated_no_hop_copy_tree > data/isolated_no_hop_copy_tree-5K.txt
```

When copying (not resetting) task-local values, performance of the fast path of the isolated deinit does not depend on number of task-local values,
and costs about 16ns per object for array case and 18ns per object for tree case. Despite low R² for tree case, results are reproducible. The origin of the 2ns difference is not clear.

```shell
$ ./regression.py data/inputs-5K.txt data/isolated_no_hop_copy_array-5K.txt --diff data/nonisolated_array-5K.txt -p o -y T
Total: 16⋅o, R² = 0.8352, Adjusted R² = 0.8351
$ ./regression.py data/inputs-5K.txt data/isolated_no_hop_copy_tree-5K.txt --diff data/nonisolated_tree-5K.txt -p o -y T
Total: 18⋅o, R² = 0.1261, Adjusted R² = 0.1260
```

#### 2. Fast path - reset

```shell
$ ./run-benchmark.sh data/inputs-5K.txt isolated_no_hop_reset_array > data/isolated_no_hop_reset_array-5K.txt
$ ./run-benchmark.sh data/inputs-5K.txt isolated_no_hop_reset_tree > data/isolated_no_hop_reset_tree-5K.txt
```

When resetting task-local values, performance of the fast path of the isolated deinit also does not depend on number of task-local values, but costs per object are higher - 36ns for array case and 41ns for tree case. The 5ns difference between cases is reproducible, but its origin is not clear.

Extra work needed to reset task-local values is about 20ns per object.

```shell
$ ./regression.py data/inputs-5K.txt data/isolated_no_hop_reset_array-5K.txt --diff data/nonisolated_array-5K.txt -p o -y T
Total: 36⋅o, R² = 0.9446, Adjusted R² = 0.9446
$ ./regression.py data/inputs-5K.txt data/isolated_no_hop_reset_tree-5K.txt --diff data/nonisolated_tree-5K.txt -p o -y T
Total: 41⋅o, R² = 0.4243, Adjusted R² = 0.4242
```

#### 3. Slow path - reset

#### 3.1. Array

```shell
$ ./run-benchmark.sh data/inputs-5K.txt isolated_hop_reset_array > data/isolated_hop_reset_array-5K.txt
```

To interpret benchmark results we need to understand interaction between enqueueing and dequeueing tasks:

```shell
$ ./regression.py data/inputs-5K.txt data/isolated_hop_reset_array-5K.txt -p o   
Scheduling: 117⋅o, R² = 0.5794, Adjusted R² = 0.5793
Total     : 195⋅o, R² = 0.7279, Adjusted R² = 0.7278
```

Since total execution time is significantly larger then scheduling time, we can assume that draining the actor queue is happening slower then enqueueing.
Most of the time, actor queue is non-empty, and enqueueing and draining happens in parallel. Draining thread is not waiting for the enqueueing thread.

Measurements are quite noisy. Repeated benchmarks give slightly different values. Let's take enqueueing cost to be about 115ns.
```shell
$ ./regression.py data/inputs-5K.txt data/isolated_hop_reset_array-5K-2.txt -y S -p o
Scheduling: 108⋅o, R² = 0.6572, Adjusted R² = 0.6572
$ ./regression.py data/inputs-5K.txt data/isolated_hop_reset_array-5K-3.txt -y S -p o
Scheduling: 123⋅o, R² = 0.6173, Adjusted R² = 0.6172
$ ./regression.py data/inputs-5K.txt data/isolated_hop_reset_array-5K-4.txt -y S -p o
Scheduling: 124⋅o, R² = 0.5400, Adjusted R² = 0.5399
$ ./regression.py data/inputs-5K.txt data/isolated_hop_reset_array-5K-5.txt -y S -p o
Scheduling: 107⋅o, R² = 0.5702, Adjusted R² = 0.5702
```

And let's take additional cost of the dequeueing is about 140ns.

```shell
$ ./regression.py data/inputs-5K.txt data/isolated_hop_reset_array-5K.txt --diff data/nonisolated_array-5K.txt -y T -p o 
Total: 130⋅o, R² = 0.5423, Adjusted R² = 0.5422
$ ./regression.py data/inputs-5K.txt data/isolated_hop_reset_array-5K-2.txt --diff data/nonisolated_array-5K.txt -y T -p o
Total: 125⋅o, R² = 0.6572, Adjusted R² = 0.6572
$ ./regression.py data/inputs-5K.txt data/isolated_hop_reset_array-5K-3.txt --diff data/nonisolated_array-5K.txt -y T -p o
Total: 160⋅o, R² = 0.6471, Adjusted R² = 0.6470
$ ./regression.py data/inputs-5K.txt data/isolated_hop_reset_array-5K-4.txt --diff data/nonisolated_array-5K.txt -y T -p o
Total: 140⋅o, R² = 0.4657, Adjusted R² = 0.4656
$ ./regression.py data/inputs-5K.txt data/isolated_hop_reset_array-5K-5.txt --diff data/nonisolated_array-5K.txt -y T -p o
Total: 154⋅o, R² = 0.5977, Adjusted R² = 0.5976
```

#### 3.2. Tree

```shell
$ ./run-benchmark.sh data/inputs-5K.txt isolated_hop_reset_array > data/isolated_hop_reset_array-5K.txt
```

If entire tree is isolated to the same actor, hopping happens only for the root node.
Rest of the nodes behave as fast path with resetting, and should have similar performance.

```shell
$ ./regression.py data/inputs-5K.txt data/isolated_hop_reset_tree-5K.txt -p o,1                                           
Scheduling:   0⋅o  + 2159, R² = 0.0112, Adjusted R² = 0.0108
Total     : 115⋅o + 11683, R² = 0.8585, Adjusted R² = 0.8584
$ ./regression.py data/inputs-5K.txt data/isolated_hop_reset_tree-5K.txt --diff data/isolated_no_hop_reset_tree-5K.txt -y T -p o                    
Total: 14⋅o, R² = 0.0287, Adjusted R² = 0.0285
$ ./regression.py data/inputs-5K.txt data/isolated_hop_reset_tree-5K.txt --diff data/isolated_no_hop_reset_tree-5K.txt -y T -p o,1
Total: 10⋅o + 14482, R² = 0.0396, Adjusted R² = 0.0392
```

Scheduling of the root node triggers actor transition from `Idle` into `Scheduled` state and scheduling of actor processing job, which has a relatively large constant cost of about 2-2.5μs.

There is also small and noisy difference in per-object costs compared to the fast path. Origin of this difference is not clear.

To benchmark hopping per each node of the tree, we need to construct a tree where each node has a different isolation than the parent. Using only two actors, we end up with a tree where even layers are isolated to one actor, and odd layers to another.

```shell
$ ./run-benchmark.sh data/inputs-5K.txt isolated_hop_reset_tree_interleaved > data/isolated_hop_reset_tree_interleaved-5K.txt
```

Both actors perform enqueueing (to another one's queue) and dequeueing, so total amount of work should be approximately equal
to the sum of `Scheduling` and `Total` times from slow path array case.

But this work is distributed between two actors, and the actor which finishes its jobs last determines the reported time.
In the best case scenario, both actors do equal amounts of work, and finish in half the time of the array case.
In the worst case scenario, one of the actors does twice the amount of work of another, and both actors finish in about ⅔ of the time of the array case.

```shell
$ ./regression.py data/inputs-5K.txt data/isolated_hop_reset_tree_interleaved-5K.txt -p o  
Scheduling:   1⋅o, R² = -0.4648, Adjusted R² = -0.4651
Total     : 169⋅o, R² =  0.8082, Adjusted R² =  0.8081
$ ./regression.py data/inputs-5K.txt data/isolated_hop_reset_tree_interleaved-5K.txt -p o,1
Scheduling:  -0⋅o  + 1745, R² = 0.0001, Adjusted R² = -0.0003
Total     : 163⋅o + 18001, R² = 0.8093, Adjusted R² =  0.8093
```

```
169 / (117 + 195) ≈ 54%
163 / (117 + 195) ≈ 52%
```

Constant cost of scheduling is consistent with the non-interleaved tree benchmark, and per object costs are within expected range.

#### 4. Slow path - copy

#### 4.1. Array

```shell
$ ./run-benchmark.sh data/inputs-5K.txt isolated_hop_copy_array > data/isolated_hop_copy_array-5K.txt
$ ./regression.py data/inputs-5K.txt data/isolated_hop_copy_array-5K.txt -p vo,o
Scheduling: 32⋅v⋅o + 486⋅o, R² = 0.9680, Adjusted R² = 0.9680
Total     : 32⋅v⋅o + 492⋅o, R² = 0.9677, Adjusted R² = 0.9677
```

Copying task-local values increases cost of scheduling and changes dynamics between enqueueing and dequeueing.
With enqueueing being slower, queue remains empty most of the time and dequeueing thread is waiting for the enqueueing one.
It is not possible to measure costs of execution in this mode of operation.
To make them visible, we can make dequeueing slower by adding ballast to the deinit body.
A dummy call to `arc4random()` is used as a ballast. It cannot be optimized away by the compiler, and takes amount of time comparable to values being measured.

We can verify that amount of ballast is sufficient by zooming in on the subset of data with high number of task-local values:

```shell
$ ./run-benchmark.sh data/inputs-5K.txt isolated_hop_copy_array --ballast=80 > data/isolated_hop_copy_array-b80-5K.txt
$ ./regression.py data/inputs-5K.txt data/isolated_hop_copy_array-b80-5K.txt -p vo,o --min-values=180
Scheduling: 32⋅v⋅o + 486⋅o, R² = 0.9680, Adjusted R² = 0.9680
Total     : 32⋅v⋅o + 492⋅o, R² = 0.9677, Adjusted R² = 0.9677
$ ./run-benchmark.sh data/inputs-5K.txt isolated_hop_copy_array --ballast=100 > data/isolated_hop_copy_array-b100-5K.txt
$ ./regression.py data/inputs-5K.txt data/isolated_hop_copy_array-b100-5K.txt -p vo,o --min-values=180               
Scheduling: 21⋅v⋅o + 2000⋅o, R² = 0.9905, Adjusted R² = 0.9905
Total     : 17⋅v⋅o + 4259⋅o, R² = 0.9909, Adjusted R² = 0.9909
```

Zooming out to the entire dataset we can see that copying 1 task-local value costs about 30-35ns when scheduling and about 20ns when executing isolated deinit:
```shell
$  ./regression.py data/inputs-5K.txt data/isolated_hop_copy_array-b100-5K.txt -p vo,o                 
Scheduling: 31⋅v⋅o   + 38⋅o, R² = 0.9948, Adjusted R² = 0.9948
Total     : 19⋅v⋅o + 3987⋅o, R² = 0.9947, Adjusted R² = 0.9947
```

To better isolate cost of the task-local values we can generate dataset with reset task-local values with the same ballast and examine the difference:
```shell
$ ./run-benchmark.sh data/inputs-5K.txt isolated_hop_reset_array --ballast=100 > data/isolated_hop_reset_array-b100-5K.txt
$ ./regression.py data/inputs-5K.txt data/isolated_hop_reset_array-b100-5K.txt -p vo,o 
Scheduling: 0⋅v⋅o   + 62⋅o, R² = 0.9905, Adjusted R² = 0.9905
Total     : 0⋅v⋅o + 3901⋅o, R² = 0.9994, Adjusted R² = 0.9994
$ ./regression.py data/inputs-5K.txt data/isolated_hop_copy_array-b100-5K.txt --diff data/isolated_hop_reset_array-b100-5K.txt -p vo,o 
Scheduling: 31⋅v⋅o - 23⋅o, R² = 0.9947, Adjusted R² = 0.9947
Total     : 19⋅v⋅o + 85⋅o, R² = 0.9765, Adjusted R² = 0.9765
$ ./regression.py data/inputs-5K.txt data/isolated_hop_copy_array-b100-5K.txt --diff data/isolated_hop_reset_array-b100-5K.txt -p vo   
Scheduling: 31⋅v⋅o, R² = 0.9946, Adjusted R² = 0.9946
Total     : 20⋅v⋅o, R² = 0.9757, Adjusted R² = 0.9757
```

To clarify if copying task-local values incurs addition per-object code, we can benchmark with number of task-local values set to 0 and to 1:

```shell
$ ./run-benchmark.sh data/inputs-5K-0-values.txt isolated_hop_reset_array --ballast=5 > data/isolated_hop_reset_array-b5-v0-5K.txt
$ ./run-benchmark.sh data/inputs-5K-0-values.txt isolated_hop_copy_array --ballast=5 > data/isolated_hop_copy_array-b5-v0-5K.txt
$ ./run-benchmark.sh data/inputs-5K-1-value.txt isolated_hop_reset_array --ballast=5 > data/isolated_hop_reset_array-b5-v1-5K.txt 
$ ./run-benchmark.sh data/inputs-5K-1-value.txt isolated_hop_copy_array --ballast=5 > data/isolated_hop_copy_array-b5-v1-5K.txt 
$ ./regression.py data/inputs-5K-0-values.txt data/isolated_hop_copy_array-b5-v0-5K.txt --diff data/isolated_hop_reset_array-b5-v0-5K.txt -p o 
Scheduling: 3⋅o, R² = 0.0056, Adjusted R² =  0.0054
Total     : 1⋅o, R² = 0.0000, Adjusted R² = -0.0002
$ ./regression.py data/inputs-5K-1-value.txt data/isolated_hop_copy_array-b5-v1-5K.txt --diff data/isolated_hop_reset_array-b5-v1-5K.txt -p o
Scheduling: 97⋅o, R² = 0.5710, Adjusted R² = 0.5709
Total     : 31⋅o, R² = 0.1053, Adjusted R² = 0.1051
```

Enabling copying task-local values, without any values to copy does not incur additional costs, but copying the first task-local value comes with additional cost of about 60-65ns per object for scheduling. Total time measurements are too noisy to draw any useful conclusions.

![Cost of copying task-local values in slow path of isolated deinit using array of objects](img/isolated_copy_array.png)

#### 4.2. Tree

### Async deinit

First let's validate that performance of async deinit without copying task-local values does not depend on the number of task-local values.

Two benchmarks can be used for this:
* `async_tree` - deallocates a binary tree of given size
* `async_array` - deallocates a array of objects

We fix range of number objects to a fixed value, and let number of task-local values be selected randomly from a linear distribution.
Benchmark is repeated for 3 different values of number of objects.


```shell
$ ./run-benchmark.sh async_tree --values=1:200 --objects=100:100 --points=1000 > data/async_tree-vs-values-100.txt 
$ ./run-benchmark.sh async_tree --values=1:200 --objects=1000:1000 --points=1000 > data/async_tree-vs-values-1000.txt
$ ./run-benchmark.sh async_tree --values=1:200 --objects=5000:5000 --points=1000 > data/async_tree-vs-values-5000.txt
$ ./run-benchmark.sh async_array --values=1:200 --objects=100:100 --points=1000 > data/async_array-vs-values-100.txt 
$ ./run-benchmark.sh async_array --values=1:200 --objects=1000:1000 --points=1000 > data/async_array-vs-values-1000.txt
$ ./run-benchmark.sh async_array --values=1:200 --objects=5000:5000 --points=1000 > data/async_array-vs-values-5000.txt
```

Plotting results shows pretty much horizontal lines. For easier comparison durations are normalized per number of objects.

![async deinit of a tree vs number of task-local values](img/async_tree-vs-values.png)
![async deinit of an array vs number of task-local values](img/async_array-vs-values.png)

And attempting to perform regression against number of task-local values gives rubbish R².

```shell
$ ./regression.py data/async_tree-vs-values-100.txt -p v,1 
Scheduling: 0.14720034717678354⋅v + -4884.234931270247, R² = 0.0000, Adjusted R² = -0.0020
Execution :  -23.699491793629342⋅v + 54000.76281262156, R² = 0.0209, Adjusted R² =  0.0189
Total     :  -23.552291446452447⋅v + 49116.52788135131, R² = 0.0224, Adjusted R² =  0.0205
$ ./regression.py data/async_tree-vs-values-1000.txt -p v,1
Scheduling:  -3.753269983170878⋅v + -58393.73801655156, R² = 0.0026, Adjusted R² =  0.0006
Execution :  -7.547297728769095⋅v + 403978.00344176096, R² = 0.0002, Adjusted R² = -0.0018
Total     : -11.300567711939745⋅v + 345584.26542520936, R² = 0.0004, Adjusted R² = -0.0016
$ ./regression.py data/async_tree-vs-values-5000.txt -p v,1
Scheduling:   3.450078413374252⋅v + -307342.51929036854, R² = 0.0002, Adjusted R² = -0.0019
Execution : -0.23145246290276794⋅v + 1934989.0708021887, R² = 0.0000, Adjusted R² = -0.0020
Total     :    3.218625950471484⋅v + 1627646.5515118204, R² = 0.0000, Adjusted R² = -0.0020
$ ./regression.py data/async_array-vs-values-100.txt -p v,1
Scheduling: 2.4317184474247444⋅v + 14124.10763059641, R² = 0.0003, Adjusted R² = -0.0017
Execution : 7.186227269560555⋅v + 30009.201698502035, R² = 0.0027, Adjusted R² =  0.0007
Total     :  9.617945716985414⋅v + 44133.30932909846, R² = 0.0027, Adjusted R² =  0.0007
$ ./regression.py data/async_tree-vs-values-1000.txt -p v,1
Scheduling:  -3.753269983170878⋅v + -58393.73801655156, R² = 0.0026, Adjusted R² =  0.0006
Execution :  -7.547297728769095⋅v + 403978.00344176096, R² = 0.0002, Adjusted R² = -0.0018
Total     : -11.300567711939745⋅v + 345584.26542520936, R² = 0.0004, Adjusted R² = -0.0016
$ ./regression.py data/async_tree-vs-values-5000.txt -p v,1
Scheduling:   3.450078413374252⋅v + -307342.51929036854, R² = 0.0002, Adjusted R² = -0.0019
Execution : -0.23145246290276794⋅v + 1934989.0708021887, R² = 0.0000, Adjusted R² = -0.0020
Total     :    3.218625950471484⋅v + 1627646.5515118204, R² = 0.0000, Adjusted R² = -0.0020
```

Note that scheduling deallocation of the root of a tree is faster then deallocating entire tree, because only 1 objects needs to be scheduled. This shows that async deinit can be used to unblock thread of last release faster at the cost of slower deallocation in another task.

Now we can analyze performance of async deinit depending only on number of objects:

```shell
$ ./run-benchmark.sh async_tree --values=1:1 --objects=100:50000 --points=1000 > data/async_tree-vs-objects.txt 
$ ./run-benchmark.sh async_array --values=1:1 --objects=100:50000 --points=1000 > data/async_array-vs-objects.txt
```

![async deinit vs number of objects](img/async-vs-objects.png)

```shell
$ ./regression.py data/async_tree-vs-objects.txt -p o,1
Scheduling: -62.03628799124445⋅o + 1319.8175314705481, R² = 0.9964, Adjusted R² = 0.9964
Execution :  502.1604231178307⋅o + -684561.5415930031, R² = 0.9848, Adjusted R² = 0.9848
Total     : 440.12413512658634⋅o + -683241.7240615345, R² = 0.9805, Adjusted R² = 0.9804
$ ./regression.py data/async_array-vs-objects.txt -p o,1
Scheduling:   341.9412867451418⋅o + -75775.4954550333, R² = 0.8212, Adjusted R² = 0.8209
Execution :  85.31886018727057⋅o + -94431.03322500603, R² = 0.9329, Adjusted R² = 0.9328
Total     : 427.26014693241245⋅o + -170206.5286800412, R² = 0.8768, Adjusted R² = 0.8766
```

This shows that total cost of async deinit is linear in number of objects, costing about 400ns extra per object. The `async_array` benchmark shows that most of the time is spent in scheduling task for async deinit. The `async_tree` is not indicative, because measured scheduling time includes only scheduling destruction of the root object. Scheduling destruction of the child nodes is included in the "Execution".

### Copying task-local values in async deinit

#### Array

```shell
$ ./run-benchmark.sh async_copy_array --values=1:200 --objects=100:50000 --points=1000 > data/async_copy_array.txt 
```

![cost of copying task-locals in async deinit of array of objects](img/async_copy_array.png)

```shell
$ ./regression.py data/async_copy_array.txt -p vo,o  
Scheduling:   24.984413687185803⋅v⋅o + 169.55852433924048⋅o, R² = 0.9952, Adjusted R² = 0.9952
Execution : 0.003699444311821941⋅v⋅o + -80.34199529218753⋅o, R² = 0.9667, Adjusted R² = 0.9666
Total     :    24.988113131497613⋅v⋅o + 89.21652904705317⋅o, R² = 0.9951, Adjusted R² = 0.9951
./regression.py data/async_copy_array.txt -y S,T -p vo                                                                                
Scheduling: 26.264204261611525⋅v⋅o, R² = 0.9933, Adjusted R² = 0.9933
Total     : 25.661499936450927⋅v⋅o, R² = 0.9946, Adjusted R² = 0.9946
```

When scheduling async deinit, it costs about 25ns to copy a task-local value. Data is too noisy to determine if there is a per-object cost independent of number of task-local values.

Surprisingly there seems to be linear dependency between execution time and number of objects. Each extra object **decreases** execution time by 80ns. That's a very surprising effect, for which I don't have an explanation yet.

#### Tree

```shell
$ ./run-benchmark.sh async_copy_tree --values=1:200 --objects=100:50000 --points=1000 > data/async_copy_tree.txt 
```

Difference in scheduling is too noisy to draw any conclusions about effect of copying task-locals on scheduling of the destruction of the root of the tree:

```shell
$ ./regression.py data/async_copy_tree.txt -y S        
Scheduling: -1.7290801314669238e-08⋅v⋅o² + 0.001235787251508909⋅v⋅o + -7.618884224050876⋅v + 5.302224585147051e-06⋅o² + -0.3656720714361409⋅o + 5570.464743812955, R² = 0.1265, Adjusted R² = 0.1212
```

But differences in total execution time allow to conclude that copying task-locals in async deinit costs about 40ns per value per object:

```shell
$ ./regression.py data/async_copy_tree.txt -y T -p vo
Total: 39.14231151032403⋅v⋅o, R² = 0.9981, Adjusted R² = 0.9981
```

It is not clear what causes 15ns difference between array and tree cases.