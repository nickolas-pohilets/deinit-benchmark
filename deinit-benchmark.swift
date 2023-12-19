import Dispatch

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
    init(_ objects: Int, _ group: DispatchGroup)
}

class TreeBase<Child: Tree> {
    typealias ChildType = Child
    var group: DispatchGroup
    var first: ChildType?
    var second: ChildType?

    init(_ objects: Int, _ group: DispatchGroup) {
        self.group = group
        group.enter()
        
        let L = objects / 2
        let R = objects - 1 - L

        if L > 0 {
            first = ChildType(L, group)
        }

        if R > 0 {
            second = ChildType(R, group)
        }
    }

    deinit {
        group.leave()
    }
}

//class ListBase<Child: Tree> {
//    typealias ChildType = Child
//    var group: DispatchGroup
//    var next: ChildType?
//
//    init(_ objects: Int, _ group: DispatchGroup) {
//        self.group = group
//        group.enter()
//        
//        if objects > 1 {
//            next = ChildType(objects - 1, group)
//        }
//    }
//
//    deinit {
//        group.leave()
//    }
//}

final class NonisolatedTree: TreeBase<NonisolatedTree>, Tree {

}

final class IsolatedCopyTree: TreeBase<IsolatedCopyTree>, Tree {
    @FirstActor deinit {
    }
}

final class IsolatedResetTree: TreeBase<IsolatedResetTree>, Tree {
    @resetTaskLocals
    @FirstActor deinit {
    }
}

final class InterleavedCopyTree: TreeBase<InterleavedCopyTreeAnother>, Tree {
    @FirstActor deinit {
    }
}

final class InterleavedCopyTreeAnother: TreeBase<InterleavedCopyTree>, Tree {
    @SecondActor deinit {
    }
}

final class InterleavedResetTree: TreeBase<InterleavedResetTreeAnother>, Tree {
    @resetTaskLocals
    @FirstActor deinit {
    }
}

final class InterleavedResetTreeAnother: TreeBase<InterleavedResetTree>, Tree {
    @resetTaskLocals
    @SecondActor deinit {
    }
}

//final class InterleavedCopyList: ListBase<InterleavedCopyListAnother>, Tree {
//    @FirstActor deinit {
//    }
//}
//
//final class InterleavedCopyListAnother: ListBase<InterleavedCopyList>, Tree {
//    @SecondActor deinit {
//    }
//}

//final class InterleavedResetList: ListBase<InterleavedResetListAnother>, Tree {
//    @resetTaskLocals
//    @FirstActor deinit {
//    }
//}
//
//final class InterleavedResetListAnother: ListBase<InterleavedResetList>, Tree {
//    @resetTaskLocals
//    @SecondActor deinit {
//    }
//}

final class AsyncYieldCopyTree: TreeBase<AsyncYieldCopyTree>, Tree {
    @FirstActor deinit async {
        await Task.yield()
    }
}

final class AsyncYieldResetTree: TreeBase<AsyncYieldResetTree>, Tree {
    @resetTaskLocals
    @FirstActor deinit async {
        await Task.yield()
    }
}

final class AsyncNoOpCopyTree: TreeBase<AsyncNoOpCopyTree>, Tree {
    @FirstActor deinit async {
        await noop()
    }
}

final class AsyncNoOpResetTree: TreeBase<AsyncNoOpResetTree>, Tree {
    @resetTaskLocals
    @FirstActor deinit async {
        await noop()
    }
}

class InterleavedTree {
    var group: DispatchGroup
    var first: InterleavedTreeAnother?
    var second: InterleavedTreeAnother?

    init(_ objects: Int, _ group: DispatchGroup) {
        self.group = group
        group.enter()

        let L = objects / 2
        let R = objects - 1 - L

        if L == 0 {
            first = nil
        } else {
            first = InterleavedTreeAnother(L, group)
        }

        if R == 0 {
            second = nil  
        } else {
            second = InterleavedTreeAnother(R, group)
        }
    }

    @resetTaskLocals
    @FirstActor deinit {
        group.leave()
    }
}

class InterleavedTreeAnother {
    var group: DispatchGroup
    var first: InterleavedTree?
    var second: InterleavedTree?

    init(_ objects: Int, _ group: DispatchGroup) {
        self.group = group
        group.enter()

        let L = objects / 2
        let R = objects - 1 - L

        if L == 0 {
            first = nil
        } else {
            first = InterleavedTree(L, group)
        }

        if R == 0 {
            second = nil  
        } else {
            second = InterleavedTree(R, group)
        }
    }

    @resetTaskLocals
    @FirstActor deinit {
        group.leave()
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
    static func build(_ type: any Tree.Type, _ numObjects: Int, _ g: DispatchGroup) -> Storage
}

struct TreeBuilder: Builder {
    static var empty: AnyObject? { nil }
    static func build(_ type: any Tree.Type, _ numObjects: Int, _ g: DispatchGroup) -> AnyObject? { type.init(numObjects, g) }
}

struct ArrayBuilder: Builder {
    static var empty: [AnyObject] { [] }
    static func build(_ type: any Tree.Type, _ numObjects: Int, _ g: DispatchGroup) -> [AnyObject] { (0..<numObjects).map { _ in type.init(1, g) } }
}

func measure(builder: any Builder.Type, type: any Tree.Type, numObjects: Int) -> (schedule: Duration, total: Duration) {
    let g = DispatchGroup()
    var storage = builder.build(type, numObjects, g)
    let clock = ContinuousClock()
    let t1 = clock.now
    withExtendedLifetime(storage) {}
    storage = builder.empty
    let t2 = clock.now
    g.wait()
    let t3 = clock.now
    let s = t2 - t1
    let t = t3 - t1
    return (s, t)
}


struct Stats {
    var average: Duration
    var stddev: Duration
}

struct StatsCalculator {
    var sum: Duration = Duration.seconds(0)
    var values: [Duration] = []

    mutating func add(_ x: Duration) {
        sum += x
        values.append(x)
    }

    var stats: Stats {
        let average = sum / values.count
        var variance: Double = 0
        for value in values {
            let delta = Double((value - average).asSeconds)
            variance += delta * delta
        }
        let sigma = variance.squareRoot()
        
        let integralPart = sigma.rounded(.towardZero)
        let fractionalPart = sigma - integralPart
        let stddev = Duration(secondsComponent: Int64(integralPart), attosecondsComponent: Int64((fractionalPart * 1e18).rounded()))
        return Stats(average: average, stddev: stddev)
    }
}

func measureAverage(builder: any Builder.Type, type: any Tree.Type, numObjects: Int, repetitions: Int) -> (schedule: Stats, total: Stats) {
    var scheduleCalc = StatsCalculator()
    var totalCalc = StatsCalculator()

    for _ in 0..<repetitions {
        let (s, t) = measure(builder: builder, type: type, numObjects: numObjects)
        scheduleCalc.add(s)
        totalCalc.add(t)
    }
    return (scheduleCalc.stats, totalCalc.stats)
}

func printHeader(normalizeByTLs: Bool, normalizeByObjects: Bool) {
    let normalizedTitle = normalizeByTLs ? (normalizeByObjects ? "normalized (ns)" : "per TL (ns)") : (normalizeByObjects ? "per object (ns)" : "")
    let sigmaTitle = "σ " + normalizedTitle
    print("#TL", "#Objs", "test", "", "", "", "baseline", "", "", "", "delta (us)", "", normalizedTitle, "", separator: "\t")
    print("", "", "schedule (us)", sigmaTitle, "total (us)", sigmaTitle, "schedule (us)", sigmaTitle, "total (us)", sigmaTitle, "schedule", "total", "schedule", "total", separator: "\t")
}

enum Distribution: CustomStringConvertible {
    case linear
    case logarithmic

    var description: String {
        switch self {
            case .linear: return "linear"
            case .logarithmic: return "logarithmic"
        }
    }
}

struct Domain: CustomStringConvertible {
    var range: ClosedRange<Int>
    var distribution: Distribution

    var description: String {
        "\(range.lowerBound):\(range.upperBound):\(distribution)"
    }
}

struct Generator {
    enum Impl {
        case linear(ClosedRange<Int>)
        case logarithmic(ClosedRange<Double>)
    }
    var impl: Impl

    init(_ domain: Domain) {
        switch domain.distribution {
        case .linear:
            self.impl = .linear(domain.range)
        case .logarithmic:
            let logRange = log(Double(domain.range.lowerBound))...log(Double(domain.range.upperBound))
            self.impl = .logarithmic(logRange)
        }
    }

    func generate() -> Int {
        switch impl {
        case .linear(let range):
            return Int.random(in: range)
        case .logarithmic(let logRange):
            return Int(exp(Double.random(in: logRange)).rounded())
        }
    }
}

func benchmark(
    _ actor: isolated Actor,
    _ builder: any Builder.Type,
    _ testType: any Tree.Type,
    _ baselineType: any Tree.Type,
    _ TLs: Domain,
    _ objects: Domain,
    _ points: Int
) {
    withTLs(1) {
        _ = measure(builder: builder, type: testType, numObjects: 1)
        _ = measure(builder: builder, type: baselineType, numObjects: 1)
    }

    let valuesGenerator = Generator(TLs)
    let objectsGenerator = Generator(objects)

    for i in 0..<points {
        let numTLs = valuesGenerator.generate()
        let numObjects = objectsGenerator.generate()
        
        withTLs(numTLs) {
            let test = measure(builder: builder, type: testType, numObjects: numObjects)
            let baseline = measure(builder: builder, type: baselineType, numObjects: numObjects)
            let deltaSchedule = test.schedule - baseline.schedule
            let deltaTotal = test.total - baseline.total
            print(
                numTLs, numObjects,
                deltaSchedule.asNanoSeconds,
                deltaTotal.asNanoSeconds,
                separator: "\t"
            )
        }

        fputs("\r\(i)/\(points)", stderr)
    }
    fputs("\n", stderr)
}

struct Benchmark {
    var help: String
    var actor: Actor
    var builder: any Builder.Type
    var testType: any Tree.Type
    var baselineType: any Tree.Type

    func run(TLs: Domain, objects: Domain, points: Int) async {
        await benchmark(actor, builder, testType, baselineType, TLs, objects, points)
    }
}

let benchmarks: [String: Benchmark] = [
    "async_tree": Benchmark(
        help: "Measure cost of executing no-op deinit asynchronously vs inline using binary tree of objects",
        actor: SecondActor.shared, builder: TreeBuilder.self, testType: AsyncNoOpResetTree.self, baselineType: NonisolatedTree.self
    ),
    "async_array": Benchmark(
        help: "Measure cost of executing no-op deinit asynchronously vs inline using array of objects",
        actor: SecondActor.shared, builder: ArrayBuilder.self, testType: AsyncNoOpResetTree.self, baselineType: NonisolatedTree.self
    ),
    "async_copy_noop": Benchmark(
        help: "Measure cost of copying task locals in no-op async deinit using binary tree of objects",
        actor: FirstActor.shared, builder: TreeBuilder.self, testType: AsyncNoOpCopyTree.self, baselineType: AsyncNoOpResetTree.self
    ),
    "async_copy_yield": Benchmark(
        help: "Measure cost of copying task locals in yielding async deinit using binary tree of objects",
        actor: FirstActor.shared, builder: TreeBuilder.self, testType: AsyncYieldCopyTree.self, baselineType: AsyncYieldResetTree.self
    ),
    "isolated_no_hop_copy": Benchmark(
        help: "Measure cost of fast path of isolated deinit preserving task locals using binary tree of objects",
        actor: FirstActor.shared, builder: TreeBuilder.self, testType: IsolatedCopyTree.self, baselineType: NonisolatedTree.self
    ),
    "isolated_no_hop_reset": Benchmark(
        help: "Measure cost of fast path of isolated deinit inserting stop node using binary tree of objects",
        actor: FirstActor.shared, builder: TreeBuilder.self, testType: IsolatedResetTree.self, baselineType: NonisolatedTree.self
    ),
    "isolated_hop_copy": Benchmark(
        help: "Measure cost of slow path of isolated deinit copying task locals",
        actor: SecondActor.shared, builder: ArrayBuilder.self, testType: IsolatedCopyTree.self, baselineType: NonisolatedTree.self
    ),
    "isolated_hop_reset": Benchmark(
        help: "Measure cost of slow path of isolated deinit ignoring task locals",
        actor: SecondActor.shared, builder: ArrayBuilder.self, testType: IsolatedResetTree.self, baselineType: NonisolatedTree.self
    ),
    "isolated_copy": Benchmark(
        help: "Measure cost of copying task locals ",
        actor: SecondActor.shared, builder: ArrayBuilder.self, testType: IsolatedCopyTree.self, baselineType: IsolatedResetTree.self
    ),
]

//benchmark_1(ArrayBuilder.self, IsolatedResetTree.self, NonisolatedTree.self, normalizeByTLs: false)
//benchmark_2(ArrayBuilder.self, IsolatedCopyTree.self, IsolatedResetTree.self, TLs: 1...50, objects: 1_000...1_000)

//measureTreeAgainstValuesCount(IsolatedCopyTree.self, NonisolatedTree.self)

extension String {
    func removingPrefix(_ prefix: String) -> String? {
        guard self.hasPrefix(prefix) else { return nil }
        return String(self.dropFirst(prefix.count))
    }
}

func parseDomain(_ s: String, domain: inout Domain) -> Bool {
    let components = s.split(separator: ":")
    if components.count > 3 { return false }
    
    let minValue: Int
    if components.count < 1 || components[0].isEmpty {
        minValue = domain.range.lowerBound
    } else {
        guard let value = Int(components[0]) else { return false }
        minValue = value
    }

    let maxValue: Int
    if components.count < 2 || components[1].isEmpty {
        maxValue = domain.range.upperBound
    } else {
        guard let value = Int(components[1]) else { return false }
        maxValue = value
    }

    if minValue < 0 || maxValue < minValue { return false }

    domain.range = minValue...maxValue

    if components.count >= 3 {
        switch components[2] {
        case "":
            break
        case "linear":
            domain.distribution = .linear
        case "logarithmic":
            domain.distribution = .logarithmic
        default:
            return false
        }
    }

    return true
}

struct Args: CustomStringConvertible {
    var benchmarkName: String
    var benchmark: Benchmark
    var values = Domain(range: 1...1_000, distribution: .linear)
    var objects = Domain(range: 10...100_000, distribution: .linear)
    var points: Int = 5_000

    var description: String {
        "\(benchmarkName) --values=\(values) --objects=\(objects) --points=\(points)"
    }

    @MainActor
    func run() async {
        print("# \(self)")
        print("#")
        print("# values objects Δschedule(ns) Δtotal(ns)")
        await benchmark.run(TLs: values, objects: objects, points: points)      
    }
}

func parseArgs(_ arguments: [String]) -> Args {
    if arguments.count < 2 || arguments[1].hasPrefix("--") {
        print("Missing benchmark name")
        printUsage()
    }
    let benchmarkName = arguments[1]
    guard let benchmark = benchmarks[benchmarkName] else {
        print("Invalid benchmark name \"\(arguments[1])\"")
        printUsage()
    }
    var result = Args(benchmarkName: benchmarkName, benchmark: benchmark)
    for arg in arguments[2...] {
        if let value = arg.removingPrefix("--values=") {
            if !parseDomain(value, domain: &result.values) {
                print("Invalid values domain \"\(value)\"")
                printUsage()
            }
        } else if let value = arg.removingPrefix("--objects=") {
            if !parseDomain(value, domain: &result.objects) {
                print("Invalid objects domain \"\(value)\"")
                printUsage()
            }
        } else if let value = arg.removingPrefix("--points=") {
            if let n = Int(value), n > 0 {
                result.points = n
            } else {
                print("Invalid number of points")
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
    print("Usage: deinit-bechmark BENCHMARK_NAME [--values=MIN:MAX:(linear|logarithmic)] [--objects=MIN:MAX:(linear|logarithmic)] [--points=POINTS]")
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
