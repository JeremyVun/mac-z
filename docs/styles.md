# UI conventions

Use a single native macOS window with standard traffic lights and segmented tabs: Overview, CPU, Memory, Graphics, System. Keep the default window at 720 × 640 points with a 620 × 570 minimum and scrollable tab content.

Use system typography, semantic foreground and background colors, the system accent, and SF Symbols. Follow the macOS light/dark appearance. Information tables use secondary labels and selectable values. Keep rows readable when values wrap; no fixed-height clipping.

The app icon is a white chip with a Z on a blue rounded square. `Sources/MacZ/Resources/AppIcon.icns` includes native sizes from 16 to 1024 pixels and is used in Finder and the app header. Regenerate it with `swift tools/make-icon.swift Sources/MacZ/Resources/AppIcon.icns`. SwiftPM embeds the same resource for development launches.

While running, the Dock icon overlays CPU history in translucent blue and GPU history in translucent red across the full dark rounded square. Both share the full 0–100% height and 30 two-second slots, with the latest at the right. Additive fills blend the overlap, and each graph keeps a bright top edge. There are no visible labels or percentages; current values remain accessible to VoiceOver and in the window. Missing readings leave gaps. Pause dims the graphs and adds a Paused badge. Sampling continues when minimised or inactive. Jeremy requested this revision on 20 September 2026 because the stacked graphs were too small to read.

Overview contains three hardware summaries, two activity graphs, and uptime and thermal state. The header identifies the chip, Mac model, and macOS version. Detailed tabs expand those same facts. Activity graphs always use a 0–100% scale and retain at most 60 samples. Pause and copy-report controls remain in the footer.

Unavailable readings use an em dash or an explicit unavailable label. Memory usage is labelled as an estimate. Use plain technical names and describe limitations beside the affected readings.
