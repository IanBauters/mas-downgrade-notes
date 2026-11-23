import SwiftUI
import AppKit

@main
struct KeeperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var pipeline = Pipeline()

    var body: some Scene {
        WindowGroup("Keeper") {
            ContentView()
                .environmentObject(pipeline)
                .frame(minWidth: 640, minHeight: 660)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// Tells a running watcher (which may run as root) to stop.
    func applicationWillTerminate(_ notification: Notification) {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let stop = caches.appendingPathComponent("Keeper", isDirectory: true).appendingPathComponent("stop")
        FileManager.default.createFile(atPath: stop.path, contents: Data())
    }
}
