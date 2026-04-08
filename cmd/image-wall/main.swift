import AppKit
import AVFoundation
import AVKit
import CoreMedia
import Foundation
import ObjectiveC
import UniformTypeIdentifiers

// MARK: - Config Parsing

struct ImageEntry: Codable {
    let path: String
    let position: [Double]?
    let size: [Double]?
    let zoom: Double?
    let pan: [Double]?
    let lock: Bool?
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
    var panOffset: CGPoint = .zero

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
        let drawX = (viewW - drawW) / 2.0 + Double(panOffset.x)
        let drawY = (viewH - drawH) / 2.0 + Double(panOffset.y)

        image.draw(in: NSRect(x: drawX, y: drawY, width: drawW, height: drawH))
    }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        menu.removeAllItems()
        if let delegate = NSApplication.shared.delegate as? AppDelegate {
            delegate.addImageMenuItems(to: menu, canvas: self)
        }
    }

    private var lastScrollSaveTime: Date = .distantPast

    override func scrollWheel(with event: NSEvent) {
        guard !((window as? WallWindow)?.isLocked ?? false) else { return }

        if event.modifierFlags.contains(.option) {
            // Option+scroll = pan
            if let w = window as? WallWindow, Date().timeIntervalSince(lastScrollSaveTime) > 0.5 {
                (NSApplication.shared.delegate as? AppDelegate)?.imageUndoManager.saveState(for: w)
                lastScrollSaveTime = Date()
            }
            panOffset.x += event.scrollingDeltaX * 2.0
            panOffset.y -= event.scrollingDeltaY * 2.0
            needsDisplay = true
        } else if event.modifierFlags.contains(.control) {
            // Ctrl+scroll = zoom
            if let w = window as? WallWindow, Date().timeIntervalSince(lastScrollSaveTime) > 0.5 {
                (NSApplication.shared.delegate as? AppDelegate)?.imageUndoManager.saveState(for: w)
                lastScrollSaveTime = Date()
            }
            let delta = event.scrollingDeltaY * 0.005
            zoom = min(10.0, max(0.1, zoom + delta))
            needsDisplay = true
        }
    }

    var filename: String {
        (filePath as NSString).lastPathComponent
    }
}

// MARK: - Video file detection

let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "webm", "avi", "mkv"]

func isVideoFile(_ path: String) -> Bool {
    let ext = (path as NSString).pathExtension.lowercased()
    return videoExtensions.contains(ext)
}

// MARK: - VideoCanvasView

class VideoCanvasView: NSView {
    let filePath: String
    var zoom: Double
    var panOffset: CGPoint = .zero

    private var player: AVQueuePlayer!
    private var playerLayer: AVPlayerLayer!
    private var looper: AVPlayerLooper!
    private var playerItem: AVPlayerItem!

    init(url: URL, zoom: Double, filePath: String) {
        self.filePath = filePath
        self.zoom = zoom
        super.init(frame: .zero)
        wantsLayer = true

        let asset = AVURLAsset(url: url)
        playerItem = AVPlayerItem(asset: asset)
        player = AVQueuePlayer(items: [playerItem])
        player.isMuted = true
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(asset: asset))

        playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(playerLayer)

        player.play()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        updatePlayerLayerFrame()
    }

    private func updatePlayerLayerFrame() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let viewW = bounds.width
        let viewH = bounds.height
        let layerW = viewW * zoom
        let layerH = viewH * zoom
        let layerX = (viewW - layerW) / 2.0 + panOffset.x
        let layerY = (viewH - layerH) / 2.0 + panOffset.y

        playerLayer.frame = CGRect(x: layerX, y: layerY, width: layerW, height: layerH)
        CATransaction.commit()
    }

    func applyZoomAndPan() {
        updatePlayerLayerFrame()
    }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        menu.removeAllItems()
        if let delegate = NSApplication.shared.delegate as? AppDelegate {
            delegate.addImageMenuItems(to: menu, canvas: self)
        }
    }

    private var lastScrollSaveTime: Date = .distantPast

    override func scrollWheel(with event: NSEvent) {
        guard !((window as? WallWindow)?.isLocked ?? false) else { return }

        if event.modifierFlags.contains(.option) {
            if let w = window as? WallWindow, Date().timeIntervalSince(lastScrollSaveTime) > 0.5 {
                (NSApplication.shared.delegate as? AppDelegate)?.imageUndoManager.saveState(for: w)
                lastScrollSaveTime = Date()
            }
            panOffset.x += event.scrollingDeltaX * 2.0
            panOffset.y -= event.scrollingDeltaY * 2.0
            applyZoomAndPan()
        } else if event.modifierFlags.contains(.control) {
            if let w = window as? WallWindow, Date().timeIntervalSince(lastScrollSaveTime) > 0.5 {
                (NSApplication.shared.delegate as? AppDelegate)?.imageUndoManager.saveState(for: w)
                lastScrollSaveTime = Date()
            }
            let delta = event.scrollingDeltaY * 0.005
            zoom = min(10.0, max(0.1, zoom + delta))
            applyZoomAndPan()
        }
    }

    var filename: String {
        (filePath as NSString).lastPathComponent
    }
}

// MARK: - Canvas Protocol helpers

/// Shared interface for both image and video canvas views
protocol WallCanvas: NSView {
    var zoom: Double { get set }
    var panOffset: CGPoint { get set }
    var filePath: String { get }
    var filename: String { get }
}

extension ImageCanvasView: WallCanvas {}
extension VideoCanvasView: WallCanvas {}

func wallCanvas(of window: WallWindow) -> WallCanvas? {
    return window.contentView as? WallCanvas
}

// MARK: - WallWindow

class WallWindow: NSWindow {
    override var canBecomeKey: Bool { true }

    var isLocked = false {
        didSet { isMovableByWindowBackground = !isLocked }
    }

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

    override func mouseDown(with event: NSEvent) {
        if !isLocked {
            // About to drag-move — save state for undo
            (NSApplication.shared.delegate as? AppDelegate)?.imageUndoManager.saveState(for: self)
        }
        super.mouseDown(with: event)
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
        let zoom = entry.zoom ?? 1.0

        if isVideoFile(expanded) {
            // Video file — use AVFoundation player
            let url = URL(fileURLWithPath: expanded)
            guard FileManager.default.fileExists(atPath: expanded) else {
                print("Warning: Could not find video: \(expanded)")
                continue
            }

            // Get video dimensions for default window size
            let asset = AVURLAsset(url: url)
            var videoSize = CGSize(width: 640, height: 480)
            let semaphore = DispatchSemaphore(value: 0)
            Task {
                if let track = try? await asset.loadTracks(withMediaType: .video).first {
                    let size = try? await track.load(.naturalSize)
                    let transform = try? await track.load(.preferredTransform)
                    if let size = size, let transform = transform {
                        let natural = size.applying(transform)
                        videoSize = CGSize(width: abs(natural.width), height: abs(natural.height))
                    }
                }
                semaphore.signal()
            }
            semaphore.wait()

            let winW: Double
            let winH: Double
            if let sz = entry.size, sz.count == 2 {
                winW = sz[0]
                winH = sz[1]
            } else {
                winW = min(Double(videoSize.width), 1280)
                winH = min(Double(videoSize.height), 720)
            }

            let winX: Double
            let winY: Double
            if let pos = entry.position, pos.count == 2 {
                winX = pos[0]
                winY = screenH - pos[1] - winH
            } else {
                winX = screenFrame.origin.x + (screenFrame.width - winW) / 2.0
                winY = screenFrame.origin.y + (screenFrame.height - winH) / 2.0
            }

            let rect = NSRect(x: winX, y: winY, width: winW, height: winH)
            let window = WallWindow(rect: rect)
            let canvas = VideoCanvasView(url: url, zoom: zoom, filePath: entry.path)

            if let pan = entry.pan, pan.count == 2 {
                canvas.panOffset = CGPoint(x: pan[0], y: pan[1])
            }
            if entry.lock == true {
                window.isLocked = true
            }

            window.contentView = canvas
            window.orderFront(nil)
            windows.append(window)
        } else {
            // Image file
            guard let image = NSImage(contentsOfFile: expanded) else {
                print("Warning: Could not load image: \(expanded)")
                continue
            }

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

            let winX: Double
            let winY: Double
            if let pos = entry.position, pos.count == 2 {
                winX = pos[0]
                winY = screenH - pos[1] - winH
            } else {
                winX = screenFrame.origin.x + (screenFrame.width - winW) / 2.0
                winY = screenFrame.origin.y + (screenFrame.height - winH) / 2.0
            }

            let rect = NSRect(x: winX, y: winY, width: winW, height: winH)
            let window = WallWindow(rect: rect)
            let canvas = ImageCanvasView(image: image, zoom: zoom, filePath: entry.path)

            if let pan = entry.pan, pan.count == 2 {
                canvas.panOffset = CGPoint(x: pan[0], y: pan[1])
            }
            if entry.lock == true {
                window.isLocked = true
            }

            window.contentView = canvas
            window.orderFront(nil)
            windows.append(window)
        }
    }

    return windows
}

// MARK: - Snapshot

func buildSnapshotEntries(windows: [WallWindow]) -> [[String: Any]] {
    guard let screen = NSScreen.main else { return [] }
    let screenH = screen.frame.height
    let home = NSHomeDirectory()

    var entries: [[String: Any]] = []
    for window in windows {
        guard let canvas = wallCanvas(of: window) else { continue }
        let frame = window.frame

        // Convert macOS bottom-left Y back to top-left
        let topY = screenH - frame.origin.y - frame.height

        let portablePath = canvas.filePath.replacingOccurrences(of: home, with: "$HOME")

        var entry: [String: Any] = [
            "path": portablePath,
            "position": [Int(frame.origin.x), Int(topY)],
            "size": [Int(frame.width), Int(frame.height)],
            "zoom": canvas.zoom
        ]

        if canvas.panOffset.x != 0 || canvas.panOffset.y != 0 {
            entry["pan"] = [round(Double(canvas.panOffset.x) * 100) / 100,
                            round(Double(canvas.panOffset.y) * 100) / 100]
        }

        if window.isLocked {
            entry["lock"] = true
        }

        entries.append(entry)
    }
    return entries
}

func writeSnapshot(windows: [WallWindow]) {
    let entries = buildSnapshotEntries(windows: windows)

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

// MARK: - Undo System

struct WindowState {
    let zoom: Double
    let panOffset: CGPoint
    let windowFrame: NSRect
}

struct UndoEntry {
    let window: WallWindow
    let state: WindowState
}

class ImageUndoManager {
    private var undoStack: [UndoEntry] = []
    private var redoStack: [UndoEntry] = []
    private let maxDepth = 50

    func saveState(for window: WallWindow) {
        guard let canvas = wallCanvas(of: window) else { return }
        let state = WindowState(zoom: canvas.zoom, panOffset: canvas.panOffset, windowFrame: window.frame)
        undoStack.append(UndoEntry(window: window, state: state))
        if undoStack.count > maxDepth { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    func undo() {
        guard let entry = undoStack.popLast() else { return }
        guard let canvas = wallCanvas(of: entry.window) else { return }
        let current = WindowState(zoom: canvas.zoom, panOffset: canvas.panOffset, windowFrame: entry.window.frame)
        redoStack.append(UndoEntry(window: entry.window, state: current))
        canvas.zoom = entry.state.zoom
        canvas.panOffset = entry.state.panOffset
        entry.window.setFrame(entry.state.windowFrame, display: true)
        if let video = canvas as? VideoCanvasView { video.applyZoomAndPan() }
        (canvas as NSView).needsDisplay = true
    }

    func redo() {
        guard let entry = redoStack.popLast() else { return }
        guard let canvas = wallCanvas(of: entry.window) else { return }
        let current = WindowState(zoom: canvas.zoom, panOffset: canvas.panOffset, windowFrame: entry.window.frame)
        undoStack.append(UndoEntry(window: entry.window, state: current))
        canvas.zoom = entry.state.zoom
        canvas.panOffset = entry.state.panOffset
        entry.window.setFrame(entry.state.windowFrame, display: true)
        if let video = canvas as? VideoCanvasView { video.applyZoomAndPan() }
        (canvas as NSView).needsDisplay = true
    }

    func purge(window: WallWindow) {
        undoStack.removeAll { $0.window === window }
        redoStack.removeAll { $0.window === window }
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
}

private var kCanvasKey: UInt8 = 0

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var windows: [WallWindow] = []
    var entries: [ImageEntry] = []
    var configPath: String = ""
    var signalSource: DispatchSourceSignal?
    var statusItem: NSStatusItem?
    let imageUndoManager = ImageUndoManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        windows = createWindows(entries: entries)

        // Set up context menus on each window (willOpenMenu rebuilds dynamically)
        for window in windows {
            if let canvas = window.contentView, canvas is WallCanvas {
                canvas.menu = NSMenu()
            }
        }

        setupMainMenu()

        // Create menu bar status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            var img: NSImage? = nil
            if #available(macOS 11.0, *) {
                img = NSImage(systemSymbolName: "photo.on.rectangle", accessibilityDescription: "Image Wall")
            }
            if let img = img {
                button.image = img
            } else {
                button.title = "IW"
            }
        }
        rebuildMenu()

        // Register SIGUSR1 handler for snapshot
        signal(SIGUSR1, SIG_IGN) // Let dispatch source handle it
        let src = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        src.setEventHandler { [weak self] in
            guard let self = self else { return }
            writeSnapshot(windows: self.windows)
        }
        src.resume()
        signalSource = src
    }

    // MARK: - Main Menu Bar

    func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Image Wall", action: nil, keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit Image Wall", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // File menu
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        let addItem = fileMenu.addItem(withTitle: "Add Image...", action: #selector(doAddImage), keyEquivalent: "o")
        addItem.target = self
        let saveItem = fileMenu.addItem(withTitle: "Save to VPC", action: #selector(doSaveToVPC), keyEquivalent: "s")
        saveItem.target = self
        fileMenu.addItem(NSMenuItem.separator())
        let snapItem = fileMenu.addItem(withTitle: "Snapshot", action: #selector(doSnapshot), keyEquivalent: "")
        snapItem.target = self
        let reloadItem = fileMenu.addItem(withTitle: "Reload from VPC", action: #selector(doReload), keyEquivalent: "r")
        reloadItem.target = self
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // Edit menu
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        let undoItem = editMenu.addItem(withTitle: "Undo", action: #selector(doUndo), keyEquivalent: "z")
        undoItem.target = self
        let redoItem = editMenu.addItem(withTitle: "Redo", action: #selector(doRedo), keyEquivalent: "Z")
        redoItem.target = self
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    @objc func doUndo() {
        imageUndoManager.undo()
    }

    @objc func doRedo() {
        imageUndoManager.redo()
    }

    // MARK: - Menu Building

    func rebuildMenu() {
        let menu = NSMenu()

        menu.addItem(withTitle: "Snapshot", action: #selector(doSnapshot), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: "Reload from VPC", action: #selector(doReload), keyEquivalent: "")
            .target = self

        menu.addItem(NSMenuItem.separator())

        menu.addItem(withTitle: "Add Image...", action: #selector(doAddImage), keyEquivalent: "")
            .target = self

        menu.addItem(NSMenuItem.separator())

        menu.addItem(withTitle: "Save to VPC", action: #selector(doSaveToVPC), keyEquivalent: "")
            .target = self

        menu.addItem(NSMenuItem.separator())

        // Per-image submenus
        for window in windows {
            guard let canvas = wallCanvas(of: window) else { continue }
            let submenu = NSMenu()
            addImageMenuItems(to: submenu, canvas: canvas as NSView)
            let item = NSMenuItem(title: canvas.filename, action: nil, keyEquivalent: "")
            item.submenu = submenu
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        menu.addItem(withTitle: "Quit", action: #selector(doQuit), keyEquivalent: "q")
            .target = self

        menu.delegate = self
        statusItem?.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        // Only rebuild the status item menu (not context menus)
        guard menu === statusItem?.menu else { return }
        rebuildMenu()
    }

    func buildContextMenu(for canvas: NSView) -> NSMenu {
        let menu = NSMenu()
        addImageMenuItems(to: menu, canvas: canvas)
        return menu
    }

    func addImageMenuItems(to menu: NSMenu, canvas view: NSView) {
        guard let canvas = view as? WallCanvas else { return }
        let canvasView = canvas as NSView

        // Zoom submenu
        let zoomSubmenu = NSMenu()
        let currentZoom = NSMenuItem(title: String(format: "Zoom: %.2fx", canvas.zoom), action: nil, keyEquivalent: "")
        currentZoom.isEnabled = false
        zoomSubmenu.addItem(currentZoom)
        zoomSubmenu.addItem(NSMenuItem.separator())

        for (label, value) in [("Reset (1.0x)", 1.0), ("50%", 0.5), ("75%", 0.75), ("100%", 1.0), ("150%", 1.5), ("200%", 2.0)] {
            let item = NSMenuItem(title: label, action: #selector(doSetZoom(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = (canvasView, value)
            zoomSubmenu.addItem(item)
        }

        zoomSubmenu.addItem(NSMenuItem.separator())

        let zoomIn = NSMenuItem(title: "Zoom In (+0.25)", action: #selector(doZoomStep(_:)), keyEquivalent: "")
        zoomIn.target = self
        zoomIn.representedObject = (canvasView, 0.25)
        zoomSubmenu.addItem(zoomIn)

        let zoomOut = NSMenuItem(title: "Zoom Out (-0.25)", action: #selector(doZoomStep(_:)), keyEquivalent: "")
        zoomOut.target = self
        zoomOut.representedObject = (canvasView, -0.25)
        zoomSubmenu.addItem(zoomOut)

        zoomSubmenu.addItem(NSMenuItem.separator())

        let sliderItem = NSMenuItem()
        let slider = NSSlider(value: canvas.zoom, minValue: 0.1, maxValue: 5.0, target: self, action: #selector(doSliderZoom(_:)))
        slider.frame = NSRect(x: 20, y: 0, width: 160, height: 24)
        slider.isContinuous = true
        objc_setAssociatedObject(slider, &kCanvasKey, canvasView, .OBJC_ASSOCIATION_ASSIGN)
        let sliderContainer = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        sliderContainer.addSubview(slider)
        sliderItem.view = sliderContainer
        zoomSubmenu.addItem(sliderItem)

        let zoomItem = NSMenuItem(title: "Zoom", action: nil, keyEquivalent: "")
        zoomItem.submenu = zoomSubmenu
        menu.addItem(zoomItem)

        // Reset Pan
        let resetPan = NSMenuItem(title: "Reset Pan", action: #selector(doResetPan(_:)), keyEquivalent: "")
        resetPan.target = self
        resetPan.representedObject = canvasView
        menu.addItem(resetPan)

        // Lock Position
        let lockItem = NSMenuItem(title: "Lock Position", action: #selector(doToggleLock(_:)), keyEquivalent: "")
        lockItem.target = self
        lockItem.representedObject = canvasView
        lockItem.state = (canvas.window as? WallWindow)?.isLocked == true ? .on : .off
        menu.addItem(lockItem)

        // Snap to Edge submenu
        let snapSubmenu = NSMenu()
        for (label, tag) in [("Top-Left", 0), ("Top-Right", 1), ("Bottom-Left", 2), ("Bottom-Right", 3), ("Fill Screen", 4), ("Center", 5)] {
            let item = NSMenuItem(title: label, action: #selector(doSnapEdge(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = canvasView
            item.tag = tag
            snapSubmenu.addItem(item)
        }
        let snapItem = NSMenuItem(title: "Snap to Edge", action: nil, keyEquivalent: "")
        snapItem.submenu = snapSubmenu
        menu.addItem(snapItem)

        // Edit Size submenu
        let sizeSubmenu = NSMenu()
        for (label, w, h) in [("200 x 200", 200.0, 200.0), ("400 x 300", 400.0, 300.0), ("640 x 480", 640.0, 480.0), ("800 x 600", 800.0, 600.0), ("1024 x 768", 1024.0, 768.0), ("1920 x 1080", 1920.0, 1080.0)] {
            let item = NSMenuItem(title: label, action: #selector(doSetSize(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = (canvasView, w, h)
            sizeSubmenu.addItem(item)
        }
        let sizeItem = NSMenuItem(title: "Edit Size...", action: nil, keyEquivalent: "")
        sizeItem.submenu = sizeSubmenu
        menu.addItem(sizeItem)

        menu.addItem(NSMenuItem.separator())

        // Remove Image
        let removeItem = NSMenuItem(title: "Remove Image", action: #selector(doRemoveImage(_:)), keyEquivalent: "")
        removeItem.target = self
        removeItem.representedObject = canvasView
        menu.addItem(removeItem)
    }

    // MARK: - Global Actions

    @objc func doSnapshot() {
        writeSnapshot(windows: windows)
        print("Snapshot written to /tmp/image-wall-snapshot.json")
    }

    @objc func doReload() {
        guard !configPath.isEmpty else { return }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              let config = try? JSONDecoder().decode(VPCConfig.self, from: data) else {
            print("Error: Could not reload config from \(configPath)")
            return
        }

        // Close all existing windows
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()

        entries = config.wallpapers.files
        windows = createWindows(entries: entries)

        // Set up context menus (willOpenMenu rebuilds dynamically)
        for window in windows {
            if let canvas = window.contentView, canvas is WallCanvas {
                canvas.menu = NSMenu()
            }
        }

        rebuildMenu()
        print("Reloaded from \(configPath)")
    }

    @objc func doAddImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .gif, .tiff, .bmp, .webP]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let path = url.path
        guard let image = NSImage(contentsOfFile: path) else {
            print("Error: Could not load image: \(path)")
            return
        }

        let home = NSHomeDirectory()
        let portablePath = path.replacingOccurrences(of: home, with: "$HOME")

        // Default size from image or 400x400
        let winW: Double
        let winH: Double
        if let rep = image.representations.first {
            winW = min(Double(rep.pixelsWide), 800)
            winH = min(Double(rep.pixelsHigh), 600)
        } else {
            winW = 400
            winH = 400
        }

        // Center on screen
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame
        let winX = screenFrame.origin.x + (screenFrame.width - winW) / 2.0
        let winY = screenFrame.origin.y + (screenFrame.height - winH) / 2.0

        let rect = NSRect(x: winX, y: winY, width: winW, height: winH)
        let window = WallWindow(rect: rect)
        let canvas = ImageCanvasView(image: image, zoom: 1.0, filePath: portablePath)
        canvas.menu = NSMenu()
        window.contentView = canvas
        window.orderFront(nil)
        windows.append(window)

        rebuildMenu()
    }

    @objc func doSaveToVPC() {
        guard !configPath.isEmpty else { return }

        // Read existing VPC as raw JSON to preserve non-wallpaper keys
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              var vpcDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("Error: Could not read VPC file for saving")
            return
        }

        let entries = buildSnapshotEntries(windows: windows)

        // Update wallpapers.files
        if var wallpapers = vpcDict["wallpapers"] as? [String: Any] {
            wallpapers["files"] = entries
            vpcDict["wallpapers"] = wallpapers
        } else {
            vpcDict["wallpapers"] = ["files": entries]
        }

        guard let outData = try? JSONSerialization.data(
            withJSONObject: vpcDict,
            options: [.prettyPrinted, .sortedKeys]
        ) else {
            print("Error: Could not serialize VPC data")
            return
        }

        do {
            try outData.write(to: URL(fileURLWithPath: configPath))
            print("Saved to \(configPath)")
        } catch {
            print("Error: Could not write to \(configPath): \(error)")
        }
    }

    @objc func doQuit() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Per-Image Actions

    private func refreshCanvas(_ canvas: WallCanvas) {
        if let video = canvas as? VideoCanvasView { video.applyZoomAndPan() }
        (canvas as NSView).needsDisplay = true
    }

    @objc func doSetZoom(_ sender: NSMenuItem) {
        guard let (view, value) = sender.representedObject as? (NSView, Double),
              let canvas = view as? WallCanvas else { return }
        if let w = view.window as? WallWindow { imageUndoManager.saveState(for: w) }
        canvas.zoom = value
        refreshCanvas(canvas)
        rebuildMenu()
    }

    @objc func doZoomStep(_ sender: NSMenuItem) {
        guard let (view, delta) = sender.representedObject as? (NSView, Double),
              let canvas = view as? WallCanvas else { return }
        if let w = view.window as? WallWindow { imageUndoManager.saveState(for: w) }
        canvas.zoom = min(10.0, max(0.1, canvas.zoom + delta))
        refreshCanvas(canvas)
        rebuildMenu()
    }

    @objc func doSliderZoom(_ sender: NSSlider) {
        guard let view = objc_getAssociatedObject(sender, &kCanvasKey) as? NSView,
              let canvas = view as? WallCanvas else { return }
        canvas.zoom = sender.doubleValue
        refreshCanvas(canvas)
    }

    @objc func doResetPan(_ sender: NSMenuItem) {
        guard let view = sender.representedObject as? NSView,
              let canvas = view as? WallCanvas else { return }
        if let w = view.window as? WallWindow { imageUndoManager.saveState(for: w) }
        canvas.panOffset = .zero
        refreshCanvas(canvas)
    }

    @objc func doToggleLock(_ sender: NSMenuItem) {
        guard let view = sender.representedObject as? NSView,
              let wallWindow = view.window as? WallWindow else { return }
        wallWindow.isLocked = !wallWindow.isLocked
        rebuildMenu()
    }

    @objc func doSnapEdge(_ sender: NSMenuItem) {
        guard let view = sender.representedObject as? NSView,
              let window = view.window as? WallWindow,
              let screen = NSScreen.main else { return }
        imageUndoManager.saveState(for: window)

        let screenFrame = screen.frame
        let screenW = screenFrame.width
        let screenH = screenFrame.height
        let menuBarH: Double = 25
        let winW = window.frame.width
        let winH = window.frame.height

        let newFrame: NSRect
        switch sender.tag {
        case 0: // Top-Left
            newFrame = NSRect(x: 0, y: screenH - menuBarH - winH, width: winW, height: winH)
        case 1: // Top-Right
            newFrame = NSRect(x: screenW - winW, y: screenH - menuBarH - winH, width: winW, height: winH)
        case 2: // Bottom-Left
            newFrame = NSRect(x: 0, y: 0, width: winW, height: winH)
        case 3: // Bottom-Right
            newFrame = NSRect(x: screenW - winW, y: 0, width: winW, height: winH)
        case 4: // Fill Screen
            newFrame = NSRect(x: 0, y: 0, width: screenW, height: screenH - menuBarH)
        case 5: // Center
            newFrame = NSRect(x: (screenW - winW) / 2, y: (screenH - winH) / 2, width: winW, height: winH)
        default:
            return
        }

        window.setFrame(newFrame, display: true)
    }

    @objc func doSetSize(_ sender: NSMenuItem) {
        guard let (view, w, h) = sender.representedObject as? (NSView, Double, Double),
              let window = view.window as? WallWindow else { return }
        imageUndoManager.saveState(for: window)

        let oldFrame = window.frame
        let newY = oldFrame.origin.y + oldFrame.height - h
        let newFrame = NSRect(x: oldFrame.origin.x, y: newY, width: w, height: h)
        window.setFrame(newFrame, display: true)
    }

    @objc func doRemoveImage(_ sender: NSMenuItem) {
        guard let view = sender.representedObject as? NSView,
              let window = view.window as? WallWindow else { return }

        if let video = view as? VideoCanvasView {
            // Stop playback before removing
            _ = video
        }
        window.orderOut(nil)
        imageUndoManager.purge(window: window)
        windows.removeAll { $0 === window }
        rebuildMenu()
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
delegate.configPath = configPath
app.delegate = delegate
app.run()
