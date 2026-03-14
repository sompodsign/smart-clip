import Foundation

enum Constants {
    static let pollIntervalSeconds: TimeInterval = 0.5
    static let freeTierLimit: Int64 = 5
    static let defaultMaxItems: Int64 = 50
    static let panelWidth: CGFloat = 340
    static let panelMinHeight: CGFloat = 200
    static let panelMaxHeight: CGFloat = 600
    static let headerHeight: CGFloat = 40
    static let searchHeight: CGFloat = 80
    static let itemHeight: CGFloat = 56
    static let footerHeight: CGFloat = 74
    static let listPadding: CGFloat = 8
    static let thumbnailSize: CGFloat = 100
    static let keychainService = "com.smartclip.app.license"
    static let keychainAccount = "license_state_v2"
    static let lemonSqueezyAPIBase = "https://api.lemonsqueezy.com"
    static let bundleIdentifier = "com.smartclip.desktop"
}
