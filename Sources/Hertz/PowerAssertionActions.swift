import AppKit
import Foundation
import HertzCore

enum PowerAssertionActions {
    static func copyReport(_ snapshot: PowerAssertionsSnapshot) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(powerAssertionsReport(snapshot), forType: .string)
    }

    static func copyReport(for group: PowerAssertionGroup) {
        let snapshot = PowerAssertionsSnapshot(groups: [group],
                                               totalAssertions: group.assertions.count)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(powerAssertionsReport(snapshot), forType: .string)
    }

    static func canReveal(_ group: PowerAssertionGroup) -> Bool {
        revealURL(for: group) != nil
    }

    @discardableResult
    static func reveal(_ group: PowerAssertionGroup) -> Bool {
        guard let url = revealURL(for: group) else { return false }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        return true
    }

    static func openActivityMonitor() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    private static func revealURL(for group: PowerAssertionGroup) -> URL? {
        guard !group.processPath.isEmpty else { return nil }
        let path: String
        if let range = group.processPath.range(of: ".app/") {
            path = String(group.processPath[..<range.lowerBound]) + ".app"
        } else {
            path = group.processPath
        }
        return URL(fileURLWithPath: path)
    }
}
