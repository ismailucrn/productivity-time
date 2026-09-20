import Foundation

struct ActivityName: Equatable, Hashable, Sendable {
    enum ValidationError: Error, Equatable {
        case empty
        case tooLong
    }

    let value: String

    static func stableCaseInsensitiveKey(_ value: String) -> String {
        value.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

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
