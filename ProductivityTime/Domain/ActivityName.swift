import Foundation

struct ActivityName: Equatable, Hashable, Sendable {
    enum ValidationError: Error, Equatable {
        case empty
        case tooLong
    }

    let value: String

    init(_ rawValue: String) throws {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedValue.isEmpty else {
            throw ValidationError.empty
        }
        guard trimmedValue.count <= 80 else {
            throw ValidationError.tooLong
        }

        value = trimmedValue
    }
}
