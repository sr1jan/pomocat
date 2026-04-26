import Foundation
import Testing
import Combine
@testable import fatcat

final class TestClock {
    private(set) var callback: (() -> Void)?

    func schedule(_ interval: TimeInterval, _ callback: @escaping () -> Void) -> AnyCancellable {
        self.callback = callback
        return AnyCancellable { [weak self] in self?.callback = nil }
    }

    func advance(ticks: Int) {
        for _ in 0..<ticks { callback?() }
    }
}

final class TestIdleSource {
    var seconds: TimeInterval = 0
    func read() -> TimeInterval { seconds }
}

@Test
func accumulates_active_seconds_when_not_idle() {
    let clock = TestClock()
    let idle = TestIdleSource()
    idle.seconds = 0

    let scheduler = BreakScheduler(
        workDuration: 10,
        breakDuration: 3,
        idleResetThreshold: 60,
        pollInterval: 1,
        idleSource: idle.read,
        scheduleTick: clock.schedule
    )
    scheduler.start()

    clock.advance(ticks: 5)

    #expect(scheduler.accumulatedActiveSeconds == 5, "Should accumulate 5 seconds of active time")
}
