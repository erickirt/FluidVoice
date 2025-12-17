import AppKit
import ApplicationServices
import SwiftUI

@main
struct FluidApp: App {
    @StateObject private var menuBarManager = MenuBarManager()
    @StateObject private var appServices = AppServices.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var theme = AppTheme.dark

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(self.menuBarManager)
                .environmentObject(self.appServices)
                .appTheme(self.theme)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1000, height: 700)
        .windowResizability(.contentSize)
    }
}
