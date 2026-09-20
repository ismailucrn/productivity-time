import Foundation
import SwiftData

@Model
final class ActivityRecord {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var normalizedName: String
    var name: String
    var createdAt: Date

    init(id: UUID, name: String, createdAt: Date) {
        self.id = id
        self.normalizedName = name.folding(options: [.caseInsensitive], locale: .current)
        self.name = name
        self.createdAt = createdAt
    }

    var activity: Activity {
        Activity(id: id, name: try! ActivityName(name), createdAt: createdAt)
    }
}
