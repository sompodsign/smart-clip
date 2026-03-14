import Foundation
import Security
import os

/// Wrapper around macOS Security.framework Keychain APIs.
/// Uses the same service/account names as the Rust `keyring` crate for backward compatibility.
enum KeychainService {
    private static let logger = Logger(subsystem: Constants.bundleIdentifier, category: "Keychain")

    static func loadLicenseState() -> LicenseState? {
        guard let data = load(service: Constants.keychainService, account: Constants.keychainAccount) else { return nil }
        return try? JSONDecoder().decode(LicenseState.self, from: data)
    }

    static func saveLicenseState(_ state: LicenseState) {
        guard let data = try? JSONEncoder().encode(state) else {
            logger.error("Failed to encode license state")
            return
        }
        save(service: Constants.keychainService, account: Constants.keychainAccount, data: data)
    }

    static func deleteLicenseState() {
        delete(service: Constants.keychainService, account: Constants.keychainAccount)
    }

    private static func load(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            if status != errSecItemNotFound { logger.error("Keychain load error: \(status)") }
            return nil
        }
        return data
    }

    private static func save(service: String, account: String, data: Data) {
        delete(service: service, account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess { logger.error("Keychain save error: \(status)") }
    }

    private static func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound { logger.error("Keychain delete error: \(status)") }
    }
}
