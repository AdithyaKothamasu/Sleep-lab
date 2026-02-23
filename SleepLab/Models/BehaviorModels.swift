import Foundation

struct BehaviorTag: Identifiable, Hashable {
    let id: UUID
    let name: String
    let colorHex: String
    let isSystem: Bool
    let createdAt: Date
}

struct DayBehaviorLog: Identifiable, Hashable {
    let id: UUID
    let dayStart: Date
    let tagName: String
    let note: String?
    let loggedAt: Date
}
