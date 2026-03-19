import AppKit

/// A custom NSPanel subclass that can become key, allowing text fields
/// and other first responders to receive keyboard input even when the
/// panel uses `.nonactivatingPanel` style mask.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
