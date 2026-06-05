import AppKit
import Darwin
import Foundation
import HertzCore

struct ProcessActionItem: Identifiable, Equatable {
    let pid: pid_t
    let name: String
    let path: String

    var id: pid_t { pid }
}

struct ProcessActionTarget: Identifiable, Equatable {
    let root: ProcessActionItem
    let items: [ProcessActionItem]

    var id: pid_t { root.pid }
    var descendantCount: Int { max(0, items.count - 1) }
    var includesDescendants: Bool { descendantCount > 0 }

    var title: String {
        root.name.isEmpty ? "pid \(root.pid)" : root.name
    }

    var terminationSummary: String {
        if includesDescendants {
            return "\(title) and \(descendantCount) child process\(descendantCount == 1 ? "" : "es")"
        }
        return title
    }
}

struct ProcessTerminationReport {
    let terminated: [ProcessActionItem]
    let skipped: [String]
    let failed: [String]

    var message: String {
        var parts: [String] = []
        if !terminated.isEmpty {
            parts.append("Terminated \(terminated.count)")
        }
        if !skipped.isEmpty {
            parts.append("Skipped \(skipped.count)")
        }
        if !failed.isEmpty {
            parts.append("Failed \(failed.count)")
        }
        return parts.isEmpty ? "No matching process was terminated" : parts.joined(separator: " · ")
    }
}

extension ProcessNode {
    var processActionTarget: ProcessActionTarget {
        let allItems = flattenedProcessItems()
        return ProcessActionTarget(root: allItems[0], items: allItems)
    }

    private func flattenedProcessItems() -> [ProcessActionItem] {
        [ProcessActionItem(sample: sample)] + children.flatMap { $0.flattenedProcessItems() }
    }
}

private extension ProcessActionItem {
    init(sample: ProcSample) {
        self.init(pid: sample.pid, name: sample.name, path: sample.path)
    }

    var displayName: String {
        name.isEmpty ? "pid \(pid)" : "\(name) (\(pid))"
    }
}

enum ProcessActions {
    static func copyDetails(_ target: ProcessActionTarget) {
        let details = target.items.map { item in
            let path = item.path.isEmpty ? "path unavailable" : item.path
            return "\(item.name)\tpid \(item.pid)\t\(path)"
        }.joined(separator: "\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(details, forType: .string)
    }

    static func canReveal(_ target: ProcessActionTarget) -> Bool {
        revealURL(for: target.root) != nil
    }

    @discardableResult
    static func reveal(_ target: ProcessActionTarget) -> Bool {
        guard let url = revealURL(for: target.root) else { return false }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        return true
    }

    static func terminate(_ target: ProcessActionTarget) -> ProcessTerminationReport {
        var terminated: [ProcessActionItem] = []
        var skipped: [String] = []
        var failed: [String] = []

        for item in target.items.reversed() {
            if item.pid <= 1 || item.pid == getpid() {
                skipped.append("\(item.displayName): protected process")
                continue
            }

            guard processExists(item.pid) else {
                skipped.append("\(item.displayName): already exited")
                continue
            }

            if !item.path.isEmpty,
               let currentPath = executablePath(item.pid),
               currentPath != item.path {
                skipped.append("\(item.displayName): pid now belongs to another process")
                continue
            }

            if kill(item.pid, SIGTERM) == 0 {
                terminated.append(item)
            } else {
                failed.append("\(item.displayName): \(String(cString: strerror(errno)))")
            }
        }

        return ProcessTerminationReport(terminated: terminated, skipped: skipped, failed: failed)
    }

    private static func revealURL(for item: ProcessActionItem) -> URL? {
        guard !item.path.isEmpty else { return nil }
        let path: String
        if let range = item.path.range(of: ".app/") {
            path = String(item.path[..<range.lowerBound]) + ".app"
        } else {
            path = item.path
        }
        return URL(fileURLWithPath: path)
    }

    private static func processExists(_ pid: pid_t) -> Bool {
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }

    private static func executablePath(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
