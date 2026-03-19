import AppKit
import SwiftUI

/// Main app delegate — manages the NSStatusItem (menu bar icon) and floating panel.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: NSPanel!
    private var eventMonitor: Any?

    // Shared services
    private(set) var databaseService: DatabaseService!
    private(set) var clipboardMonitor: ClipboardMonitor!
    private(set) var licenseService: LicenseService!

    // Shared view model
    private(set) var clipboardViewModel: ClipboardViewModel!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // ── Initialize services ──
        databaseService = DatabaseService()
        licenseService = LicenseService()
        clipboardMonitor = ClipboardMonitor(databaseService: databaseService, licenseService: licenseService)

        // ── Initialize view model ──
        clipboardViewModel = ClipboardViewModel(
            databaseService: databaseService,
            licenseService: licenseService
        )

        // Close panel callback for views
        clipboardViewModel.onDismiss = { [weak self] in
            self?.hidePanel()
        }

        // ── Start clipboard monitoring ──
        clipboardMonitor.onClipboardChange = { [weak self] in
            self?.clipboardViewModel.refreshHistory()
        }
        clipboardMonitor.startMonitoring()

        // ── Validate license on startup ──
        Task {
            await licenseService.validate()
            await MainActor.run {
                clipboardViewModel.refreshLicenseStatus()
            }
        }

        // ── Set up menu bar icon ──
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "paperclip", accessibilityDescription: "SmartClip")
            button.image?.size = NSSize(width: 18, height: 18)
            button.image?.isTemplate = true
            button.action = #selector(togglePanel)
            button.target = self
        }

        // ── Set up floating panel ──
        setupPanel()
    }

    // MARK: - Panel Setup

    private func setupPanel() {
        let panelWidth: CGFloat = 360

        panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: 400),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: true
        )

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isMovableByWindowBackground = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let hostingView = NSHostingView(
            rootView: ContentView()
                .environmentObject(clipboardViewModel)
        )
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear

        panel.contentView = hostingView
    }

    // MARK: - Show / Hide

    @MainActor @objc private func togglePanel() {
        if panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    @MainActor private func showPanel() {
        clipboardViewModel.refreshHistory()

        // Calculate panel height based on items
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let menuBarHeight: CGFloat = NSApp.mainMenu?.menuBarHeight ?? 24
        let maxHeight = screen.visibleFrame.height
        let itemCount = max(clipboardViewModel.itemCount, 1)
        let contentHeight: CGFloat = 50 + 50 + CGFloat(itemCount) * 56 + 60 + 36 // header + search + items + footer + padding
        let panelHeight = min(contentHeight, maxHeight)

        // Position panel below the status item
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let panelX = buttonFrame.midX - 360 / 2
        let panelY = buttonFrame.minY - panelHeight

        panel.setFrame(NSRect(x: panelX, y: panelY, width: 360, height: panelHeight), display: true)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Monitor clicks outside the panel to close it
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hidePanel()
        }
    }

    @MainActor private func hidePanel() {
        panel.orderOut(nil)
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}
