import Foundation
import Security

enum NotionCredentialError: Error, Equatable, Sendable { case unavailable, unexpected }
struct KeychainNotionCredentialStore: NotionCredentialStore, @unchecked Sendable {
    static let service = "com.ismailucrn.ProductivityTime.notion"; static let account = "internal-integration-token"
    func readToken() throws -> Data? {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: Self.service, kSecAttrAccount: Self.account, kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne]
        var result: CFTypeRef?; let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }; guard status == errSecSuccess, let data = result as? Data else { throw NotionCredentialError.unavailable }; return data
    }
    func writeToken(_ token: Data) throws {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: Self.service, kSecAttrAccount: Self.account]
        SecItemDelete(query as CFDictionary)
        var values = query; values[kSecValueData] = token; values[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(values as CFDictionary, nil) == errSecSuccess else { throw NotionCredentialError.unavailable }
    }
    func removeToken() throws { let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: Self.service, kSecAttrAccount: Self.account]; let status = SecItemDelete(query as CFDictionary); guard status == errSecSuccess || status == errSecItemNotFound else { throw NotionCredentialError.unavailable } }
}
