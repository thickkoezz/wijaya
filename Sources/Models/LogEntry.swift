import Foundation

struct LogEntry: Identifiable, Sendable {
    enum Level: Sendable {
        case info
        case success
        case error
    }

    let id = UUID()
    let date: Date
    let level: Level
    let message: String

    init(level: Level, message: String, date: Date = Date()) {
        self.level = level
        self.message = message
        self.date = date
    }

    var timestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}
