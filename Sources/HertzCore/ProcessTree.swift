import Darwin

/// A process plus its descendants, with resource totals summed over the
/// whole subtree (self + every child, recursively).
public struct ProcessNode: Identifiable {
    public let id: pid_t
    public let sample: ProcSample
    public let children: [ProcessNode]
    public let subtreeCPU: Double      // self + descendants, percent
    public let subtreeMemory: UInt64   // self + descendants, bytes
    public let processCount: Int       // self + descendants
}

/// Build a forest from a flat process list using ppid links.
///
/// Children of launchd (pid 1) are kept as their own roots — otherwise every
/// app would nest under launchd and the grouping would be meaningless. So an
/// app's helper processes (parented to the app) nest under it, while the app
/// itself stays a top-level root.
public func buildProcessTree(_ samples: [ProcSample]) -> [ProcessNode] {
    let byPid = Dictionary(samples.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })

    var childrenOf: [pid_t: [pid_t]] = [:]
    for s in samples {
        let parent = s.ppid
        guard parent != 1, parent != 0, parent != s.pid, byPid[parent] != nil
        else { continue }
        childrenOf[parent, default: []].append(s.pid)
    }
    let childPids = Set(childrenOf.values.flatMap { $0 })

    func node(for pid: pid_t, depth: Int) -> ProcessNode? {
        guard depth < 24, let sample = byPid[pid] else { return nil } // depth cap = cycle guard
        let kids = (childrenOf[pid] ?? []).compactMap { node(for: $0, depth: depth + 1) }
        return ProcessNode(
            id: pid,
            sample: sample,
            children: kids,
            subtreeCPU: sample.cpu + kids.reduce(0) { $0 + $1.subtreeCPU },
            subtreeMemory: sample.memory + kids.reduce(0) { $0 + $1.subtreeMemory },
            processCount: 1 + kids.reduce(0) { $0 + $1.processCount })
    }

    return samples
        .filter { !childPids.contains($0.pid) }
        .compactMap { node(for: $0.pid, depth: 0) }
}
