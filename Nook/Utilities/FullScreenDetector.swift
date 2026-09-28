//
//  FullScreenDetector.swift
//  Nook
//
//  Detects when a frontmost application or active space is in full screen mode,
//  enabling Notchify to automatically hide and avoid obstructing full screen apps.
//

import AppKit
import CoreGraphics
import Combine

@MainActor
final class FullScreenDetector: ObservableObject {
    static let shared = FullScreenDetector()

    @Published private(set) var isFullScreen: Bool = false

    private var cancellables = Set<AnyCancellable>()
    private var periodicTimer: Timer?
    private weak var targetScreen: NSScreen?

    private init() {
        setupObservers()
    }

    func setTargetScreen(_ screen: NSScreen) {
        self.targetScreen = screen
        checkFullScreenStatus()
    }

    private func setupObservers() {
        // Space changes (switching to/from native full-screen space)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.checkFullScreenStatus()
            }
            .store(in: &cancellables)

        // Frontmost app changes
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.checkFullScreenStatus()
            }
            .store(in: &cancellables)

        // Screen configuration changes
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.checkFullScreenStatus()
            }
            .store(in: &cancellables)

        // Fallback polling at 1.0s to detect custom/borderless video full-screen transitions
        periodicTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkFullScreenStatus()
            }
        }
    }

    func checkFullScreenStatus() {
        guard AppSettings.hideInFullScreen else {
            if isFullScreen {
                isFullScreen = false
            }
            return
        }

        let isFS = detectFullScreen()
        if isFullScreen != isFS {
            isFullScreen = isFS
        }
    }

    private func detectFullScreen() -> Bool {
        guard let screen = targetScreen ?? NSScreen.main else { return false }

        // If frontmost app is Notchify itself or Finder desktop, it's not a full-screen app
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontApp.bundleIdentifier,
              bundleId != Bundle.main.bundleIdentifier,
              bundleId != "com.apple.finder" else {
            return false
        }

        // Query on-screen windows from Quartz Window Services
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        let screenFrame = screen.frame
        let tolerance: CGFloat = 6.0

        for window in windowList {
            guard let layer = window[kCGWindowLayer as String] as? Int,
                  layer == 0, // Normal application window layer
                  let pid = window[kCGWindowOwnerPID as String] as? pid_t,
                  pid == frontApp.processIdentifier,
                  let boundsDict = window[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                continue
            }

            // Window must have non-trivial size
            guard bounds.width > 200 && bounds.height > 200 else { continue }

            // Check if window bounds cover the screen dimensions
            let widthDiff = abs(bounds.width - screenFrame.width)
            let heightDiff = abs(bounds.height - screenFrame.height)

            if widthDiff <= tolerance && heightDiff <= tolerance {
                return true
            }

            // Also check if window spans full height (covering menu bar area)
            if bounds.height >= screenFrame.height - tolerance && widthDiff <= tolerance {
                return true
            }
        }

        return false
    }

    deinit {
        periodicTimer?.invalidate()
    }
}
