import Dispatch
import Foundation

let TLs = (0..<10000).map { _ in
    TaskLocal<AnyObject?>(wrappedValue: nil)
}

class Foo {}

func withTLs<T>(_ count: Int, _ block: () -> T) -> T {
    if count == 0 {
        return block()
    } else {
        return TLs[count - 1].withValue(Foo()) {
            withTLs(count - 1, block)
        }
    }
}

@globalActor final actor FirstActor {
  static let shared = FirstActor()
}

@globalActor final actor SecondActor {
  static let shared = SecondActor()
}

func noop() async {}

protocol Tree: AnyObject {
    init(_ objects: Int, _ group: DispatchGroup, _ ballast: Int)
}

class TreeBase<Child: Tree> {
    typealias ChildType = Child
    var group: DispatchGroup
    var first: ChildType?
    var second: ChildType?
    let ballast: Int

    init(_ objects: Int, _ group: DispatchGroup, _ ballast: Int) {
        self.group = group
        group.enter()
        
        let L = objects / 2
        let R = objects - 1 - L

        if L > 0 {
            first = ChildType(L, group, ballast)
        }

        if R > 0 {
            second = ChildType(R, group, ballast)
        }

        self.ballast = ballast
    }

    deinit {
        for _ in 0..<ballast {
            _ = arc4random()
        }
        group.leave()
    }
}

typealias NonisolatedTreeBase = TreeBase<NonisolatedTree>
final class NonisolatedTree: NonisolatedTreeBase, Tree {

}

typealias IsolatedCopyTreeBase = TreeBase<IsolatedCopyTree>
final class IsolatedCopyTree: IsolatedCopyTreeBase, Tree {
    @FirstActor deinit {
    }
}

typealias IsolatedResetTreeBase = TreeBase<IsolatedResetTree>
final class IsolatedResetTree: IsolatedResetTreeBase, Tree {
    @resetTaskLocals
    @FirstActor deinit {
    }
}

typealias InterleavedCopyTreeBase = TreeBase<InterleavedCopyTreeAnother>
final class InterleavedCopyTree: InterleavedCopyTreeBase, Tree {
    @FirstActor deinit {
    }
}

typealias InterleavedCopyTreeAnotherBase = TreeBase<InterleavedCopyTree>
final class InterleavedCopyTreeAnother: InterleavedCopyTreeAnotherBase, Tree {
    @SecondActor deinit {
    }
}

typealias InterleavedResetTreeBase = TreeBase<InterleavedResetTreeAnother>
final class InterleavedResetTree: InterleavedResetTreeBase, Tree {
    @resetTaskLocals
    @FirstActor deinit {
    }
}

typealias InterleavedResetTreeAnotherBase = TreeBase<InterleavedResetTree>
final class InterleavedResetTreeAnother: InterleavedResetTreeAnotherBase, Tree {
    @resetTaskLocals
    @SecondActor deinit {
    }
}

typealias AsyncYieldCopyTreeBase = TreeBase<AsyncYieldCopyTree>
final class AsyncYieldCopyTree: AsyncYieldCopyTreeBase, Tree {
    @FirstActor deinit async {
        await Task.yield()
    }
}

typealias AsyncYieldResetTreeBase = TreeBase<AsyncYieldResetTree>
final class AsyncYieldResetTree: AsyncYieldResetTreeBase, Tree {
    @resetTaskLocals
    @FirstActor deinit async {
        await Task.yield()
    }
}

typealias AsyncNoOpCopyTreeBase = TreeBase<AsyncNoOpCopyTree>
final class AsyncNoOpCopyTree: AsyncNoOpCopyTreeBase, Tree {
    @FirstActor deinit async {
        await noop()
    }
}

typealias AsyncNoOpResetTreeBase = TreeBase<AsyncNoOpResetTree>
final class AsyncNoOpResetTree: AsyncNoOpResetTreeBase, Tree {
    @resetTaskLocals
    @FirstActor deinit async {
        await noop()
    }
}

extension Duration {
    var asMicroSeconds: Int64 {
        let comps = self.components
        return comps.seconds * 1_000_000 + (comps.attoseconds + 500_000_000_000) / 1_000_000_000_000
    }

    var asNanoSeconds: Int64 {
        let comps = self.components
        return comps.seconds * 1_000_000_000 + (comps.attoseconds + 500_000_000) / 1_000_000_000
    }

    var asSeconds: Double {
        let comps = self.components
        return Double(comps.seconds) + 1e-18 * Double(comps.attoseconds)
    }
}

protocol Builder {
    associatedtype Storage

    static var empty: Storage { get }
    static func build(_ type: any Tree.Type, _ numObjects: Int, _ g: DispatchGroup, _ ballast: Int) -> Storage
}

struct TreeBuilder: Builder {
    static var empty: AnyObject? { nil }
    static func build(_ type: any Tree.Type, _ numObjects: Int, _ g: DispatchGroup, _ ballast: Int) -> AnyObject? {
        type.init(numObjects, g, ballast)
    }
}

struct ArrayBuilder: Builder {
    static var empty: [AnyObject] { [] }
    static func build(_ type: any Tree.Type, _ numObjects: Int, _ g: DispatchGroup, _ ballast: Int) -> [AnyObject] {
        (0..<numObjects).map { _ in type.init(1, g, ballast) }
    }
}

let clock = ContinuousClock()

typealias Measurements = (schedule: Duration, total: Duration)
func measure(builder: any Builder.Type, type: any Tree.Type, numObjects: Int, ballast: Int) -> Measurements {
    let g = DispatchGroup()
    var storage = builder.build(type, numObjects, g, ballast)
    let t1 = clock.now
    withExtendedLifetime(storage) {}
    storage = builder.empty
    let t2 = clock.now
    g.wait()
    let t3 = clock.now
    let s = t2 - t1
    let t = t3 - t1
    return Measurements(schedule: s, total: t)
}

struct InputParams {
    var values: Int
    var objects: Int
}

func benchmark(
    _ actor: isolated Actor,
    _ builder: any Builder.Type,
    _ type: any Tree.Type,
    _ ballast: Int,
    _ inputs: [InputParams]
) {
    withTLs(1) {
        _ = measure(builder: builder, type: type, numObjects: 1, ballast: 1)
        _ = measure(builder: builder, type: type, numObjects: 1, ballast: 1)
    }

    for (i, params) in inputs.enumerated() {
        withTLs(params.values) {
            let m: Measurements = measure(builder: builder, type: type, numObjects: params.objects, ballast: ballast)
            print(
                m.schedule.asNanoSeconds,
                m.total.asNanoSeconds,
                separator: "\t"
            )
        }

        fputs("\r\(i + 1)/\(inputs.count)", stderr)
    }
    fputs("\n", stderr)
}

struct Benchmark {
    var help: String
    var actor: Actor
    var builder: any Builder.Type
    var type: any Tree.Type

    func run(inputs: [InputParams], ballast: Int) async {
        await benchmark(actor, builder, type, ballast, inputs)
    }
}

let benchmarks: [String: Benchmark] = [
    "nonisolated_array": Benchmark(
        help: "Regular deinit using array of objects",
        actor: FirstActor.shared, builder: ArrayBuilder.self, type: NonisolatedTree.self
    ),
    "nonisolated_tree": Benchmark(
        help: "Regular deinit using binary tree of objects",
        actor: FirstActor.shared, builder: TreeBuilder.self, type: NonisolatedTree.self
    ),
    "isolated_no_hop_copy_array": Benchmark(
        help: "Fast path of isolated deinit preserving task locals using array of objects",
        actor: FirstActor.shared, builder: ArrayBuilder.self, type: IsolatedCopyTree.self
    ),
    "isolated_no_hop_copy_tree": Benchmark(
        help: "Fast path of isolated deinit preserving task locals using binary tree of objects",
        actor: FirstActor.shared, builder: TreeBuilder.self, type: IsolatedCopyTree.self
    ),
    "isolated_no_hop_reset_array": Benchmark(
        help: "Fast path of isolated deinit inserting stop node using array of objects",
        actor: FirstActor.shared, builder: ArrayBuilder.self, type: IsolatedResetTree.self
    ),
    "isolated_no_hop_reset_tree": Benchmark(
        help: "Fast path of isolated deinit inserting stop node using binary tree of objects",
        actor: FirstActor.shared, builder: TreeBuilder.self, type: IsolatedResetTree.self
    ),
    "isolated_hop_reset_array": Benchmark(
        help: "Slow path of isolated deinit ignoring task locals using array of objects",
        actor: SecondActor.shared, builder: ArrayBuilder.self, type: IsolatedResetTree.self
    ),
    "isolated_hop_reset_tree": Benchmark(
        help: "Slow path of isolated deinit ignoring task locals using tree of objects",
        actor: SecondActor.shared, builder: TreeBuilder.self, type: IsolatedResetTree.self
    ),
    "isolated_hop_reset_tree_interleaved": Benchmark(
        help: "Slow path of isolated deinit ignoring task locals using tree of objects",
        actor: MainActor.shared, builder: TreeBuilder.self, type: InterleavedResetTree.self
    ),
    "isolated_hop_copy_array": Benchmark(
        help: "Slow path of isolated deinit copying task locals using array of objects",
        actor: SecondActor.shared, builder: ArrayBuilder.self, type: IsolatedCopyTree.self
    ),
    "isolated_hop_copy_tree": Benchmark(
        help: "Slow path of isolated deinit copying task locals using tree of objects",
        actor: SecondActor.shared, builder: TreeBuilder.self, type: IsolatedCopyTree.self
    ),
    "isolated_hop_copy_tree_interleaved": Benchmark(
        help: "Slow path of isolated deinit copying task locals using tree of objects",
        actor: MainActor.shared, builder: TreeBuilder.self, type: InterleavedCopyTree.self
    ),
    "async_reset_array": Benchmark(
        help: "Async deinit ignoring task locals using array of objects",
        actor: SecondActor.shared, builder: ArrayBuilder.self, type: AsyncNoOpResetTree.self
    ),
    "async_reset_tree": Benchmark(
        help: "Async deinit ignoring task locals using binary tree of objects",
        actor: SecondActor.shared, builder: TreeBuilder.self, type: AsyncNoOpResetTree.self
    ),
    "async_copy_array": Benchmark(
        help: "Async deinit copying task locals using array of objects",
        actor: SecondActor.shared, builder: ArrayBuilder.self, type: AsyncNoOpCopyTree.self
    ),
    "async_copy_tree": Benchmark(
        help: "Async deinit copying task locals using binary tree of objects",
        actor: SecondActor.shared, builder: TreeBuilder.self, type: AsyncNoOpCopyTree.self
    ),
]

extension String {
    func removingPrefix(_ prefix: String) -> String? {
        guard self.hasPrefix(prefix) else { return nil }
        return String(self.dropFirst(prefix.count))
    }
}

struct Args: CustomStringConvertible {
    var inputsFileName: String
    var inputs: [InputParams]
    var benchmarkName: String
    var benchmark: Benchmark
    var ballast: Int = 0

    var description: String {
        "\(benchmarkName) \(inputsFileName) --ballast=\(ballast)"
    }

    @MainActor
    func run() async {
        print("# \(self)")
        print("#")
        print("# schedule(ns) total(ns)")
        await benchmark.run(inputs: inputs, ballast: ballast)
    }
}

func parseArgs(_ arguments: [String]) -> Args {
    if arguments.contains("--help") {
        printUsage()
    }
    if arguments.count < 2 || arguments[1].hasPrefix("--") {
        print("Missing inputs file name")
        printUsage()
    }
    let inputsFileName = arguments[1]
    var inputs: [InputParams] = []
    do {
        let text = try String(contentsOfFile: inputsFileName, encoding: .utf8)
        let lines = text.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() {
            if line.hasPrefix("#") || line.isEmpty {
                continue
            }
            let comps = line.components(separatedBy: "\t")
            if comps.count == 2, let v = Int(comps[0]), let o = Int(comps[1]), v >= 0, o > 0 {
                inputs.append(InputParams(values: v, objects: o))
            } else {
                print("\(inputsFileName):\(i + 1): error: Invalid data")
                print("  \(line)")
                print("  \(String(repeating: "^", count: line.count))")
            }
        }
    } catch {
        print("Error reading from: \(inputsFileName)")
        print(error)
        exit(1)
    }
    if arguments.count < 3 || arguments[2].hasPrefix("--") {
        print("Missing benchmark name")
        printUsage()
    }
    let benchmarkName = arguments[2]
    guard let benchmark = benchmarks[benchmarkName] else {
        print("Invalid benchmark name \"\(benchmarkName)\"")
        printUsage()
    }
    var result = Args(
        inputsFileName: inputsFileName,
        inputs: inputs,
        benchmarkName: benchmarkName,
        benchmark: benchmark
    )
    for arg in arguments[3...] {
        if let value = arg.removingPrefix("--ballast=") {
            if let n = Int(value), n >= 0 {
                result.ballast = n
            } else {
                print("Invalid ballast")
                printUsage()
            }
        } else {
            print("Unknown argument \"\(arg)\"")
            printUsage()
        }
    }
    return result
}

func printUsage() -> Never {
    print("Usage: deinit-benchmark BENCHMARK_NAME INPUTS_FILE [--ballast=N]")
    print("Use ./gen-points.py to create INPUTS_FILE")
    print("Possible benchmark names:")
    for b in benchmarks.keys.sorted() {
        print("  * \(b) - \(benchmarks[b]!.help)")
    }
    return exit(1)
}

@main
struct Main {
    static func main() async {
        let args = parseArgs(CommandLine.arguments)
        await args.run()
    }
}
