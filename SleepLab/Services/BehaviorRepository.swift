import CoreData
import Foundation

@MainActor
final class BehaviorRepository: ObservableObject {
    private let context: NSManagedObjectContext
    private var calendar = Calendar(identifier: .gregorian)

    init(context: NSManagedObjectContext) {
        self.context = context
        calendar.timeZone = .current
    }

    func seedDefaultTagsIfNeeded() throws {
        let request = NSFetchRequest<NSManagedObject>(entityName: PersistenceController.EntityName.tagDefinition)
        let existing = try context.fetch(request)

        let existingNames = Set(
            existing.compactMap { ($0.value(forKey: "name") as? String)?.lowercased() }
        )

        let defaultTags: [(name: String, colorHex: String)] = [
            ("Workout", "#2FA56A"),
            ("Dinner", "#4A7DF0"),
            ("Caffeine", "#D97B2A")
        ]

        for tag in defaultTags where !existingNames.contains(tag.name.lowercased()) {
            let object = NSEntityDescription.insertNewObject(
                forEntityName: PersistenceController.EntityName.tagDefinition,
                into: context
            )
            object.setValue(UUID(), forKey: "id")
            object.setValue(tag.name, forKey: "name")
            object.setValue(tag.colorHex, forKey: "colorHex")
            object.setValue(true, forKey: "isSystem")
            object.setValue(Date(), forKey: "createdAt")
        }

        for object in existing {
            let isSystem = object.value(forKey: "isSystem") as? Bool ?? false
            let name = (object.value(forKey: "name") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if isSystem && name.caseInsensitiveCompare("Stress") == .orderedSame {
                context.delete(object)
            }
        }

        if context.hasChanges {
            try context.save()
        }
    }

    func fetchTags() throws -> [BehaviorTag] {
        let request = NSFetchRequest<NSManagedObject>(entityName: PersistenceController.EntityName.tagDefinition)
        request.sortDescriptors = [
            NSSortDescriptor(key: "isSystem", ascending: false),
            NSSortDescriptor(key: "name", ascending: true)
        ]

        let objects = try context.fetch(request)

        return objects.compactMap { object in
            guard let id = object.value(forKey: "id") as? UUID,
                  let name = object.value(forKey: "name") as? String,
                  let colorHex = object.value(forKey: "colorHex") as? String,
                  let isSystem = object.value(forKey: "isSystem") as? Bool,
                  let createdAt = object.value(forKey: "createdAt") as? Date else {
                return nil
            }

            return BehaviorTag(
                id: id,
                name: name,
                colorHex: colorHex,
                isSystem: isSystem,
                createdAt: createdAt
            )
        }
    }

    func addCustomTag(name: String, colorHex: String) throws {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty else { return }

        let request = NSFetchRequest<NSManagedObject>(entityName: PersistenceController.EntityName.tagDefinition)
        request.predicate = NSPredicate(format: "name =[c] %@", cleanedName)
        request.fetchLimit = 1

        if try context.fetch(request).isEmpty {
            let object = NSEntityDescription.insertNewObject(
                forEntityName: PersistenceController.EntityName.tagDefinition,
                into: context
            )
            object.setValue(UUID(), forKey: "id")
            object.setValue(cleanedName, forKey: "name")
            object.setValue(colorHex, forKey: "colorHex")
            object.setValue(false, forKey: "isSystem")
            object.setValue(Date(), forKey: "createdAt")
            try context.save()
        }
    }

    func fetchLogs(for dayStart: Date) throws -> [DayBehaviorLog] {
        let normalizedDayStart = calendar.startOfDay(for: dayStart)

        let request = NSFetchRequest<NSManagedObject>(entityName: PersistenceController.EntityName.dayTagLog)
        request.predicate = NSPredicate(format: "dayStart == %@", normalizedDayStart as NSDate)
        request.sortDescriptors = [NSSortDescriptor(key: "loggedAt", ascending: false)]

        return try context.fetch(request).compactMap { object in
            guard let id = object.value(forKey: "id") as? UUID,
                  let persistedDayStart = object.value(forKey: "dayStart") as? Date,
                  let tagName = object.value(forKey: "tagName") as? String,
                  let loggedAt = object.value(forKey: "loggedAt") as? Date else {
                return nil
            }

            return DayBehaviorLog(
                id: id,
                dayStart: persistedDayStart,
                tagName: tagName,
                note: object.value(forKey: "note") as? String,
                loggedAt: loggedAt
            )
        }
    }

    func addLog(for dayStart: Date, tagName: String, note: String?, eventTime: Date) throws {
        let object = NSEntityDescription.insertNewObject(
            forEntityName: PersistenceController.EntityName.dayTagLog,
            into: context
        )

        let cleanedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let eventTimestamp = timestamp(on: dayStart, from: eventTime)

        object.setValue(UUID(), forKey: "id")
        object.setValue(calendar.startOfDay(for: dayStart), forKey: "dayStart")
        object.setValue(tagName, forKey: "tagName")
        object.setValue(cleanedNote?.isEmpty == true ? nil : cleanedNote, forKey: "note")
        object.setValue(eventTimestamp, forKey: "loggedAt")

        try context.save()
    }

    func deleteLog(id: UUID) throws {
        let request = NSFetchRequest<NSManagedObject>(entityName: PersistenceController.EntityName.dayTagLog)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1

        guard let object = try context.fetch(request).first else { return }
        context.delete(object)
        try context.save()
    }

    private func timestamp(on dayStart: Date, from time: Date) -> Date {
        let dayComponents = calendar.dateComponents([.year, .month, .day], from: dayStart)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)

        var combined = DateComponents()
        combined.year = dayComponents.year
        combined.month = dayComponents.month
        combined.day = dayComponents.day
        combined.hour = timeComponents.hour
        combined.minute = timeComponents.minute

        return calendar.date(from: combined) ?? dayStart
    }
}
