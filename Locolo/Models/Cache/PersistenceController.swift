//
//  PersistenceController.swift
//  Locolo
//
//  Created by Apramjot Singh on 10/11/2025.
//

import CoreData

enum PersistenceController {
    static let modelName = "LocoloCache"

    // Just our shared persistent container for Core Dat, I mean if it is throwing an error then we dont have any offline functionality.
    static let shared: NSPersistentContainer = {
        guard let modelURL = Bundle.main.url(forResource: modelName, withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: modelURL) else {
            fatalError(" Failed to locate Core Data model \(modelName).xcdatamodeld in bundle.")
        }

        let container = NSPersistentContainer(name: modelName, managedObjectModel: model)
        container.loadPersistentStores { description, error in
            if let error = error {
                fatalError(" Core Data store failed to load: \(error)")
            }
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
        }
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true
        return container
    }()

 
    static var viewContext: NSManagedObjectContext {
        shared.viewContext
    }

    static func newBackgroundContext() -> NSManagedObjectContext {
        let context = shared.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy
        context.automaticallyMergesChangesFromParent = true
        return context
    }
    
    
}

