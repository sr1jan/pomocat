import Foundation
import Combine
import IOKit

// IOHIDSystem's HIDIdleTime is the canonical macOS idle source — works without
// Input Monitoring/Accessibility permission, unlike CGEventSource which silently
// returns bogus values (~28 days) when the caller lacks entitlements, breaking
// the scheduler's "are you active?" check entirely under launchd.
func realIdleSource() -> TimeInterval {
    var iter: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"), &iter) == KERN_SUCCESS else { return 0 }
    defer { IOObjectRelease(iter) }
    let entry = IOIteratorNext(iter)
    guard entry != 0 else { return 0 }
    defer { IOObjectRelease(entry) }
    var props: Unmanaged<CFMutableDictionary>?
    guard IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
          let dict = props?.takeRetainedValue() as? [String: Any],
          let ns = dict["HIDIdleTime"] as? UInt64 else { return 0 }
    return TimeInterval(ns) / 1_000_000_000.0
}

func realTimer(interval: TimeInterval, _ callback: @escaping () -> Void) -> AnyCancellable {
    let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in callback() }
    RunLoop.main.add(timer, forMode: .common)
    return AnyCancellable { timer.invalidate() }
}

final class BreakScheduler {
    var onBreakStart: (() -> Void)?
    var onBreakTick: ((TimeInterval) -> Void)?
    var onBreakEnd: (() -> Void)?

    private let workDuration: TimeInterval
    private let breakDuration: TimeInterval
    private let idleResetThreshold: TimeInterval
    private let pollInterval: TimeInterval
    private let idleSource: () -> TimeInterval
    private let scheduleTick: (TimeInterval, @escaping () -> Void) -> AnyCancellable

    private(set) var accumulatedActiveSeconds: TimeInterval = 0
    private var breakRemaining: TimeInterval? = nil
    private var ticker: AnyCancellable? = nil

    init(
        workDuration: TimeInterval = Config.workDuration,
        breakDuration: TimeInterval = Config.breakDuration,
        idleResetThreshold: TimeInterval = Config.idleResetThreshold,
        pollInterval: TimeInterval = Config.pollInterval,
        idleSource: @escaping () -> TimeInterval = realIdleSource,
        scheduleTick: @escaping (TimeInterval, @escaping () -> Void) -> AnyCancellable = realTimer
    ) {
        self.workDuration = workDuration
        self.breakDuration = breakDuration
        self.idleResetThreshold = idleResetThreshold
        self.pollInterval = pollInterval
        self.idleSource = idleSource
        self.scheduleTick = scheduleTick
    }

    func start() {
        ticker = scheduleTick(pollInterval) { [weak self] in self?.tick() }
    }

    func tick() {
        if var remaining = breakRemaining {
            remaining -= pollInterval
            if remaining <= 0 {
                breakRemaining = nil
                accumulatedActiveSeconds = 0
                onBreakEnd?()
                return
            }
            breakRemaining = remaining
            onBreakTick?(remaining)
            return
        }
        let idle = idleSource()
        if idle >= idleResetThreshold {
            return
        }
        accumulatedActiveSeconds += pollInterval
        if accumulatedActiveSeconds >= workDuration {
            breakRemaining = breakDuration
            onBreakStart?()
        }
    }
}
