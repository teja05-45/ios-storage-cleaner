//
//  ReclaimApp.swift
//  Reclaim
//
//  Document 03 §2: NavigationStack-based SwiftUI app, iOS 17+,
//  @Observable ViewModels. AppEnvironment is constructed once here and
//  handed down — no ViewModel constructs its own services.
//

import SwiftUI

@main
struct ReclaimApp: App {
    @State private var environment = AppEnvironment.live()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            DashboardView(viewModel: DashboardViewModel(environment: environment))
                // Leaf UI components (AssetThumbnailView) reach the
                // composition root through the SwiftUI environment — see
                // UI/Components/AppEnvironmentKey.swift for why.
                .environment(\.appEnvironment, environment)
        }
        .onChange(of: scenePhase) { _, newPhase in
            // ADR-04 / Document 07 §8: permission state is re-checked on
            // every foreground re-entry, never assumed to still hold from
            // when the app last ran. DashboardViewModel owns the actual
            // re-check (it holds the ViewModel state that needs updating);
            // this hook exists so the mechanism is visible at the app-root
            // level, not buried only inside one screen.
            if newPhase == .active {
                NotificationCenter.default.post(name: .reclaimDidBecomeActive, object: nil)
            }
        }
    }
}

extension Notification.Name {
    static let reclaimDidBecomeActive = Notification.Name("com.reclaim.didBecomeActive")
}
