//
//  Ext+NSScreen.swift
//  Nook
//
//  Extensions for NSScreen to detect notch and built-in display
//

import AppKit

extension NSScreen {
    private static let hasBuiltinPhysicalNotchKey = "Nook_HasBuiltinPhysicalNotch"
    private static let builtinNotchWidthKey = "Nook_BuiltinNotchWidth"
    private static let builtinNotchHeightKey = "Nook_BuiltinNotchHeight"

    private static var inMemoryBuiltinHasNotch: Bool?
    private static var inMemoryBuiltinNotchSize: CGSize?

    /// Returns the size of the notch on this screen (pixel-perfect using macOS APIs)
    var notchSize: CGSize {
        if safeAreaInsets.top > 0 {
            let notchHeight = safeAreaInsets.top
            let fullWidth = frame.width
            let leftPadding = auxiliaryTopLeftArea?.width ?? 0
            let rightPadding = auxiliaryTopRightArea?.width ?? 0

            let notchWidth: CGFloat
            if leftPadding > 0, rightPadding > 0 {
                // +4 to match boring.notch's calculation for proper alignment
                notchWidth = fullWidth - leftPadding - rightPadding + 4
            } else {
                // Fallback if auxiliary areas unavailable
                notchWidth = 180
            }

            let size = CGSize(width: notchWidth, height: notchHeight)
            if isBuiltinDisplay {
                Self.inMemoryBuiltinHasNotch = true
                Self.inMemoryBuiltinNotchSize = size
                UserDefaults.standard.set(true, forKey: Self.hasBuiltinPhysicalNotchKey)
                UserDefaults.standard.set(Double(notchWidth), forKey: Self.builtinNotchWidthKey)
                UserDefaults.standard.set(Double(notchHeight), forKey: Self.builtinNotchHeightKey)
            }
            return size
        }

        // safeAreaInsets.top is 0. If this is the built-in display, check cached physical notch info
        // (during sleep/wake cycles, macOS displays can transiently report safeAreaInsets.top == 0)
        if isBuiltinDisplay && hasPhysicalNotch {
            if let cachedSize = Self.inMemoryBuiltinNotchSize {
                return cachedSize
            }
            let w = UserDefaults.standard.double(forKey: Self.builtinNotchWidthKey)
            let h = UserDefaults.standard.double(forKey: Self.builtinNotchHeightKey)
            if w > 0 && h > 0 {
                let size = CGSize(width: CGFloat(w), height: CGFloat(h))
                Self.inMemoryBuiltinNotchSize = size
                return size
            }
        }

        // On non-notched displays, match this screen's actual menu bar height
        return CGSize(width: 224, height: menuBarHeight)
    }

    /// Whether this is the built-in display
    var isBuiltinDisplay: Bool {
        guard let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return false
        }
        return CGDisplayIsBuiltin(screenNumber) != 0
    }

    /// The built-in display (with notch on newer MacBooks)
    static var builtin: NSScreen? {
        if let builtin = screens.first(where: { $0.isBuiltinDisplay }) {
            return builtin
        }
        return NSScreen.main
    }

    /// Whether this screen has a physical notch (camera housing)
    var hasPhysicalNotch: Bool {
        if safeAreaInsets.top > 0 || auxiliaryTopLeftArea != nil {
            if isBuiltinDisplay {
                Self.inMemoryBuiltinHasNotch = true
                UserDefaults.standard.set(true, forKey: Self.hasBuiltinPhysicalNotchKey)
            }
            return true
        }

        // Built-in MacBook display never physically loses its camera notch across sleep/wake
        if isBuiltinDisplay {
            if let cached = Self.inMemoryBuiltinHasNotch {
                return cached
            }
            if UserDefaults.standard.bool(forKey: Self.hasBuiltinPhysicalNotchKey) {
                Self.inMemoryBuiltinHasNotch = true
                return true
            }
        }

        return false
    }

    /// The menu bar height on this specific screen
    var menuBarHeight: CGFloat {
        let topInset = frame.maxY - visibleFrame.maxY
        return max(topInset, 24)
    }
}
