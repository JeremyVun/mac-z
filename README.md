# MacZ

A small native macOS hardware viewer inspired by CPU-Z. Built with SwiftUI, with no third-party dependencies, accounts, network requests, or privileged helpers.

- CPU model, architecture, core counts, and cache sizes
- Live CPU and memory usage, with 60-sample graphs
- Live CPU and GPU Dock graphs showing the last minute, even while minimised
- Installed memory, wired memory, compression, and swap
- Metal GPU information and connected display resolutions
- macOS version, uptime, and thermal state
- Copy a text report without device identifiers

Requires macOS 14 or later. Supports Apple silicon and Intel; available specifications depend on the hardware. Sampling runs every two seconds, including in the background. Pause freezes the window and Dock readings; resuming starts fresh history. Closing the window quits the app.

## Build and run

Install Xcode or the Command Line Tools with Swift 6 or later, then:

```sh
./tools/build-app.sh
open dist/MacZ.app
```

For a universal app containing both Apple silicon and Intel binaries:

```sh
./tools/build-app.sh --universal
```

The script applies an ad-hoc signature for local use. Public binary distribution still needs Developer ID signing and notarization. This repository contains no signing credentials.

During development:

```sh
swift run MacZ
swift test
python3 -m unittest discover -s Tests/PackagingTests
swift run MacZ --report
```

## Readings and privacy

MacZ reads hardware and activity through `sysctl`, Mach, Metal, IOKit, and AppKit. It does not launch `system_profiler`, collect serial numbers, access the network, write telemetry, or save reports automatically. The copy action places an allowlisted report on the clipboard. Graph history stays in memory for the current session. Hardware specifications are loaded at launch.

CPU usage is the change in kernel ticks across each sample, normalized across all logical processors. Memory used is an estimate from VM page counters; it may differ from Activity Monitor. Metal's recommended working set is a memory budget, not dedicated VRAM. Cache sizes follow macOS's per-core or shared-group reporting.

GPU usage comes from driver performance counters when available; unsupported readings leave gaps in the Dock graph and show as unavailable in the window. On Macs with multiple reporting GPUs, the Dock shows the busiest GPU. The Dock overlays translucent blue CPU and red GPU graphs across the whole icon, each scaled from 0–100%, with no labels or percentages. Sleep and resume reset history so old readings aren't presented as the last minute.

This version does not report live clock speeds, temperatures, fan speeds, GPU core counts, or RAM timings. It has no benchmarks.

Missing readings leave gaps in all graphs. Sampling delays over three seconds reset history and the CPU baseline. Live monitoring prevents App Nap while allowing the Mac to sleep; pausing releases that activity.

## Licence

[MIT](LICENSE). MacZ is an independent project and is not affiliated with CPU-Z or CPUID.
