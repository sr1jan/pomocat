import Foundation
import Combine
import CoreGraphics

func realIdleSource() -> TimeInterval {
    // CGEventType raw value 0 means "any/null event" — returns time since the last event of any kind.
    CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: 0)!)
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
        if breakRemaining != nil {
            // In break — handled in Task 7
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
