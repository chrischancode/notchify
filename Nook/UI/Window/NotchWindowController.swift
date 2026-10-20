//
//  NotchWindowController.swift
//  Nook
//
//  Controls the notch window positioning and lifecycle
//

import AppKit
import Combine
import SwiftUI

class NotchWindowController: NSWindowController {
    let viewModel: NotchViewModel
    private(set) var screen: NSScreen
    private var cancellables = Set<AnyCancellable>()
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var notificationObservers: [NSObjectProtocol] = []

    init(screen: NSScreen, animateOnLaunch: Bool = true) {
        self.screen = screen

        let screenFrame = screen.frame
        let notchSize = screen.notchSize

        // Window covers full width at top, tall enough for largest content (chat view)
        let windowHeight: CGFloat = 750
        let windowFrame = NSRect(
            x: screenFrame.origin.x,
            y: screenFrame.maxY - windowHeight,
            width: screenFrame.width,
            height: windowHeight
        )

        // Device notch rect - positioned at center
        let deviceNotchRect = CGRect(
            x: (screenFrame.width - notchSize.width) / 2,
            y: 0,
            width: notchSize.width,
            height: notchSize.height
        )

        // Create view model
        self.viewModel = NotchViewModel(
            deviceNotchRect: deviceNotchRect,
            screenRect: screenFrame,
            windowHeight: windowHeight,
            hasPhysicalNotch: screen.hasPhysicalNotch
        )

        // Create the window
        let notchWindow = NotchPanel(
            contentRect: windowFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        super.init(window: notchWindow)

        // Create the SwiftUI view with pass-through hosting
        let hostingController = NotchViewController(viewModel: viewModel)
        notchWindow.contentViewController = hostingController

        notchWindow.setFrame(windowFrame, display: true)

        // Dynamically toggle mouse event handling based on notch state:
        // - Closed: ignoresMouseEvents = true (clicks pass through to menu bar/apps)
        // - Opened: ignoresMouseEvents = false (buttons inside panel work)
        viewModel.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak notchWindow, weak viewModel] status in
                switch status {
                case .opened:
                    // Accept mouse events when opened so buttons work
                    notchWindow?.ignoresMouseEvents = false
                    // Don't steal focus when opened by notification (task finished)
                    if viewModel?.openReason != .notification {
                        NSApp.activate(ignoringOtherApps: false)
                        notchWindow?.makeKey()
                    }
                    
                    // Setup autohide monitors when opened
                    if self.globalMouseMonitor == nil {
                        self.globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                            self?.viewModel.notchClose()
                        }
                    }
                    if self.localMouseMonitor == nil {
                        self.localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                            if let notchWindow = self?.window,
                               let eventWindow = event.window,
                               eventWindow == notchWindow {
                                // Inside the notch window, don't close
                                return event
                            }
                            self?.viewModel.notchClose()
                            return event
                        }
                    }
                    
                case .closed, .popping:
                    // Ignore mouse events when closed so clicks pass through
                    notchWindow?.ignoresMouseEvents = true
                    notchWindow?.resignKey()
                    
                    self.removeMouseMonitors()
                }
            }
            .store(in: &cancellables)

        // Start with ignoring mouse events (closed state)
        notchWindow.ignoresMouseEvents = true

        // Let ShortcutManager know the current content type so chat-specific
        // hardcoded scroll keys (↑/↓/⌃F/⌃B) dispatch correctly.
        ShortcutManager.shared.contentTypeProvider = { [weak viewModel] in
            viewModel?.contentType ?? .instances
        }

        // Start local keyboard monitor (stays active regardless of notch state)
        ShortcutManager.shared.startLocalMonitor()

        // Register global hotkey (e.g. ⌥⌘L to open notch)
        ShortcutManager.shared.registerGlobalHotkey()

        // Update target screen for fullscreen detector
        FullScreenDetector.shared.setTargetScreen(screen)

        // Automatically hide notch window when an app or active space is in full screen
        FullScreenDetector.shared.$isFullScreen
            .receive(on: DispatchQueue.main)
            .sink { [weak notchWindow, weak viewModel] isFS in
                guard let window = notchWindow else { return }
                if isFS {
                    if viewModel?.status == .opened {
                        viewModel?.notchClose()
                    }
                    window.orderOut(nil)
                } else {
                    if !window.isVisible {
                        window.orderFront(nil)
                    }
                }
            }
            .store(in: &cancellables)

        // Listen for global hotkey toggle (Carbon) — route through handleShortcutAction
        // to ensure currentChatSession is cleared for instances page.
        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: .globalToggleNotch,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            // If hidden due to fullscreen, allow manual hotkey toggle
            if let window = self.window, !window.isVisible {
                window.orderFront(nil)
            }
            self.viewModel.handleShortcutAction(.toggleNotch)
        })

        // Listen for local shortcut actions (routed from ShortcutManager)
        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: .shortcutAction,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let action = notification.object as? ShortcutAction else { return }
            self.viewModel.handleShortcutAction(action)
        })

        // Perform boot animation after a brief delay (only on initial launch)
        if animateOnLaunch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.viewModel.performBootAnimation()
            }
        }
    }

    private func removeMouseMonitors() {
        if let global = globalMouseMonitor {
            NSEvent.removeMonitor(global)
            globalMouseMonitor = nil
        }
        if let local = localMouseMonitor {
            NSEvent.removeMonitor(local)
            localMouseMonitor = nil
        }
    }

    /// Detach everything that could keep a replaced controller reacting to
    /// app-wide events (hotkeys, full-screen changes, click-outside monitors).
    /// Without this, a controller replaced on a screen change can stay alive
    /// and order its old window back in — the "doubled notch" bug.
    func tearDown() {
        cancellables.removeAll()
        removeMouseMonitors()
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers.removeAll()
        window?.orderOut(nil)
        window?.close()
    }

    /// Realign window and view model geometry to a given screen (e.g. after sleep/wake or screen change)
    func realign(screen: NSScreen) {
        self.screen = screen

        let screenFrame = screen.frame
        let notchSize = screen.notchSize

        let windowHeight: CGFloat = 750
        let windowFrame = NSRect(
            x: screenFrame.origin.x,
            y: screenFrame.maxY - windowHeight,
            width: screenFrame.width,
            height: windowHeight
        )

        let deviceNotchRect = CGRect(
            x: (screenFrame.width - notchSize.width) / 2,
            y: 0,
            width: notchSize.width,
            height: notchSize.height
        )

        viewModel.updateGeometry(
            deviceNotchRect: deviceNotchRect,
            screenRect: screenFrame,
            windowHeight: windowHeight,
            hasPhysicalNotch: screen.hasPhysicalNotch
        )

        if let window = self.window {
            window.setFrame(windowFrame, display: true)
        }

        FullScreenDetector.shared.setTargetScreen(screen)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
