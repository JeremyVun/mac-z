# Release review — 20 September 2026

The local app builds and passes the checks below. Public distribution is not ready: release signing and notarization are unconfigured, and the supported hardware/OS matrix is not fully tested. The review began on a dirty working tree with no commits.

## Fixed

| Issue | Change | Evidence |
| --- | --- | --- |
| Background monitoring was eligible for App Nap timer throttling. | Hold a user-initiated activity while sampling, allowing idle system sleep; release it on pause and sleep. | Lifecycle test verifies acquisition and release. Long-duration App Nap behavior still needs a soak test. |
| Delayed callbacks stretched old readings into the Dock's last-minute graph. Relative sleeps also accumulated sampling time. | Use two-second clock deadlines; reset history and CPU baseline after delays over three seconds; skip catch-up bursts. | Simulated 18-second gap clears CPU, memory, and Dock history. |
| Missing CPU/memory readings disappeared from window history, connecting readings across failures. | Keep aligned optional readings and break graph paths at missing values. | Bounded-history and initial unavailable-reading tests; app rendering smoke test. |
| Copy report always confirmed success even if the clipboard rejected the write. | Confirm successful writes only; show an alert on failure. | Injected successful, failed, and recovered clipboard writes. |
| Switching categories inherited the previous category's scroll offset and could hide the new heading and current reading. | Reset the scroll view when the selected category changes. | Reproduced by scrolling CPU to the bottom and opening Memory; rebuilt app opens Memory at scroll position zero with the heading visible. |
| Packaging overwrote the existing app before signing/verification completed and retained stale files. | Assemble and verify a temporary bundle, then replace the existing bundle; restore it if the final rename fails. Reject surplus arguments. | Five isolated packaging tests cover signing failure, verification failure, failed rename, clean replacement, and argument validation. |

## Second pass

Three additional issues were reproduced with failing regression tests and fixed:

| Issue | Change | Evidence |
| --- | --- | --- |
| Hardware specifications used the cores available in the current power-management mode. A reduced-power configuration could be reported as a smaller processor. | Prefer `hw.physicalcpu_max`, `hw.logicalcpu_max`, and `hw.perflevelN.physicalcpumax`, with the original keys as fallbacks. | A simulated 12-core system with four available cores previously reported four. Tests now verify maximum counts and fallback behavior. Key semantics were checked against Apple's SDK `sys/sysctl.h`. |
| Copying a paused report described retained readings as current activity. | Use the section title `Paused activity` when sampling is paused. | The report test failed on the old title and passes after the change. No new data fields were added to reports. |
| Two build scripts could overlap after SwiftPM released its compilation lock, racing the app replacement and rollback steps. | Hold a nonblocking kernel file lock across the complete build and packaging operation. The lock file remains in `.build`; the kernel releases ownership on process exit. | Packaging tests reject a competing lock without touching the previous app, verify lock ownership during signing/verification, and verify release after a failed build. |

## Long-running pass — 24 September 2026

A copy left running for four days used 35–40% CPU and 491 MB. Found by profiling and heap diffs of the live process:

| Issue | Change | Evidence |
| --- | --- | --- |
| Every sample rebuilt the segmented page picker, and SwiftUI leaked its tag state each time (one `TagIndexProjection` plus two Observation registrars per sample). Layout slowed as the pile grew. | Move the picker into its own view that only depends on the selected page. | 165,262 leaked projections after four days; the fixed build stays at one. The old build gained 22 in 40 seconds while the fixed build gained none. |
| The window re-rendered every sample while minimized, hidden or covered. Each SwiftUI frame also schedules a RenderBox clean-up timer that stays pending in libdispatch. | Readings refresh the window only while it is visible; sampling and the Dock graph continue. | A hidden window drops from 12 idle wakeups per 5 seconds to none, and pending timers fall instead of growing. `testHiddenWindowSkipsRefreshesButKeepsSampling`. |
| The Dock view set its accessibility label inside `draw(_:)`. | Set it when new readings arrive. | Code change only. |

Remaining framework behaviour: a visible window still schedules RenderBox clean-up timers, and `leaks` reports a one-time 14 KB cycle in AppKit's XPC interfaces. Neither is reachable from MacZ code.

## Verification

- `swift test`: 14 tests passed, including live API checks, report privacy, and second-pass regressions.
- `python3 -m unittest discover -s Tests/PackagingTests -v`: 8 tests passed, covering packaging failures and lock ownership.
- `./tools/build-app.sh --universal`: release build passed for arm64 and x86_64; strict code-signature verification passed.
- Packaged `--report` passed on native Apple silicon and under Rosetta. Both report the hardware architecture correctly and omit Rosetta's synthetic CPU frequency. No reports were saved.
- The second-pass universal build passed signature verification; native and Rosetta reports matched the maximum core counts. A separate process verified that the completed real build released its lock.
- Isolated GUI launch outside the checkout used the release executable and bundled icon. The copy used a separate bundle identifier and an ad-hoc signature to avoid interfering with the running app.
- GUI smoke checks covered all five categories, scrolling, pause/resume, and quitting. The final tab-scroll fix was rebuilt for both architectures and verified in the isolated app.
- `git diff --check` and shell syntax validation passed.

## Before public release

1. Use a clean, reviewed commit on `main` for release. No deployment was attempted during this review.
2. Configure Developer ID signing, enable and test hardened runtime, notarize the distribution artifact, staple the ticket, and verify a quarantined download on a clean Mac. The current script signs ad hoc for local use only. See [Apple's distribution requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).
3. Test on macOS 14 and native Intel hardware, including integrated/discrete and unsupported GPU counters. A universal build and Rosetta execution do not verify Intel hardware APIs.
4. Run an extended minimized-monitoring and actual sleep/wake test, and check that footprint and CPU stay flat over at least an hour. Automated tests cover background sampling without a window and simulated lifecycle transitions; they do not reproduce overnight sleep, App Nap heuristics, or long-term energy usage.

The Dock artwork and its documentation changed concurrently during this review; those changes were preserved. This is a review of a working tree, not a frozen release commit.

Apple documents App Nap timer throttling and activity assertions in its [energy efficiency guide](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/AppNap.html). API references were checked on 20 September 2026.
