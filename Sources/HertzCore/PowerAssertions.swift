import Darwin
import Foundation
import IOKit
import IOKit.pwr_mgt

public struct PowerAssertionRecord: Identifiable, Equatable {
    public let id: String
    public let pid: pid_t
    public let processName: String
    public let processPath: String
    public let assertionName: String
    public let assertionType: String
    public let trueType: String
    public let details: String
    public let reason: String
    public let startDate: Date?
    public let level: Int

    public var isActive: Bool {
        level >= Int(kIOPMAssertionLevelOn)
    }

    public var blocksSystemSleep: Bool {
        let types = [assertionType, trueType]
        return types.contains("PreventUserIdleSystemSleep")
            || types.contains("PreventSystemSleep")
            || types.contains("NoIdleSleepAssertion")
    }

    public var blocksDisplaySleep: Bool {
        let types = [assertionType, trueType]
        return types.contains("PreventUserIdleDisplaySleep")
            || types.contains("NoDisplaySleepAssertion")
    }

    public var label: String {
        if !reason.isEmpty { return reason }
        if !details.isEmpty { return details }
        if !assertionName.isEmpty { return assertionName }
        return assertionType.isEmpty ? "power assertion" : assertionType
    }
}

public struct PowerAssertionGroup: Identifiable, Equatable {
    public let pid: pid_t
    public let processName: String
    public let processPath: String
    public let assertions: [PowerAssertionRecord]

    public var id: pid_t { pid }

    public var displayName: String {
        processName.isEmpty ? "pid \(pid)" : processName
    }

    public var blocksSystemSleep: Bool {
        assertions.contains { $0.blocksSystemSleep }
    }

    public var blocksDisplaySleep: Bool {
        assertions.contains { $0.blocksDisplaySleep }
    }

    public var longestRunningStart: Date? {
        assertions.compactMap(\.startDate).min()
    }

    public var primaryLabel: String {
        assertions.first?.label ?? "power assertion"
    }
}

public struct PowerAssertionsSnapshot: Equatable {
    public var groups: [PowerAssertionGroup]
    public var totalAssertions: Int
    public var readError: String

    public init(groups: [PowerAssertionGroup] = [],
                totalAssertions: Int = 0,
                readError: String = "") {
        self.groups = groups
        self.totalAssertions = totalAssertions
        self.readError = readError
    }

    public var hasBlockers: Bool {
        !groups.isEmpty
    }

    public var blockerCount: Int {
        groups.reduce(0) { $0 + $1.assertions.count }
    }
}

public final class PowerAssertionReader {
    public init() {}

    public func read(processes: [ProcSample] = []) -> PowerAssertionsSnapshot {
        var unmanaged: Unmanaged<CFDictionary>?
        let result = IOPMCopyAssertionsByProcess(&unmanaged)
        guard result == kIOReturnSuccess,
              let dictionary = unmanaged?.takeRetainedValue() else {
            return PowerAssertionsSnapshot(readError: "IOPMCopyAssertionsByProcess failed: \(result)")
        }

        let processByPID = Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0) })
        let raw = dictionary as NSDictionary
        var totalAssertions = 0
        var recordsByPID: [pid_t: [PowerAssertionRecord]] = [:]

        for (rawPID, rawAssertions) in raw {
            guard let pid = pid(from: rawPID),
                  let assertions = rawAssertions as? NSArray else { continue }

            for case let assertion as NSDictionary in assertions {
                totalAssertions += 1
                guard let record = record(from: assertion,
                                          pid: pid,
                                          process: processByPID[pid]),
                      record.isActive,
                      record.blocksSystemSleep || record.blocksDisplaySleep,
                      !Self.isSuppressedBaseline(record) else { continue }
                recordsByPID[pid, default: []].append(record)
            }
        }

        let groups = recordsByPID.map { pid, records in
            let process = processByPID[pid]
            let first = records[0]
            return PowerAssertionGroup(
                pid: pid,
                processName: process?.name ?? first.processName,
                processPath: process?.path ?? first.processPath,
                assertions: records.sorted(by: assertionSort)
            )
        }
        .sorted(by: groupSort)

        return PowerAssertionsSnapshot(groups: groups,
                                       totalAssertions: totalAssertions)
    }

    private static func isSuppressedBaseline(_ record: PowerAssertionRecord) -> Bool {
        let type = record.assertionType.lowercased()
        let trueType = record.trueType.lowercased()
        if type == "userisactive" || trueType == "userisactive" {
            return true
        }

        let name = record.assertionName.lowercased()
        return record.processName == "powerd"
            && name.contains("prevent sleep while display is on")
    }

    private func record(from assertion: NSDictionary,
                        pid: pid_t,
                        process: ProcSample?) -> PowerAssertionRecord? {
        let assertionType = stringValue(assertion[kIOPMAssertionTypeKey as String]) ?? ""
        let trueType = stringValue(assertion["AssertionTrueType"]) ?? ""
        let level = intValue(assertion[kIOPMAssertionLevelKey as String])
        let assertionID = intValue(assertion["AssertionId"])
        let processName = process?.name
            ?? stringValue(assertion["Process Name"])
            ?? "pid \(pid)"

        let name = stringValue(assertion[kIOPMAssertionNameKey as String]) ?? ""
        let details = stringValue(assertion[kIOPMAssertionDetailsKey as String]) ?? ""
        let reason = stringValue(assertion[kIOPMAssertionHumanReadableReasonKey as String]) ?? ""
        let startDate = assertion["AssertStartWhen"] as? Date
        let identity = "\(pid)-\(assertionID)-\(assertionType)-\(name)"

        return PowerAssertionRecord(
            id: identity,
            pid: pid,
            processName: processName,
            processPath: process?.path ?? "",
            assertionName: name,
            assertionType: assertionType,
            trueType: trueType,
            details: details,
            reason: reason,
            startDate: startDate,
            level: level
        )
    }

    private func pid(from rawPID: Any) -> pid_t? {
        if let number = rawPID as? NSNumber {
            return pid_t(number.int32Value)
        }
        return nil
    }

    private func stringValue(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let string = value as? String {
            return string
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private func intValue(_ value: Any?) -> Int {
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let string = value as? String {
            return Int(string) ?? 0
        }
        return 0
    }
}

public func powerAssertionsReport(_ snapshot: PowerAssertionsSnapshot) -> String {
    if snapshot.groups.isEmpty {
        return "Hertz Sleep Blocker Watch: no active app sleep blockers."
    }

    var lines = ["Hertz Sleep Blocker Watch"]
    for group in snapshot.groups {
        lines.append("- \(group.displayName) (pid \(group.pid))")
        if !group.processPath.isEmpty {
            lines.append("  path: \(group.processPath)")
        }
        for assertion in group.assertions {
            var detail = assertion.assertionType
            if !assertion.trueType.isEmpty, assertion.trueType != assertion.assertionType {
                detail += " / \(assertion.trueType)"
            }
            if let start = assertion.startDate {
                detail += " · active \(durationString(since: start))"
            }
            lines.append("  - \(assertion.label) [\(detail)]")
        }
    }
    return lines.joined(separator: "\n")
}

private func assertionSort(_ lhs: PowerAssertionRecord,
                           _ rhs: PowerAssertionRecord) -> Bool {
    if lhs.blocksSystemSleep != rhs.blocksSystemSleep {
        return lhs.blocksSystemSleep
    }
    let lStart = lhs.startDate ?? Date.distantFuture
    let rStart = rhs.startDate ?? Date.distantFuture
    return lStart < rStart
}

private func groupSort(_ lhs: PowerAssertionGroup,
                       _ rhs: PowerAssertionGroup) -> Bool {
    if lhs.blocksSystemSleep != rhs.blocksSystemSleep {
        return lhs.blocksSystemSleep
    }
    let lStart = lhs.longestRunningStart ?? Date.distantFuture
    let rStart = rhs.longestRunningStart ?? Date.distantFuture
    if lStart != rStart { return lStart < rStart }
    return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
}

private func durationString(since start: Date, now: Date = Date()) -> String {
    let seconds = max(0, Int(now.timeIntervalSince(start)))
    let hours = seconds / 3600
    let minutes = (seconds % 3600) / 60
    if hours > 0 {
        return "\(hours)h \(minutes)m"
    }
    if minutes > 0 {
        return "\(minutes)m"
    }
    return "<1m"
}
