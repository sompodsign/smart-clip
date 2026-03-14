import SwiftUI

@main
struct SmartClipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No main window — we use NSStatusItem + NSPopover
        Settings {
            EmptyView()
        }
    }
}
