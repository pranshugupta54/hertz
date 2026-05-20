import Darwin
import Dispatch

/// One process sampled from the kernel via libproc.
public struct ProcSample {
    public let pid: pid_t
    public let ppid: pid_t
    public let name: String
    public let path: String   // executable path, for app-icon resolution
    public let memory: UInt64 // physical footprint, bytes — matches Activity Monitor
    public var cpu: Double    // percent of one core (can exceed 100 across cores)
}

/// Reads the kernel process table directly through libproc — the same C API
/// that `ps`, `top`, and Activity Monitor use. No `ps` spawn, no text parsing.
public final class ProcessCollector {
    // CPU time is a cumulative counter. A percentage is a delta between two
    // samples, so keep the previous reading per pid.
    private var prevCPU: [pid_t: UInt64] = [:]
    private var prevWall: UInt64 = 0

    // proc_taskinfo CPU times are in Mach absolute-time units, not nanoseconds.
    // ns = ticks * numer / denom (1/1 on Intel, 125/3 on Apple Silicon).
    private let timebaseNumer: UInt64
    private let timebaseDenom: UInt64

    public init() {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        timebaseNumer = UInt64(tb.numer)
        timebaseDenom = UInt64(max(tb.denom, 1))
    }

    public func sample() -> [ProcSample] {
        // 1. Ask the kernel for every pid.
        let guess = proc_listallpids(nil, 0)
        guard guess > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(guess) + 256) // slack for new procs
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard filled > 0 else { return [] }
        let count = min(Int(filled), pids.count)

        let nowWall = DispatchTime.now().uptimeNanoseconds
        let wallDelta = prevWall == 0 ? 0 : nowWall &- prevWall

        let structSize = Int32(MemoryLayout<proc_taskallinfo>.size)
        var out: [ProcSample] = []
        var curCPU: [pid_t: UInt64] = [:]

        // 2. For each pid pull task + bsd info in one call.
        for i in 0..<count {
            let pid = pids[i]
            guard pid > 0 else { continue }

            var info = proc_taskallinfo()
            let r = proc_pidinfo(pid, PROC_PIDTASKALLINFO, 0, &info, structSize)
            guard r == structSize else { continue } // 0/-1 = gone or no permission

            let cpuTotal = info.ptinfo.pti_total_user + info.ptinfo.pti_total_system
            curCPU[pid] = cpuTotal

            // 3. Percentage from the delta against the previous sample.
            var cpuPct = 0.0
            if wallDelta > 0, let prev = prevCPU[pid], cpuTotal >= prev {
                let cpuDeltaNS = (cpuTotal - prev) * timebaseNumer / timebaseDenom
                cpuPct = Double(cpuDeltaNS) / Double(wallDelta) * 100.0
            }

            let name = nonEmpty(cString(info.pbsd.pbi_name))
                ?? nonEmpty(cString(info.pbsd.pbi_comm))
                ?? "pid \(pid)"

            // Activity Monitor's "Memory" column is phys_footprint, not RSS.
            // RSS double-counts shared pages; footprint is the real cost.
            let footprint = physFootprint(pid)
            out.append(ProcSample(
                pid: pid,
                ppid: pid_t(info.pbsd.pbi_ppid),
                name: name,
                path: executablePath(pid),
                memory: footprint > 0 ? footprint : info.ptinfo.pti_resident_size,
                cpu: cpuPct
            ))
        }

        prevCPU = curCPU
        prevWall = nowWall
        return out
    }
}

/// A C fixed-size `char[]` arrives in Swift as a tuple of Int8 — read it as a
/// NUL-terminated string.
private func cString<T>(_ value: T) -> String {
    var v = value
    return withUnsafeBytes(of: &v) { raw -> String in
        guard let base = raw.baseAddress else { return "" }
        return String(cString: base.assumingMemoryBound(to: CChar.self))
    }
}

private func nonEmpty(_ s: String) -> String? {
    s.isEmpty ? nil : s
}

/// Full executable path via proc_pidpath — "" if unavailable.
private func executablePath(_ pid: pid_t) -> String {
    var buffer = [CChar](repeating: 0, count: 4096) // PROC_PIDPATHINFO_MAXSIZE
    let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
    return length > 0 ? String(cString: buffer) : ""
}

/// Physical footprint via proc_pid_rusage — the memory figure Activity Monitor
/// shows. Returns 0 if the process is not readable.
private func physFootprint(_ pid: pid_t) -> UInt64 {
    var info = rusage_info_v2()
    let rc = withUnsafeMutablePointer(to: &info) { ptr in
        ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
            proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
        }
    }
    return rc == 0 ? info.ri_phys_footprint : 0
}
