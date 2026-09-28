# LocoloWidgets

Live Activity / Dynamic Island UI for `ExploringAttributes`.

**App side (done):** `ExploringLiveActivity` + `NSSupportsLiveActivities=YES`.
Starts/updates/ends while the AR viewer is open.

**Widget UI source (ready):** `ExploringLiveActivityWidget.swift` — gated behind
`LOCOLO_WIDGETS_TARGET` so it does not compile into the main app.

**Setup (Xcode — owner):**
1. File → New → Target → Widget Extension → name `LocoloWidgets`.
2. Add `ExploringLiveActivityWidget.swift` to that target.
3. Share `ExploringAttributes` (from `Locolo/ARModule/Services/ExploringLiveActivity.swift`) with both targets, or extract to a small shared framework.
4. Build Settings → Swift Active Compilation Conditions → add `LOCOLO_WIDGETS_TARGET` for the widget target.
5. Delete the Xcode template `@main` widget if it conflicts.
