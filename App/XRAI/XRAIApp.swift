// XRAI — native iOS host (P03-00). SwiftUI, iOS 17+, Swift 6 strict concurrency.
// This build is a HOST SKELETON: five tabs, honest security status, no personal data stored.
import SwiftUI

@main
struct XRAIApp: App {
    @State private var security = SecurityStatus()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(security)
                .task { security.bootstrap() }
        }
        .onChange(of: scenePhase) { _, phase in
            // Key cache hygiene: drop unwrapped KEKs whenever the app leaves the foreground.
            if phase != .active { security.purgeKeyCache() }
        }
    }
}
