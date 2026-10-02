import AppKit
import SwiftUI

@main
struct SSMTApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    @StateObject private var localizer = Localizer()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(model)
                .environmentObject(localizer)
                .onAppear { appDelegate.model = model }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandMenu("SSMT") {
                Button(localizer.t("action.stop")) { model.emergencyStop() }
                    .keyboardShortcut(.escape, modifiers: [])
                Button(localizer.t("noise.toggle")) { model.toggleNoise() }
                    .keyboardShortcut("n", modifiers: [.command])
                Button(localizer.t("delay.find")) { model.findDelay() }
                    .keyboardShortcut("d", modifiers: [.command])
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Esc = STOP everywhere in the app, even while a text field or picker has focus.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                Task { @MainActor in self?.model?.emergencyStop() }
            }
            return event
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.stopEngine()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
