import Foundation

enum Config {
    static let workDuration: TimeInterval = 60 * 60        // 60 min of activity
    static let breakDuration: TimeInterval = 5 * 60        // 5 min cat (Pomodoro short break)
    static let idleResetThreshold: TimeInterval = 60       // 1 min idle = pause
    static let assetPath: String = "Assets/cat.mov"        // relative to launch dir
    static let pollInterval: TimeInterval = 1.0            // tick rate
}
