// XRAI — native iOS host (P03-00 / P03-01). SwiftUI, iOS 17+, Swift 6 strict concurrency.
// No personal data is persisted in this phase. Onboarding completion is a non-personal flag.
import SwiftUI

@main
struct XRAIApp: App {
    @State private var security = SecurityStatus()
    @State private var session: SessionState
    @State private var onboarding: OnboardingFlow
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // UI tests pass "-uitest-reset" to start from a clean onboarding state.
        let s = SessionState()
        if CommandLine.arguments.contains("-uitest-reset") { s.resetOnboarding() }
        _session = State(initialValue: s)
        _onboarding = State(initialValue: OnboardingFlow(session: s))
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if session.onboardingCompleted {
                    RootTabView()
                } else {
                    OnboardingView(flow: onboarding)
                }
            }
            .environment(security)
            .environment(session)
            .preferredColorScheme(nil)
            .task { security.bootstrap() }
            .onChange(of: session.onboardingCompleted) { _, done in
                if !done { onboarding = OnboardingFlow(session: session) }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Key cache hygiene: drop unwrapped KEKs whenever the app leaves the foreground.
            // The session's in-memory birth date is kept for this process; it is gone on relaunch.
            if phase != .active { security.purgeKeyCache() }
        }
    }
}
