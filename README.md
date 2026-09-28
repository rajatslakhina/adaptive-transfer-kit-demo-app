# AdaptiveTransfer Demo

**A side-by-side race between two upload clients against the same failing server: one with the concurrency limit someone picked, one that works the limit out from the latency it sees.**

The whole point is what happens at 200 ms, when the server's usable capacity quietly drops from 8 to 2 and neither client is told. Drag the slider to make the collapse harder or softer; both strategies re-run against identical conditions on every change.

This is the demo app for **[`adaptive-transfer-kit`](https://github.com/rajatslakhina/adaptive-transfer-kit)**, which it consumes as a **version-pinned remote Swift package** — not a local path, not a branch. The two repositories are deliberately separate, so the library can be read as a library.

---

## Why this matters

Open any iOS codebase with an upload path in it and you will find a constant:

```swift
uploadQueue.maxConcurrentOperationCount = 8
```

Nobody remembers choosing 8. It is a guess about capacity belonging to a server the client does not own, and it is shipped to the entire fleet.

The reason it survives is that being wrong is invisible. Set it too low and throughput suffers, somebody notices, the number goes up. Set it too high and throughput does *not* fall — the extra work queues somewhere you cannot instrument, so the dashboard stays green while the user watches a spinner. Push it further and the server starts shedding, every rejection becomes a retry, and the client turns into a retry storm that still reports zero errors.

The app shows that asymmetry as numbers that move when you drag a slider — and it shows both sides of it. Drag right, to a mild degradation, and the fixed limit of 8 is close enough to the truth to beat the controller, which is paying for probing that turns out not to have been needed. Drag left and the same constant starts shedding requests it will have to retry.

That is the argument, and it is not "adaptive is always faster". It is that the two ends of this slider are the same client on the same code path, and nothing in it can tell which end it is at.

---

## What the app shows

| section | what it is |
|---|---|
| **Two strategy cards** | p50 / p95 / p99, chunks completed, requests shed, and the limit each strategy ended on — for the fixed limiter and the gradient limiter, on byte-identical conditions |
| **Latency bars** | each strategy's p95 as a fraction of the worse of the two — and full width for a strategy that did not finish, because a client that sheds its way to 44 of 300 chunks has a *small* p95 among the survivors, and the loudest visual has to agree with the verdict |
| **The verdict line** | the p95 ratio, and the throughput the adaptive controller gives up to get it |
| **Degraded-capacity slider** | how hard the server collapses at 200 ms; both strategies re-run on every change |
| **Invariant panel** | the library's own `LimiterInvariantCheck` run live — limit before congestion → during → recovered → after a drop |

There is no empty state and no "Run" button to find. `TransferDashboardModel` computes the comparison in `init`, so the first frame already has real numbers in it.

---

## How the two repos fit together

```
adaptive-transfer-kit          (library, tagged v1.1.0)
  ├── AdaptiveTransfer         core policy + coordinator + simulation, no I/O
  └── AdaptiveTransferUI       TransferDashboardView
              ▲
              │  XCRemoteSwiftPackageReference
              │  upToNextMajorVersion, minimumVersion 1.1.0
              │
adaptive-transfer-kit-demo-app (this repo)
  └── Demo/DemoApp.swift       owns the TransferProfile; hands it to the view
```

The app imports **both** products, and for a reason worth stating: chunk count, the concurrency ceiling and what counts as a plausible server are *product* decisions — how much of a metered connection this app is willing to spend, how long a preemption may take. A library that hard-coded them would be making those calls for every app that adopts it. So `DemoApp.swift` builds the `TransferProfile` from types the core module vends and passes it in.

### Why the dependency is pinned to a tag, not `main`

`requirement = { kind = upToNextMajorVersion; minimumVersion = 1.1.0; }`.

Branch-tracking would mean every clone and every CI run resolves whatever `main` happened to be that morning — not reproducible, and a reviewer cloning this in six months would get a different library than the one this README describes.

To be exact about how far that goes: `upToNextMajorVersion` pins the **1.x line**, not a single commit. A future `1.2.0` would be picked up by a fresh clone. The artifact that pins exactly is `Package.resolved`, and it is not committed here, because it is generated when Xcode first opens the project and this project has not been opened in Xcode (see Verification). Committing one is the right next step, and saying so is better than implying a guarantee the repository does not currently provide.

### What the app decides, and what the library decides

`TransferProfile` — chunk count, the concurrency ceiling this app would
otherwise have hard-coded, the modelled server, and *when* it degrades — lives
in the library's core module, but the app constructs it. That split is the
point: the policy is the library's, the numbers are the product's.

The alternative, and why it was rejected: `TransferProfile` originally lived in
`AdaptiveTransferUI`, next to the view that reads it. That reads tidier and is
wrong, because everything in that module is inside `#if canImport(SwiftUI)` — so
on Linux it compiles to nothing, and the package's test target could not reach
it. A type holding a decision that no test can see is how the first cut of this
demo shipped a slider that recomputed faithfully and produced identical numbers
at every position: the modelled server degraded at 2,000 ms, after the modelled
transfer had already finished at ~1,520 ms. The control was live and the
scenario was inert.

Moving it into the core module is what made `TransferProfileTests` possible, and
those tests now assert the two things that would have caught it: that every
reachable slider position changes the outcome, and that the degradation lands
before either strategy could have finished.

---

## How to run it

```bash
git clone https://github.com/rajatslakhina/adaptive-transfer-kit-demo-app.git
cd adaptive-transfer-kit-demo-app
open Demo.xcodeproj
```

Then pick the **Demo** scheme (it is committed as a shared scheme, so it is there on a fresh clone), choose any iOS Simulator, and Build & Run. Xcode resolves `adaptive-transfer-kit` at v1.1.0 from GitHub on first open — an internet connection is needed once.

Requires Xcode 16 or later and iOS 17+. The project uses `objectVersion = 60` / `compatibilityVersion = "Xcode 15.0"`, so Xcode 16 and 26 open it without offering to upgrade the format.

---

## Verification — what actually happened

Kept deliberately blunt, because "it builds" and "it ran" are different facts and a README that blurs them is not worth reading.

**What was verified:**

- The library's own suite: `swift build -Xswiftc -warnings-as-errors` on a cold tree — clean, zero warnings — and `swift test` — **118 tests, 0 failures**, Swift 6.0.3 on Linux.
- `Demo.xcodeproj/project.pbxproj` was checked mechanically before it was committed: brace and paren balance with comments and quoted strings stripped, and every one of the 23 object IDs referenced in the file is also defined in it, with no dangling references. The shared scheme's `BlueprintIdentifier` was cross-checked against the `PBXNativeTarget` section specifically — the first attempt pointed at the `PBXGroup` that shares the target's name, which would have produced a scheme that does not build.
- CI ([Actions](https://github.com/rajatslakhina/adaptive-transfer-kit-demo-app/actions)) runs `xcodebuild -resolvePackageDependencies` and then `xcodebuild build -scheme Demo -destination 'generic/platform=iOS Simulator'` on `macos-15`, and prints the resolved `Package.resolved`. That proves the remote package genuinely resolves from GitHub at the pinned version and that the app compiles against it.

**What was NOT verified — the app was never launched on a Simulator, and there are no screenshots in this repository.**

It compiles for an iOS Simulator destination in CI on every push. It has never been observed running. Those are two different claims and only the first one is being made here; a "Build Succeeded" is not a launched app, and no screenshot in this repo purports otherwise because there are none.

---

## Licence

MIT. The library is [MIT too](https://github.com/rajatslakhina/adaptive-transfer-kit).
