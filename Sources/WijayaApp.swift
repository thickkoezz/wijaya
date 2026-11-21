import SwiftUI

@main
struct WijayaApp: App {
    init() {
        DiagnosticsCLI.runIfRequested()
    }

    var body: some Scene {
        WindowGroup("Wijaya — NTFS Mount") {
            ContentView()
        }
        .defaultSize(width: 880, height: 620)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Refresh Volumes") {
                    NotificationCenter.default.post(name: .wijayaRefresh, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    static let wijayaRefresh = Notification.Name("dev.mieky.wijaya.refresh")
}
