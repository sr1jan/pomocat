import Foundation
import Testing
import Combine
@testable import pomocat

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

@Test
func pauses_accumulator_when_idle_above_threshold() {
    let clock = TestClock()
    let idle = TestIdleSource()
    idle.seconds = 120  // way above threshold

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

    #expect(scheduler.accumulatedActiveSeconds == 0, "Should not accumulate while idle")
}

@Test
func fires_onBreakStart_when_workDuration_reached() {
    let clock = TestClock()
    let idle = TestIdleSource()
    idle.seconds = 0

    var startCount = 0
    let scheduler = BreakScheduler(
        workDuration: 5,
        breakDuration: 3,
        idleResetThreshold: 60,
        pollInterval: 1,
        idleSource: idle.read,
        scheduleTick: clock.schedule
    )
    scheduler.onBreakStart = { startCount += 1 }
    scheduler.start()

    clock.advance(ticks: 5)
    #expect(startCount == 1, "Should fire onBreakStart exactly once at workDuration")

    clock.advance(ticks: 1)
    #expect(startCount == 1, "Should not fire again on subsequent ticks while in break")
}

@Test
func decrements_breakRemaining_during_break() {
    let clock = TestClock()
    let idle = TestIdleSource()
    idle.seconds = 0

    var lastTickValue: TimeInterval? = nil
    let scheduler = BreakScheduler(
        workDuration: 1,           // tiny so we enter break after 1 tick
        breakDuration: 10,
        idleResetThreshold: 60,
        pollInterval: 1,
        idleSource: idle.read,
        scheduleTick: clock.schedule
    )
    scheduler.onBreakTick = { lastTickValue = $0 }
    scheduler.start()

    clock.advance(ticks: 1)        // triggers onBreakStart, enters break
    clock.advance(ticks: 3)        // 3 break ticks: 10 → 9 → 8 → 7

    #expect(lastTickValue == 7, "Last onBreakTick should fire with 7 (10 - 3)")
}

@Test
func fires_onBreakEnd_and_resets_when_break_completes() {
    let clock = TestClock()
    let idle = TestIdleSource()
    idle.seconds = 0

    var endCount = 0
    let scheduler = BreakScheduler(
        workDuration: 1,
        breakDuration: 3,
        idleResetThreshold: 60,
        pollInterval: 1,
        idleSource: idle.read,
        scheduleTick: clock.schedule
    )
    scheduler.onBreakEnd = { endCount += 1 }
    scheduler.start()

    clock.advance(ticks: 1)        // enter break, breakRemaining=3
    clock.advance(ticks: 3)        // 3 → 2 → 1 → 0 (onBreakEnd fires on the 0 tick)

    #expect(endCount == 1, "onBreakEnd should fire exactly once")
    #expect(scheduler.accumulatedActiveSeconds == 0, "Accumulator should reset to 0")
}

@Test
func transition_to_working_clears_breakRemaining() {
    let clock = TestClock()
    let idle = TestIdleSource()
    idle.seconds = 0

    let scheduler = BreakScheduler(
        workDuration: 1,
        breakDuration: 3,
        idleResetThreshold: 60,
        pollInterval: 1,
        idleSource: idle.read,
        scheduleTick: clock.schedule
    )
    scheduler.start()

    clock.advance(ticks: 1)        // enter break
    clock.advance(ticks: 3)        // exit break, accumulator reset to 0
    clock.advance(ticks: 1)        // back in working state, accumulate 1s

    #expect(scheduler.accumulatedActiveSeconds == 1, "Should be back in working state, accumulating again")
}
