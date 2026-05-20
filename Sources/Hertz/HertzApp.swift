import SwiftUI
import HertzCore

@main
struct HertzApp: App {
    @State private var model = MetricsModel()
    private let updater = UpdateChecker()

    init() {
        // Menu-bar only — no dock icon, no app window.
        NSApplication.shared.setActivationPolicy(.accessory)
        updater.start() // check GitHub Releases on launch + every 24h
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
