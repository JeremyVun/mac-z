# MacZ

MacZ is a lightweight, native hardware inspector for macOS, inspired by CPU-Z. It prioritizes specifications, low overhead, and a compact window over a persistent monitoring dashboard.

The app uses SwiftUI and Apple system frameworks without third-party dependencies. macOS 14 is the minimum supported version. Apple silicon and Intel have different available hardware fields; unsupported fields are omitted or marked unavailable. It never guesses a specification from a chip-name lookup table.

Reported CPU frequency is shown only on Intel hardware. Rosetta supplies a synthetic x86 frequency on Apple silicon, so that field is suppressed even when its sysctl key exists.

CPU specifications use the maximum physical, logical, and per-group core counts reported for this boot. Power-management-dependent available counts are fallbacks only when the maximum keys are unavailable.

Hardware is queried at launch. An app-owned cancellable task samples CPU, GPU and memory on two-second deadlines, including while inactive or minimised. A user-initiated activity prevents App Nap during monitoring without preventing idle system sleep. Pause and system sleep cancel sampling and end that activity; resuming resets the CPU baseline and history. Sampling delays over three seconds also reset history, with no burst of catch-up samples. Window CPU and memory graphs retain 60 aligned time slots; the Dock retains 30 (one minute). Missing readings leave gaps in all graphs. Closing the window quits the app.

GPU usage reads only the `PerformanceStatistics` property of IOKit `IOAccelerator` services, using `Device Utilization %` or `GPU Activity(%)`. These driver counters are not guaranteed on every hardware/OS combination. Missing or invalid values remain unavailable, and values above 100 are clamped. Multiple GPUs use the highest reported utilisation, not a sum or an inferred total. No privileged helper or shell command is used. GPU metrics are displayed in the Dock and Graphics tab; the existing report allowlist is unchanged.

Reports contain an explicit allowlist of technical specifications. The app never requests computer names, usernames, serial numbers, UUIDs, or network identifiers. It makes no network requests and has no privileged helper. Tests inspect the local username and hostname solely to assert their absence from reports; no test output or device reports belong in git.

Memory used is `active + inactive + wired + compressed - purgeable - external`, clamped to physical memory. It is explicitly an estimate. CPU uses unsigned wrapping deltas of user, nice, system, and idle counters. The initial sample has no CPU percentage. Thermal state is the operating system's state, not a temperature measurement.

Local builds are ad-hoc signed. A public release requires a separately configured Developer ID and notarization process. No deployment, signing account, analytics service, or update service is configured.

The build script holds a kernel file lock across compilation and packaging; overlapping invocations fail without changing the output. It assembles and verifies a temporary bundle before replacing `dist/MacZ.app`. Signing or verification failure preserves the existing app; a failed final rename restores it. Clipboard confirmation appears only after a successful write; failures show an alert. Reports copied while paused label their retained readings as paused activity.

API references: [Metal memory architecture](https://developer.apple.com/documentation/metal/mtldevice/hasunifiedmemory), [host_statistics64](https://developer.apple.com/documentation/kernel/1502863-host_statistics64).
