import Foundation

struct NotesFormattedLine: Equatable, Sendable {
    let plainText: String
    let html: String
    let marker: String
}

struct NotesLineFormatter: Sendable {
    private let locale: Locale
    private var calendar: Calendar
    private let timeZone: TimeZone

    init(locale: Locale = .current, calendar: Calendar = .current, timeZone: TimeZone = .current) {
        self.locale = locale
        self.calendar = calendar
        self.timeZone = timeZone
        self.calendar.timeZone = timeZone
    }

    func format(_ session: CompletedSession) -> NotesFormattedLine {
        let mode = session.mode.rawValue
        let duration = durationText(session.duration)
        let date = dateText(session.completedAt)
        let plainTitle = session.titleSnapshot.replacingOccurrences(of: "\n", with: " ")
        let plainText = "\(plainTitle) — \(mode) — \(duration) — \(date)"
        let html = htmlEscaped(plainText)
        return NotesFormattedLine(plainText: plainText, html: html, marker: plainText)
    }

    private func durationText(_ duration: Duration) -> String {
        let seconds = max(0, Int(duration.timeInterval.rounded(.down)))
        return String(format: "%02d:%02d:%02d", seconds / 3_600, (seconds % 3_600) / 60, seconds % 60)
    }

    private func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    private func htmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
