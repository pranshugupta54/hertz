import AppKit
import Foundation
import Observation

/// Checks GitHub Releases on launch, every 24h, and on demand. When a newer
/// release exists it downloads the prebuilt app, swaps it in, and relaunches.
@Observable
@MainActor
final class UpdateChecker {
    static let repo = "pranshugupta54/hertz"

    enum Status: Equatable {
        case idle
        case checking
        case updating
        case message(String) // a transient line shown in the footer
    }

    var status: Status = .idle

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// Background loop — launch, then once a day. Silent.
    func start() {
        guard Bundle.main.bundlePath.hasSuffix(".app") else { return } // skip dev runs
        Task {
            while !Task.isCancelled {
                if let url = try? await findUpdate() {
                    try? await applyUpdate(from: url)
                }
                try? await Task.sleep(for: .seconds(24 * 60 * 60))
            }
        }
    }

    /// Manual "check now" from the footer button — gives UI feedback.
    func checkNow() async {
        switch status {
        case .checking, .updating: return // already busy
        case .idle, .message: break
        }
        status = .checking
        do {
            if let url = try await findUpdate() {
                status = .updating
                try await applyUpdate(from: url) // quits + relaunches
            } else {
                await flash("Latest version")
            }
        } catch {
            await flash("Check failed")
        }
    }

    private func flash(_ text: String) async {
        status = .message(text)
        try? await Task.sleep(for: .seconds(7))
        if status == .message(text) { status = .idle }
    }

    // MARK: - GitHub release lookup

    private struct Release: Decodable {
        let tagName: String
        let assets: [Asset]
        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case assets
        }
        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: String
            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }
    }

    /// Returns the download URL of a newer release, or nil if up to date.
    private func findUpdate() async throws -> URL? {
        guard let release = try await latestRelease() else { return nil }
        let latest = release.tagName.trimmingCharacters(
            in: CharacterSet(charactersIn: "v"))
        guard isNewer(latest, than: currentVersion),
              let asset = release.assets.first(where: { $0.name.hasSuffix(".zip") }),
              let url = URL(string: asset.browserDownloadURL)
        else { return nil }
        return url
    }

    private func latestRelease() async throws -> Release? {
        guard let api = URL(string:
            "https://api.github.com/repos/\(Self.repo)/releases/latest") else { return nil }
        var request = URLRequest(url: api)
        request.setValue("Hertz", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try JSONDecoder().decode(Release.self, from: data)
    }

    /// Numeric semver comparison: "0.10.0" > "0.9.0".
    private func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: - Download + self-replace

    private func applyUpdate(from url: URL) async throws {
        let (downloaded, _) = try await URLSession.shared.download(from: url)

        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("hertz-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let zip = work.appendingPathComponent("Hertz.app.zip")
        try FileManager.default.moveItem(at: downloaded, to: zip)

        // ditto preserves bundle structure correctly.
        try run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])
        let newApp = work.appendingPathComponent("Hertz.app")
        guard FileManager.default.fileExists(atPath: newApp.path) else { return }
        try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newApp.path])

        // A running app can't overwrite its own bundle — a detached script
        // waits for this process to quit, then swaps and relaunches.
        let dest = Bundle.main.bundlePath
        let swap = work.appendingPathComponent("swap.sh")
        let script = """
        #!/bin/bash
        sleep 2
        rm -rf "\(dest)"
        mv "\(newApp.path)" "\(dest)"
        xattr -dr com.apple.quarantine "\(dest)" 2>/dev/null || true
        open "\(dest)"
        """
        try script.write(to: swap, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [swap.path]
        try process.run() // detached: not awaited; survives our exit

        NSApplication.shared.terminate(nil)
    }

    private func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
    }
}
