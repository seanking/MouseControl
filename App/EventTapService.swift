import Carbon.HIToolbox
import CoreGraphics
import Foundation
import MouseControlKit
import os
import Synchronization

/// CGEventTap for back/forward translation and the scroll-inversion fallback.
///
/// The tap is installed only when at least one feature needs it, and its event mask only includes
/// scroll events while the fallback is active, so idle cost is zero. It runs on its own thread so
/// main-thread work never delays mouse input.
final class EventTapService: @unchecked Sendable {
    struct Configuration: Equatable, Sendable {
        var backForward = false
        var invertScroll = false

        var needsTap: Bool { backForward || invertScroll }
    }

    private static let logger = Logger(subsystem: Log.subsystem, category: "eventtap")

    // Read on the tap thread for every event; written from the main actor.
    private let config = Mutex(Configuration())
    private let tapPort = Mutex<TapPort?>(nil)

    /// CFMachPort is thread-safe for the calls made here (enable/invalidate).
    private struct TapPort: @unchecked Sendable {
        let port: CFMachPort
    }

    // Main actor only.
    private var installedConfig: Configuration?
    private var source: CFRunLoopSource?
    private var tapRunLoop: CFRunLoop?

    /// Applies `configuration`, (re)building the tap if needed. Returns false when the tap
    /// couldn't be created (Accessibility not granted).
    @MainActor @discardableResult
    func update(_ configuration: Configuration) -> Bool {
        config.withLock { $0 = configuration }
        guard configuration.needsTap else {
            uninstall()
            return true
        }
        // The event mask depends on invertScroll; back/forward alone only needs mouse buttons.
        if let installed = installedConfig, installed.invertScroll == configuration.invertScroll {
            return true
        }
        uninstall()
        return install(scroll: configuration.invertScroll)
    }

    @MainActor
    private func install(scroll: Bool) -> Bool {
        var mask = CGEventMask(1 << CGEventType.otherMouseDown.rawValue) | CGEventMask(1 << CGEventType.otherMouseUp.rawValue)
        if scroll { mask |= CGEventMask(1 << CGEventType.scrollWheel.rawValue) }

        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, info in
                Unmanaged<EventTapService>.fromOpaque(info!).takeUnretainedValue().handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Self.logger.error("CGEvent.tapCreate failed (Accessibility not granted?)")
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(tapThreadRunLoop(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tapPort.withLock { $0 = TapPort(port: port) }
        self.source = source
        installedConfig = config.withLock { $0 }
        Self.logger.info("Event tap installed (scroll: \(scroll))")
        return true
    }

    @MainActor
    private func uninstall() {
        if let port = tapPort.withLock({ $0.take() })?.port {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        if let source, let tapRunLoop {
            CFRunLoopRemoveSource(tapRunLoop, source, .commonModes)
        }
        source = nil
        installedConfig = nil
    }

    @MainActor
    private func tapThreadRunLoop() -> CFRunLoop {
        if let tapRunLoop { return tapRunLoop }
        let ready = DispatchSemaphore(value: 0)
        let box = Mutex<CFRunLoop?>(nil)
        let thread = Thread {
            box.withLock { $0 = CFRunLoopGetCurrent() }
            // A port keeps the run loop alive (and blocked) when no tap source is attached.
            RunLoop.current.add(NSMachPort(), forMode: .default)
            ready.signal()
            RunLoop.current.run()
        }
        thread.name = "MouseControl.eventtap"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        let runLoop = box.withLock { $0 }!
        tapRunLoop = runLoop
        return runLoop
    }

    // MARK: - Tap thread

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .otherMouseDown, .otherMouseUp:
            // Buttons 3/4 (0-indexed) are back/forward. Filter on the button number before anything else.
            let button = event.getIntegerValueField(.mouseEventButtonNumber)
            guard button == 3 || button == 4, config.withLock({ $0.backForward }) else { break }
            if type == .otherMouseDown {
                let key = button == 3 ? kVK_ANSI_LeftBracket : kVK_ANSI_RightBracket
                SystemActions.postKeystroke(keyCode: CGKeyCode(key), flags: .maskCommand)
            }
            return nil

        case .scrollWheel:
            // Trackpads and Magic Mouse send continuous (pixel) scrolls; a notched/free-spinning wheel
            // in native HID mode sends line-based ones. Leave continuous events alone.
            guard event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0,
                  config.withLock({ $0.invertScroll }) else { break }
            event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: -event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: -event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: -event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1))

        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let port = tapPort.withLock({ $0 })?.port { CGEvent.tapEnable(tap: port, enable: true) }
            Self.logger.notice("Event tap re-enabled after \(type.rawValue)")

        default:
            break
        }
        return Unmanaged.passUnretained(event)
    }
}
