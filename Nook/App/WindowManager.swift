//
//  WindowManager.swift
//  Nook
//
//  Manages the notch window lifecycle
//

import AppKit
import os.log

/// Logger for window management
private let logger = Logger(subsystem: "com.celestial.Nook", category: "Window")

class WindowManager {
    private(set) var windowController: NotchWindowController?
    private var isInitialLaunch = true
    private var currentScreenFrame: NSRect?

    /// Set up or recreate the notch window
    @MainActor
    func setupNotchWindow() -> NotchWindowController? {
        // Use ScreenSelector for screen selection
        let screenSelector = ScreenSelector.shared
        screenSelector.refreshScreens()

        guard let screen = screenSelector.selectedScreen else {
            logger.warning("No screen found")
            return nil
        }

        let screenFrame = screen.frame
        let windowHeight: CGFloat = 750
        let expectedWindowFrame = NSRect(
            x: screenFrame.origin.x,
            y: screenFrame.maxY - windowHeight,
            width: screenFrame.width,
            height: windowHeight
        )

        // If controller already exists, realign it and skip full recreation if screen hasn't changed
        if let existingController = windowController {
            existingController.realign(screen: screen)

            if let window = existingController.window, window.frame != expectedWindowFrame {
                logger.info("Re-anchoring window frame from \(NSStringFromRect(window.frame)) to \(NSStringFromRect(expectedWindowFrame))")
                window.setFrame(expectedWindowFrame, display: true)
            }

            if let existingFrame = currentScreenFrame, existingFrame == screen.frame {
                logger.debug("Screen frame unchanged, realigned existing window")
                return existingController
            }
        }

        // Only animate on initial app launch, not on screen changes
        let shouldAnimate = isInitialLaunch
        isInitialLaunch = false

        if let existingController = windowController {
            existingController.window?.orderOut(nil)
            existingController.window?.close()
            windowController = nil
        }

        currentScreenFrame = screen.frame
        windowController = NotchWindowController(screen: screen, animateOnLaunch: shouldAnimate)
        windowController?.showWindow(nil)

        return windowController
    }

    /// Handle system sleep: close open notch and order out window
    @MainActor
    func handleWillSleep() {
        logger.debug("System will sleep - closing notch and ordering out window")
        if let controller = windowController {
            if controller.viewModel.status == .opened {
                controller.viewModel.notchClose()
            }
            controller.window?.orderOut(nil)
        }
    }

    /// Handle system wake: refresh screens, realign notch window, and restore visibility
    @MainActor
    func handleDidWake() {
        logger.debug("System did wake - refreshing screens and realigning notch window")
        _ = setupNotchWindow()
        if let controller = windowController,
           let window = controller.window,
           !FullScreenDetector.shared.isFullScreen {
            window.orderFront(nil)
        }
    }
}
