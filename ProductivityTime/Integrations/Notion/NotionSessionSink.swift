import Foundation
protocol NotionSessionSink: Sendable { func deliver(_ session: CompletedSession, configuration: NotionConfiguration) async throws -> DeliveryResult; func testConnection(configuration: NotionConfiguration) async throws }
protocol NotionCredentialStore: Sendable { func readToken() throws -> Data?; func writeToken(_ token: Data) throws; func removeToken() throws }
