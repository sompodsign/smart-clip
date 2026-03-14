import Foundation

enum LicenseTier: String, Codable {
    case free = "Free"
    case proActive = "ProActive"
    case proGrace = "ProGrace"
}

enum LicenseStatus: String, Codable {
    case active = "Active"
    case inactive = "Inactive"
    case expired = "Expired"
    case disabled = "Disabled"
    case unknown = "Unknown"
}

struct LicenseEntitlement {
    let tier: LicenseTier
    let message: String
    let isUnlimited: Bool
    let graceExpiresAt: Int64?

    static func free() -> LicenseEntitlement {
        LicenseEntitlement(tier: .free, message: "Free tier (5 clipboard items)", isUnlimited: false, graceExpiresAt: nil)
    }

    static func proActive(graceExpiresAt: Int64? = nil) -> LicenseEntitlement {
        LicenseEntitlement(tier: .proActive, message: "Pro Active", isUnlimited: true, graceExpiresAt: graceExpiresAt)
    }

    static func proGrace(graceExpiresAt: Int64, remainingDays: Int64) -> LicenseEntitlement {
        LicenseEntitlement(tier: .proGrace, message: "Pro Grace (\(remainingDays) days left)", isUnlimited: true, graceExpiresAt: graceExpiresAt)
    }
}

struct LicenseState: Codable {
    var licenseKey: String
    var instanceId: String
    var lastValidatedAt: Int64?
    var graceExpiresAt: Int64?
    var lastKnownStatus: LicenseStatus

    enum CodingKeys: String, CodingKey {
        case licenseKey = "license_key"
        case instanceId = "instance_id"
        case lastValidatedAt = "last_validated_at"
        case graceExpiresAt = "grace_expires_at"
        case lastKnownStatus = "last_known_status"
    }
}

struct LicenseConfig {
    var storeId: UInt64
    var productId: UInt64
    var monthlyCheckoutUrl: String
    var yearlyCheckoutUrl: String
    var customerPortalUrl: String
    var offlineGraceDays: Int64
    var validationIntervalHours: Int64

    static func fromEnvironment() -> LicenseConfig {
        let env = { (key: String, fallback: String) -> String in
            ProcessInfo.processInfo.environment[key] ?? fallback
        }
        return LicenseConfig(
            storeId: UInt64(env("LS_STORE_ID", "0")) ?? 0,
            productId: UInt64(env("LS_PRODUCT_ID", "0")) ?? 0,
            monthlyCheckoutUrl: env("LS_MONTHLY_CHECKOUT_URL", ""),
            yearlyCheckoutUrl: env("LS_YEARLY_CHECKOUT_URL", ""),
            customerPortalUrl: env("LS_CUSTOMER_PORTAL_URL", "https://app.lemonsqueezy.com/my-orders"),
            offlineGraceDays: Int64(env("LS_OFFLINE_GRACE_DAYS", "7")) ?? 7,
            validationIntervalHours: Int64(env("LS_VALIDATION_INTERVAL_HOURS", "12")) ?? 12
        )
    }
}
