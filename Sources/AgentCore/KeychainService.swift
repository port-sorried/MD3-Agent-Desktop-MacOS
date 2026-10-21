import Foundation
import Security

public enum KeychainService {
    private static let service = "dev.huecoder.md3agent.macos"
    public static func read(account: String) throws -> String {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return "" }
        try validate(status)
        guard let bytes = result as? Data, let secret = String(data: bytes, encoding: .utf8) else {
            throw AgentError.storage("invalid keychain item encoding")
        }
        return secret
    }
    public static func save(_ secret: String, account: String) throws {
        if secret.isEmpty { try delete(account: account); return }
        let query = baseQuery(account: account)
        let attributes: [String: Any] = [kSecValueData as String: Data(secret.utf8),
                                         kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            try validate(SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil))
        } else { try validate(status) }
    }
    public static func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        if status != errSecItemNotFound { try validate(status) }
    }
    private static func baseQuery(account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
    private static func validate(_ status: OSStatus) throws {
        guard status == errSecSuccess else {
            throw AgentError.storage("keychain: \(SecCopyErrorMessageString(status, nil) as String? ?? String(status))")
        }
    }
}
