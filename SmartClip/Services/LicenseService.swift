import Foundation
import os

/// Manages LemonSqueezy license activation, validation, and deactivation.
final class LicenseService {
    private let config: LicenseConfig
    private var state: LicenseState?
    private let logger = Logger(subsystem: Constants.bundleIdentifier, category: "License")
    private var validationTimer: Timer?

    init() {
        self.config = LicenseConfig.fromEnvironment()
        self.state = KeychainService.loadLicenseState()
        logger.info("LicenseService initialized. Has stored state: \(self.state != nil)")
    }

    func currentEntitlement() -> LicenseEntitlement {
        let now = Int64(Date().timeIntervalSince1970)
        guard let state = state else { return .free() }

        switch state.lastKnownStatus {
        case .active:
            if let grace = state.graceExpiresAt, now > grace { return .free() }
            return .proActive(graceExpiresAt: state.graceExpiresAt)
        case .unknown:
            if let grace = state.graceExpiresAt, now <= grace {
                let remaining = Int64(ceil(Double(grace - now) / 86400.0))
                return .proGrace(graceExpiresAt: grace, remainingDays: max(remaining, 0))
            }
            return .free()
        default:
            return .free()
        }
    }

    func activate(key: String) async throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LicenseError.emptyKey }

        let instanceName = Host.current().localizedName ?? "SmartClip Mac"
        let url = URL(string: "\(Constants.lemonSqueezyAPIBase)/v1/licenses/activate")!
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "license_key=\(urlEncode(trimmed))&instance_name=\(urlEncode(instanceName))".data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        if let errorMsg = payload["error"] as? String, !errorMsg.isEmpty {
            throw LicenseError.apiError(mapAPIError(errorMsg))
        }
        guard payload["activated"] as? Bool == true else { throw LicenseError.rejected }
        guard let instance = payload["instance"] as? [String: Any] else { throw LicenseError.missingInstance }

        let instanceId: String
        if let idStr = instance["id"] as? String { instanceId = idStr }
        else if let idNum = instance["id"] as? Int64 { instanceId = String(idNum) }
        else { throw LicenseError.missingInstance }

        let now = Int64(Date().timeIntervalSince1970)
        let grace = now + (config.offlineGraceDays * 86400)
        let newState = LicenseState(licenseKey: trimmed, instanceId: instanceId, lastValidatedAt: now, graceExpiresAt: grace, lastKnownStatus: .active)
        KeychainService.saveLicenseState(newState)
        self.state = newState
        logger.info("License activated successfully.")
    }

    @discardableResult
    func validate() async -> LicenseEntitlement {
        guard let state = state, !state.licenseKey.isEmpty, !state.instanceId.isEmpty else { return .free() }

        let url = URL(string: "\(Constants.lemonSqueezyAPIBase)/v1/licenses/validate")!
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "license_key=\(urlEncode(state.licenseKey))&instance_id=\(urlEncode(state.instanceId))".data(using: .utf8)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

            if let errorMsg = payload["error"] as? String, !errorMsg.isEmpty { clearState(reason: "invalid"); return .free() }
            guard payload["valid"] as? Bool == true else { clearState(reason: "invalid"); return .free() }

            let licenseKeyObj = payload["license_key"] as? [String: Any] ?? [:]
            let statusStr = (licenseKeyObj["status"] as? String)?.lowercased() ?? "unknown"
            guard statusStr == "active" else { clearState(reason: statusStr); return .free() }

            if config.storeId > 0, config.productId > 0 {
                let meta = payload["meta"] as? [String: Any]
                let storeId = (meta?["store_id"] as? UInt64) ?? (licenseKeyObj["store_id"] as? UInt64)
                let productId = (meta?["product_id"] as? UInt64) ?? (licenseKeyObj["product_id"] as? UInt64)
                if storeId != config.storeId || productId != config.productId { clearState(reason: "product_mismatch"); return .free() }
            }

            let now = Int64(Date().timeIntervalSince1970)
            let grace = now + (config.offlineGraceDays * 86400)
            let newState = LicenseState(licenseKey: state.licenseKey, instanceId: state.instanceId, lastValidatedAt: now, graceExpiresAt: grace, lastKnownStatus: .active)
            KeychainService.saveLicenseState(newState)
            self.state = newState
            logger.info("Validation succeeded.")
            return .proActive(graceExpiresAt: grace)
        } catch {
            logger.warning("Validation network error: \(error)")
            let now = Int64(Date().timeIntervalSince1970)
            if let grace = state.graceExpiresAt, now <= grace {
                var s = state
                s.lastKnownStatus = .unknown
                KeychainService.saveLicenseState(s)
                self.state = s
                let remaining = Int64(ceil(Double(grace - now) / 86400.0))
                return .proGrace(graceExpiresAt: grace, remainingDays: max(remaining, 0))
            }
            clearState(reason: "network_grace_expired")
            return .free()
        }
    }

    func deactivate() async throws {
        guard let state = state else { return }
        let url = URL(string: "\(Constants.lemonSqueezyAPIBase)/v1/licenses/deactivate")!
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "license_key=\(urlEncode(state.licenseKey))&instance_id=\(urlEncode(state.instanceId))".data(using: .utf8)
        defer { clearState(reason: "user_deactivated") }
        let (data, _) = try await URLSession.shared.data(for: request)
        let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        if let errorMsg = payload["error"] as? String, !errorMsg.isEmpty { logger.warning("Remote deactivation error: \(errorMsg)") }
        logger.info("License deactivated.")
    }

    func checkoutUrl(cycle: String) -> String? {
        switch cycle {
        case "monthly": return config.monthlyCheckoutUrl.isEmpty ? nil : config.monthlyCheckoutUrl
        case "yearly": return config.yearlyCheckoutUrl.isEmpty ? nil : config.yearlyCheckoutUrl
        default: return nil
        }
    }

    var customerPortalUrl: String { config.customerPortalUrl }

    func startPeriodicValidation() {
        let interval = TimeInterval(config.validationIntervalHours * 3600)
        validationTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { [weak self] in await self?.validate() }
        }
    }

    private func clearState(reason: String) {
        KeychainService.deleteLicenseState()
        state = nil
        logger.info("License state cleared. reason=\(reason)")
    }

    private func urlEncode(_ string: String) -> String {
        string.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? string
    }

    private func mapAPIError(_ msg: String) -> String {
        let lower = msg.lowercased()
        if lower.contains("invalid") || lower.contains("not found") { return "Invalid license key. Please check and try again." }
        else if lower.contains("expired") { return "This subscription has expired." }
        else if lower.contains("disabled") { return "This license key is disabled." }
        else if lower.contains("inactive") { return "This license key is inactive." }
        return msg
    }
}

enum LicenseError: Error, LocalizedError {
    case emptyKey, rejected, missingInstance, apiError(String)
    var errorDescription: String? {
        switch self {
        case .emptyKey: return "License key cannot be empty."
        case .rejected: return "License activation was rejected."
        case .missingInstance: return "Missing instance in response."
        case .apiError(let msg): return msg
        }
    }
}
