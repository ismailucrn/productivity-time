import Foundation

struct NotionConfiguration: Equatable, Sendable {
    let dataSourceID: String
    static let expectedProperties = ["Name": "title", "Mode": "rich_text", "Duration": "rich_text", "Date": "date", "Session ID": "rich_text"]
    init(dataSourceID: String) { self.dataSourceID = dataSourceID.trimmingCharacters(in: .whitespacesAndNewlines) }
}
