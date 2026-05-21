import SwiftUI
import ServiceManagement
import HertzCore

@main
struct HertzApp: App {
    @State private var model = MetricsModel()
    private let updater = UpdateChecker()

    init() {
        // Menu-bar only — no dock icon, no app window.
        NSApplication.shared.setActivationPolicy(.accessory)
        Self.enableLoginItemOnFirstLaunch()
        updater.start() // check GitHub Releases on launch + every 24h
    }

    /// On the very first run, register as a login item so Hertz starts with
    /// the Mac by default. The footer toggle lets the user turn it off — and
    /// this never overrides that choice on later launches.
    private static func enableLoginItemOnFirstLaunch() {
        guard Bundle.main.bundlePath.hasSuffix(".app") else { return } // skip dev runs
        let key = "didConfigureLoginItem"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        try? SMAppService.mainApp.register()
        UserDefaults.standard.set(true, forKey: key)
    }

    var body: some Scene {
        MenuBarExtra {
            DashboardView(model: model, updater: updater)
        } label: {
            Text("CPU \(model.cpu.total, format: .number.precision(.fractionLength(0)))%")
        }
        .menuBarExtraStyle(.window)
    }
}
