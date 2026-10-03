import AppKit
import GameController
import SSMTCore
import SwiftUI

/// Runs the hidden game at 60 steps per second: input from the keyboard or a gamepad, world step,
/// pixel rendering into a 320×224 image scaled without smoothing.
@MainActor
final class GameController: ObservableObject {
    @Published private(set) var image: CGImage?
    @Published var musicOn = true { didSet { sound.setMusic(musicOn) } }
    private let world = GameWorld(seed: UInt64(Date().timeIntervalSince1970))
    private let renderer = GameRenderer()
    private let sound = GameSound()
    private var timer: Timer?
    private var keys = Set<UInt16>()
    private var monitor: Any?
    var onClose: (() -> Void)?

    func start() {
        sound.start()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] e in
            guard let self else { return e }
            return MainActor.assumeIsolated {
                guard e.window?.title == GameWindow.title else { return e }
                if e.type == .keyDown {
                    if e.keyCode == 53 { self.onClose?(); return nil }   // Esc
                    if e.keyCode == 46 { self.musicOn.toggle(); return nil } // M
                    self.keys.insert(e.keyCode)
                } else {
                    self.keys.remove(e.keyCode)
                }
                return nil
            }
        }
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        sound.stop()
    }

    private func input() -> GameInput {
        var i = GameInput()
        let k = keys
        i.left = k.contains(123) || k.contains(0)          // ← or A
        i.right = k.contains(124) || k.contains(2)         // → or D
        i.down = k.contains(125) || k.contains(1)          // ↓ or S
        i.up = k.contains(126) || k.contains(13)           // ↑ or W
        i.jump = k.contains(49) || i.up                    // space
        i.punch = k.contains(6) || k.contains(38)          // Z or J
        i.kick = k.contains(7) || k.contains(40)           // X or K
        i.item1 = k.contains(18); i.item2 = k.contains(19); i.item3 = k.contains(20)
        i.start = k.contains(36) || k.contains(76)         // Return / Enter
        // Gamepad: d-pad or left stick, A jump, X punch, B kick, Y / shoulder buttons items, menu start.
        if let pad = GCController.current?.extendedGamepad {
            let x = pad.leftThumbstick.xAxis.value, y = pad.leftThumbstick.yAxis.value
            i.left = i.left || pad.dpad.left.isPressed || x < -0.4
            i.right = i.right || pad.dpad.right.isPressed || x > 0.4
            i.down = i.down || pad.dpad.down.isPressed || y < -0.5
            i.jump = i.jump || pad.buttonA.isPressed
            i.punch = i.punch || pad.buttonX.isPressed
            i.kick = i.kick || pad.buttonB.isPressed
            i.item1 = i.item1 || pad.buttonY.isPressed
            i.item2 = i.item2 || pad.leftShoulder.isPressed
            i.item3 = i.item3 || pad.rightShoulder.isPressed
            i.start = i.start || pad.buttonMenu.isPressed
        }
        return i
    }

    private func tick() {
        world.step(input())
        for e in world.events { sound.play(e) }
        let fb = renderer.render(world)
        image = Self.makeImage(fb)
    }

    private static func makeImage(_ fb: Framebuffer) -> CGImage? {
        let bytes = fb.rgbaBytes
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: fb.width, height: fb.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: fb.width * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

struct GameScreen: View {
    @StateObject private var game = GameController()
    var close: () -> Void

    var body: some View {
        ZStack {
            Color.black
            if let img = game.image {
                Image(decorative: img, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .aspectRatio(320.0 / 224.0, contentMode: .fit)
            }
        }
        .onAppear {
            game.onClose = close
            game.start()
        }
        .onDisappear { game.stop() }
    }
}

/// The hidden game's own window.
@MainActor
final class GameWindow {
    static let title = "САУНДЧЕК МЁРТВЫХ"
    private static var window: NSWindow?

    static func show() {
        if let w = window { w.makeKeyAndOrderFront(nil); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 672),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        w.title = title
        w.contentAspectRatio = NSSize(width: 320, height: 224)
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: GameScreen(close: { GameWindow.close() }))
        w.center()
        w.makeKeyAndOrderFront(nil)
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
            MainActor.assumeIsolated {
                GameWindow.window?.contentView = nil
                GameWindow.window = nil
            }
        }
        window = w
    }

    static func close() { window?.close() }
}

/// The way in: the Konami code (↑ ↑ ↓ ↓ ← → ← → B A) typed anywhere in SSMT.
@MainActor
enum SecretCode {
    private static let code: [UInt16] = [126, 126, 125, 125, 123, 124, 123, 124, 11, 0]
    private static var progress = 0
    private static var monitor: Any?

    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            MainActor.assumeIsolated {
                if let r = NSApp.keyWindow?.firstResponder, r is NSText || r is NSTextView { progress = 0; return }
                if e.keyCode == code[progress] {
                    progress += 1
                    if progress == code.count { progress = 0; GameWindow.show() }
                } else {
                    progress = e.keyCode == code[0] ? 1 : 0
                }
            }
            return e
        }
    }
}
