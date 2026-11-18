import SwiftUI
import AppKit

@main
struct PortsideApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings = AppSettings.shared
    @StateObject private var ports = PortStore.shared
    @StateObject private var repos = RepoStore.shared

    var body: some Scene {
        MenuBarExtra {
            RootView()
                .environmentObject(settings)
                .environmentObject(ports)
                .environmentObject(repos)
        } label: {
            MenuBarLabel(ports: ports, settings: settings)
        }
        .menuBarExtraStyle(.window)

        Window("Traffic Inspector", id: "traffic") {
            TrafficWindow()
                .environmentObject(settings)
                .environmentObject(ports)
        }
        .defaultSize(width: 1040, height: 680)
        .windowResizability(.contentMinSize)
    }
}

struct MenuBarLabel: View {
    @ObservedObject var ports: PortStore
    @ObservedObject var settings: AppSettings

    var body: some View {
        let count = ports.devPorts.count
        HStack(spacing: 3) {
            Image(systemName: ports.hasLiveShares ? "sailboat.fill" : "sailboat")
            if settings.showCountInMenuBar && count > 0 {
                Text(verbatim: "\(count)")
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppSettings.shared.applyAppearance()
        AppSettings.shared.startObservingSystemTheme()
        PortStore.shared.start()
        RepoStore.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        PortStore.shared.shutdown()
    }
}
