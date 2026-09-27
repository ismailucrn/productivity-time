import Foundation
import SwiftData

@Model
final class ActivityRecord {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var normalizedName: String
    var name: String
    var createdAt: Date
    // Optional so stores created before pinning can open without a custom
    // migration. A missing legacy value is interpreted as unpinned.
    var isPinned: Bool?

    init(id: UUID, name: String, createdAt: Date, isPinned: Bool = false) {
        self.id = id
        self.normalizedName = ActivityName.stableCaseInsensitiveKey(name)
        self.name = name
        self.createdAt = createdAt
        self.isPinned = isPinned
    }

    var activity: Activity {
        Activity(id: id, name: try! ActivityName(name), createdAt: createdAt, isPinned: isPinned ?? false)
    }
}
