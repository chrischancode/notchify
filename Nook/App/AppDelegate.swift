import AppKit
import SwiftUI
import os.log

class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowManager: WindowManager?
    private var screenObserver: ScreenObserver?

    static var shared: AppDelegate?

    var windowController: NotchWindowController? {
        windowManager?.windowController
    }

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !ensureSingleInstance() {
            NSApplication.shared.terminate(nil)
            return
        }

        // (scroller style override removed 2026-07-02: all three
        // attempts to set overlay globally crashed at launch:
        //   1) +[NSScroller setPreferredScrollerStyle:] — selector
        //      does not exist in AppKit
        //   2) NSScrollView.appearance().scrollerStyle — Swift
        //      resolves `appearance` to NSAppearanceCustomization
        //      instance property, not the +appearance class method
        //   3) NSClassFromString("NSScrollView") +
        //      perform("appearance") — also unrecognized (no
        //      class-level +appearance method exists in AppKit
        //      public API)
        // See docs/specs/2026-07-01-picker-panel-height-redesign.md
        // "决策 0" for the full investigation log. The picker-panel-height
        // redesign made the buffer obsolete — panel maxHeight equals
        // ScrollView contentSize at every frame (compile-time row heights),
        // so no slack is needed.)

        AppSettings.registerDefaults()

        // Start the on-disk debug log mirror as early as possible so
        // that startup-time diagnostics (hook installer, socket bind)
        // are captured. The file is recreated on every launch.
        if AppSettings.debugLogEnabled {
            DebugLog.shared.enable()
            DebugLog.shared.log(
                Logger(subsystem: "com.celestial.Nook", category: "App"),
                level: .default,
                "app launched, debug log enabled → \(DebugLog.fileURL.path)"
            )
        }

        // Analytics removed. Clear the anonymous ID earlier builds stored.
        UserDefaults.standard.removeObject(forKey: "mixpanel_distinct_id")

        // AI features removed

        NSApplication.shared.setActivationPolicy(.accessory)

        windowManager = WindowManager()
        _ = windowManager?.setupNotchWindow()

        screenObserver = ScreenObserver(
            onScreenChange: { [weak self] in
                self?.handleScreenChange()
            },
            onWillSleep: { [weak self] in
                self?.windowManager?.handleWillSleep()
            },
            onDidWake: { [weak self] in
                self?.windowManager?.handleDidWake()
            }
        )

    }

    @MainActor
    private func handleScreenChange() {
        _ = windowManager?.setupNotchWindow()
    }

    func applicationWillTerminate(_ notification: Notification) {
        screenObserver = nil
    }

    private func ensureSingleInstance() -> Bool {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.celestial.Nook"
        let runningApps = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == bundleID
        }

        if runningApps.count > 1 {
            if let existingApp = runningApps.first(where: { $0.processIdentifier != getpid() }) {
                existingApp.activate()
            }
            return false
        }

        return true
    }
}
