import CoreData
import Foundation

final class PersistenceController {
    enum EntityName {
        static let tagDefinition = "TagDefinitionEntity"
        static let dayTagLog = "DayTagLogEntity"
    }

    static let shared = PersistenceController()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        let managedObjectModel = Self.makeManagedObjectModel()
        container = NSPersistentContainer(name: "SleepLab", managedObjectModel: managedObjectModel)

        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }

        if let description = container.persistentStoreDescriptions.first {
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
        }

        container.loadPersistentStores { _, error in
            if let error {
                fatalError("Persistent store failed to load: \(error.localizedDescription)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    private static func makeManagedObjectModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        let tagDefinition = NSEntityDescription()
        tagDefinition.name = EntityName.tagDefinition
        tagDefinition.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        tagDefinition.properties = [
            makeAttribute(name: "id", type: .UUIDAttributeType),
            makeAttribute(name: "name", type: .stringAttributeType),
            makeAttribute(name: "colorHex", type: .stringAttributeType),
            makeAttribute(name: "isSystem", type: .booleanAttributeType),
            makeAttribute(name: "createdAt", type: .dateAttributeType)
        ]
        tagDefinition.uniquenessConstraints = [["name"]]

        let dayTagLog = NSEntityDescription()
        dayTagLog.name = EntityName.dayTagLog
        dayTagLog.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        dayTagLog.properties = [
            makeAttribute(name: "id", type: .UUIDAttributeType),
            makeAttribute(name: "dayStart", type: .dateAttributeType),
            makeAttribute(name: "tagName", type: .stringAttributeType),
            makeAttribute(name: "note", type: .stringAttributeType, isOptional: true),
            makeAttribute(name: "loggedAt", type: .dateAttributeType)
        ]

        model.entities = [tagDefinition, dayTagLog]
        return model
    }

    private static func makeAttribute(name: String, type: NSAttributeType, isOptional: Bool = false) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = isOptional
        return attribute
    }
}
