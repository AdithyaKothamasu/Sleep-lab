import SwiftUI

@main
struct SleepLabApp: App {
    private let persistenceController: PersistenceController
    @StateObject private var viewModel: SleepLabViewModel

    init() {
        let persistence = PersistenceController.shared
        let behaviorRepository = BehaviorRepository(context: persistence.container.viewContext)

        self.persistenceController = persistence
        _viewModel = StateObject(
            wrappedValue: SleepLabViewModel(
                healthKitService: .shared,
                behaviorRepository: behaviorRepository
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(viewModel)
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
