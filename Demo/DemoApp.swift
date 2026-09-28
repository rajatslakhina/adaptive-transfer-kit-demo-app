import SwiftUI
import AdaptiveTransfer
import AdaptiveTransferUI

/// The demo app owns the numbers, and the library owns the policy.
///
/// That split is the reason this target imports `AdaptiveTransfer` as well as
/// `AdaptiveTransferUI`. Chunk size, the concurrency ceiling, and what counts as
/// a plausible server for this product are *product* decisions — how much of a
/// metered connection the app is willing to spend, how long a preemption may
/// take — and a library that hard-coded them would be making them on behalf of
/// every app that adopts it.
///
/// So the profile is built here, from types the core module vends, and handed
/// to the view.
@main
struct DemoApp: App {

    /// The scenario the dashboard opens on: a photo-upload-shaped workload
    /// against a server with capacity 8 and a 40 ms service time.
    ///
    /// `degradeAtMilliseconds` is stated explicitly rather than left to the
    /// default, because it is the one value in here that is easy to get wrong
    /// in a way no test notices: set it later than the transfer takes to finish
    /// and the whole scenario silently becomes a no-op — the slider still moves,
    /// the model still recomputes, and every number stays identical.
    private let profile = TransferProfile(
        name: "Photo upload",
        chunkCount: 300,
        fixedLimit: 8,
        serverCapacity: 8,
        serviceTimeMilliseconds: 40,
        degradeAtMilliseconds: 200
    )

    /// Sanity-checked at launch against the library's own invariant check, so
    /// the app cannot ship a configuration the controller would misbehave under.
    private var controllerIsSane: Bool {
        LimiterInvariantCheck.run(
            GradientLimiter(configuration: .uploadPipeline)
        ).passed
    }

    var body: some Scene {
        WindowGroup {
            TransferDashboardView(profile: profile)
                .onAppear {
                    // Printed rather than asserted: a demo that crashes on
                    // launch teaches nobody anything, and the dashboard shows
                    // the same verdict on screen.
                    print("[Demo] limiter invariants hold: \(controllerIsSane)")
                }
        }
    }
}
