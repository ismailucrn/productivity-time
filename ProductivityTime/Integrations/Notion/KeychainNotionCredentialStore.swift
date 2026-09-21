import Foundation
import Security

enum NotionCredentialError: Error, Equatable, Sendable { case unavailable, unexpected }
enum KeychainStatus: Error, Equatable, Sendable { case success, itemNotFound, failure }
protocol KeychainSecurityClient: Sendable {
    func read(service: String, account: String) -> Result<Data?, KeychainStatus>
    func update(service: String, account: String, token: Data) -> KeychainStatus
    func add(service: String, account: String, token: Data, accessibility: CFString) -> KeychainStatus
    func delete(service: String, account: String) -> KeychainStatus
}
struct SystemKeychainSecurityClient: KeychainSecurityClient, @unchecked Sendable {
    func read(service: String, account: String) -> Result<Data?, KeychainStatus> { var result: CFTypeRef?; let status = SecItemCopyMatching([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account, kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne] as CFDictionary, &result); if status == errSecItemNotFound { return .success(nil) }; return status == errSecSuccess ? .success(result as? Data) : .failure(.failure) }
    func update(service: String, account: String, token: Data) -> KeychainStatus { status(SecItemUpdate([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account] as CFDictionary, [kSecValueData: token, kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly] as CFDictionary)) }
    func add(service: String, account: String, token: Data, accessibility: CFString) -> KeychainStatus { status(SecItemAdd([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account, kSecValueData: token, kSecAttrAccessible: accessibility] as CFDictionary, nil)) }
    func delete(service: String, account: String) -> KeychainStatus { status(SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account] as CFDictionary)) }
    private func status(_ value: OSStatus) -> KeychainStatus { value == errSecSuccess ? .success : value == errSecItemNotFound ? .itemNotFound : .failure }
}
struct KeychainNotionCredentialStore: NotionCredentialStore, @unchecked Sendable {
    static let service = "com.ismailucrn.ProductivityTime.notion"; static let account = "internal-integration-token"
    private let client: any KeychainSecurityClient
    init(client: any KeychainSecurityClient = SystemKeychainSecurityClient()) { self.client = client }
    func readToken() throws -> Data? { switch client.read(service: Self.service, account: Self.account) { case let .success(value): return value; case .failure: throw NotionCredentialError.unavailable } }
    func writeToken(_ token: Data) throws {
        switch client.update(service: Self.service, account: Self.account, token: token) { case .success: return; case .itemNotFound: guard client.add(service: Self.service, account: Self.account, token: token, accessibility: kSecAttrAccessibleWhenUnlockedThisDeviceOnly) == .success else { throw NotionCredentialError.unavailable }; case .failure: throw NotionCredentialError.unavailable }
    }
    func removeToken() throws { let status = client.delete(service: Self.service, account: Self.account); guard status == .success || status == .itemNotFound else { throw NotionCredentialError.unavailable } }
}
