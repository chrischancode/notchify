//
//  ScreenObserver.swift
//  Nook
//
//  Monitors screen configuration changes
//

import AppKit

class ScreenObserver {
    private var observers: [Any] = []
    private let onScreenChange: () -> Void
    private let onWillSleep: (() -> Void)?
    private let onDidWake: (() -> Void)?
    private var pendingWork: DispatchWorkItem?

    /// Debounce interval to coalesce rapid screen change notifications
    /// (e.g., when waking from sleep, displays reconnect in stages)
    private let debounceInterval: TimeInterval = 0.4

    init(
        onScreenChange: @escaping () -> Void,
        onWillSleep: (() -> Void)? = nil,
        onDidWake: (() -> Void)? = nil
    ) {
        self.onScreenChange = onScreenChange
        self.onWillSleep = onWillSleep
        self.onDidWake = onDidWake
        startObserving()
    }

    deinit {
        stopObserving()
    }

    private func startObserving() {
        // Screen parameter changes (resolution, display connect/disconnect)
        let screenParamsObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleScreenChange()
        }
        observers.append(screenParamsObserver)

        // System will sleep
        let willSleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleWillSleep()
        }
        observers.append(willSleepObserver)

        // Displays did sleep
        let screensDidSleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleWillSleep()
        }
        observers.append(screensDidSleepObserver)

        // System did wake
        let didWakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleWake()
        }
        observers.append(didWakeObserver)

        // Displays did wake
        let screensDidWakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleWake()
        }
        observers.append(screensDidWakeObserver)
    }

    private func handleWillSleep() {
        pendingWork?.cancel()
        pendingWork = nil
        onWillSleep?()
    }

    private func scheduleWake() {
        pendingWork?.cancel()

        let work = DispatchWorkItem { [weak self] in
            self?.onDidWake?()
        }
        pendingWork = work

        DispatchQueue.main.asyncAfter(
            deadline: .now() + debounceInterval,
            execute: work
        )
    }

    private func scheduleScreenChange() {
        pendingWork?.cancel()

        let work = DispatchWorkItem { [weak self] in
            self?.onScreenChange()
        }
        pendingWork = work

        DispatchQueue.main.asyncAfter(
            deadline: .now() + debounceInterval,
            execute: work
        )
    }

    private func stopObserving() {
        pendingWork?.cancel()
        pendingWork = nil
        for obs in observers {
            NotificationCenter.default.removeObserver(obs)
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
        observers.removeAll()
    }
}
