import AppKit
import Foundation

// MARK: - Config Parsing

struct ImageEntry: Codable {
    let path: String
    let position: [Double]?
    let size: [Double]?
    let zoom: Double?
}

struct WallpapersConfig: Codable {
    let files: [ImageEntry]
}

struct VPCConfig: Codable {
    let wallpapers: WallpapersConfig
}

func expandHome(_ path: String) -> String {
    path.replacingOccurrences(of: "$HOME", with: NSHomeDirectory())
}

// MARK: - ImageCanvasView

class ImageCanvasView: NSView {
    let image: NSImage
    var zoom: Double
    let filePath: String

    init(image: NSImage, zoom: Double, filePath: String) {
        self.image = image
        self.zoom = zoom
        self.filePath = filePath
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        dirtyRect.fill()

        guard let rep = image.representations.first else { return }
        let imgW = Double(rep.pixelsWide)
        let imgH = Double(rep.pixelsHigh)
        let viewW = Double(bounds.width)
        let viewH = Double(bounds.height)

        // Aspect-fill: scale so image covers the view, then apply zoom
        let scale = max(viewW / imgW, viewH / imgH) * zoom
        let drawW = imgW * scale
        let drawH = imgH * scale
        let drawX = (viewW - drawW) / 2.0
        let drawY = (viewH - drawH) / 2.0

        image.draw(in: NSRect(x: drawX, y: drawY, width: drawW, height: drawH))
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY * 0.005
        zoom = min(10.0, max(0.1, zoom + delta))
        needsDisplay = true
    }
}

// MARK: - WallWindow

class WallWindow: NSWindow {
    override var canBecomeKey: Bool { true }

    init(rect: NSRect) {
        super.init(
            contentRect: rect,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        isMovableByWindowBackground = true
        isRestorable = false
        backgroundColor = .black
        level = .normal
        collectionBehavior = [.moveToActiveSpace]
    }
}

// MARK: - Window Factory

func createWindows(entries: [ImageEntry]) -> [WallWindow] {
    guard let screen = NSScreen.main else { return [] }
    let screenFrame = screen.frame
    let screenH = screenFrame.height

    var windows: [WallWindow] = []

    for entry in entries {
        let expanded = expandHome(entry.path)
        guard let image = NSImage(contentsOfFile: expanded) else {
            print("Warning: Could not load image: \(expanded)")
            continue
        }

        let zoom = entry.zoom ?? 1.0

        // Determine window size
        let winW: Double
        let winH: Double
        if let sz = entry.size, sz.count == 2 {
            winW = sz[0]
            winH = sz[1]
        } else if let rep = image.representations.first {
            winW = Double(rep.pixelsWide)
            winH = Double(rep.pixelsHigh)
        } else {
            winW = image.size.width
            winH = image.size.height
        }

        // Determine position (convert top-left to macOS bottom-left)
        let winX: Double
        let winY: Double
        if let pos = entry.position, pos.count == 2 {
            winX = pos[0]
            winY = screenH - pos[1] - winH
        } else {
            // Center on main screen
            winX = screenFrame.origin.x + (screenFrame.width - winW) / 2.0
            winY = screenFrame.origin.y + (screenFrame.height - winH) / 2.0
        }

        let rect = NSRect(x: winX, y: winY, width: winW, height: winH)
        let window = WallWindow(rect: rect)
        let canvas = ImageCanvasView(image: image, zoom: zoom, filePath: entry.path)
        window.contentView = canvas
        window.orderFront(nil)
        windows.append(window)
    }

    return windows
}

// MARK: - Snapshot

func writeSnapshot(windows: [WallWindow]) {
    guard let screen = NSScreen.main else { return }
    let screenH = screen.frame.height
    let home = NSHomeDirectory()

    var entries: [[String: Any]] = []
    for window in windows {
        guard let canvas = window.contentView as? ImageCanvasView else { continue }
        let frame = window.frame

        // Convert macOS bottom-left Y back to top-left
        let topY = screenH - frame.origin.y - frame.height

        let portablePath = canvas.filePath.replacingOccurrences(of: home, with: "$HOME")

        let entry: [String: Any] = [
            "path": portablePath,
            "position": [Int(frame.origin.x), Int(topY)],
            "size": [Int(frame.width), Int(frame.height)],
            "zoom": canvas.zoom
        ]
        entries.append(entry)
    }

    guard let data = try? JSONSerialization.data(
        withJSONObject: entries,
        options: [.prettyPrinted, .sortedKeys]
    ) else { return }

    let path = "/tmp/image-wall-snapshot.json"
    try? data.write(to: URL(fileURLWithPath: path))
}

// MARK: - Snapshot CLI mode

func runSnapshotMode() -> Int32 {
    // Find running instance and send SIGUSR1
    let pgrep = Process()
    pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    pgrep.arguments = ["-x", "image-wall"]
    let pipe = Pipe()
    pgrep.standardOutput = pipe
    do {
        try pgrep.run()
        pgrep.waitUntilExit()
    } catch {
        print("Error: Could not find running image-wall process")
        return 1
    }

    let pidData = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let pidStr = String(data: pidData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
          let pid = pid_t(pidStr.components(separatedBy: "\n").first ?? "") else {
        print("Error: No running image-wall process found")
        return 1
    }

    kill(pid, SIGUSR1)

    // Wait for snapshot file
    Thread.sleep(forTimeInterval: 0.5)

    let path = "/tmp/image-wall-snapshot.json"
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
          let str = String(data: data, encoding: .utf8) else {
        print("Error: Could not read snapshot file")
        return 1
    }
    print(str)
    return 0
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var windows: [WallWindow] = []
    var entries: [ImageEntry] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        windows = createWindows(entries: entries)

        // Register SIGUSR1 handler for snapshot
        let src = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        src.setEventHandler { [weak self] in
            guard let self = self else { return }
            writeSnapshot(windows: self.windows)
        }
        src.resume()
        signal(SIGUSR1, SIG_IGN) // Let dispatch source handle it
    }
}

// MARK: - Main

if CommandLine.arguments.contains("--snapshot") {
    exit(runSnapshotMode())
}

guard CommandLine.arguments.count > 1 else {
    print("Usage: image-wall <vpc-file>")
    print("       image-wall --snapshot")
    exit(1)
}

let configPath = CommandLine.arguments[1]
guard let configData = try? Data(contentsOf: URL(fileURLWithPath: configPath)) else {
    print("Error: Could not read config file: \(configPath)")
    exit(1)
}
guard let config = try? JSONDecoder().decode(VPCConfig.self, from: configData) else {
    print("Error: Could not parse wallpapers config from: \(configPath)")
    exit(1)
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)

let delegate = AppDelegate()
delegate.entries = config.wallpapers.files
app.delegate = delegate
app.run()
