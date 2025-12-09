import SwiftUI
import Foundation

@main
struct MotionCamApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 1200, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open File...") {
                    appState.showOpenFilePanel()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
    }
}