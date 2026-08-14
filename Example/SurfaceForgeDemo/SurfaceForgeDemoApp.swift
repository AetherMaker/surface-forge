import SwiftUI

@main
struct SurfaceForgeDemoApp: App {
    /// The render tests use this app only as a window host and read pixels
    /// back from their own windows. Four live surfaces animating behind them
    /// is GPU load and motion the measurements never asked for, so the room
    /// stays dark under test.
    private var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    var body: some Scene {
        WindowGroup {
            if isRunningTests {
                Color.black.ignoresSafeArea()
            } else {
                RoomView()
            }
        }
    }
}
