// LiveTranscribe.app — a lightweight native front-end for `live-transcribe`.
//
// The app SPAWNS the Python `live-transcribe` engine as a child and renders its
// piped output in a floating panel + menu-bar item. Spawning it (rather than
// letting Karabiner→fish do it) is deliberate: macOS attributes a microphone
// request to the *responsible process* — the app at the top of the launch
// chain. When this bundle (launched via LaunchServices `open`) is that process
// and declares NSMicrophoneUsageDescription, the grant is offered as
// "Live Transcribe" in System Settings and persists. The Karabiner helper that
// used to be the responsible process had no grantable mic entry, so capture
// silently failed.
//
// Lifecycle: app life == session life. When the engine exits (or you quit) we
// copy the transcript to the clipboard and close. We never leave an orphan
// engine: on shutdown we SIGINT the child, then SIGKILL if it lingers.
//
// Build: see Makefile (plain swiftc → .app bundle, codesigned).

import AppKit
import Foundation

// MARK: - Config / args

func argValue(_ name: String) -> String? {
    let a = CommandLine.arguments
    if let i = a.firstIndex(of: name), i + 1 < a.count { return a[i + 1] }
    return nil
}

let micDevice = argValue("--mic") ?? "BOYA"
let enginePath = "/Users/anthony/dotfiles/bin/live-transcribe"
let stateDir = ("~/.local/state/live-transcribe" as NSString).expandingTildeInPath
let logFilePath = stateDir + "/last.log"

// Transcripts + recordings land in the synced ProtonDrive folder so the
// `read <path>` reference is meaningful on other devices. Same physical dir as
// the engine's legacy ~/transcripts symlink.
let cloudTranscriptsDir = ("~/Cloud/transcripts" as NSString).expandingTildeInPath

// The engine shells out to `whisper-server` (and friends) by name, so the child
// needs a real PATH — LaunchServices gives us a minimal one.
func enrichedEnvironment() -> [String: String] {
    var env = ProcessInfo.processInfo.environment
    let extra = [
        NSHomeDirectory() + "/.local/bin",
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/Users/anthony/dotfiles/bin",
    ]
    let existing = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
    env["PATH"] = (extra + [existing]).joined(separator: ":")
    return env
}

// MARK: - Colors (terminal-ish dark theme)

enum Palette {
    static let background = NSColor(calibratedWhite: 0.10, alpha: 1.0)
    static let normal     = NSColor(calibratedWhite: 0.92, alpha: 1.0)
    static let dim        = NSColor(calibratedWhite: 0.50, alpha: 1.0)
    static let timestamp  = NSColor(calibratedWhite: 0.45, alpha: 1.0)
    static let micSource  = NSColor(calibratedRed: 0.40, green: 0.80, blue: 0.95, alpha: 1.0)
    static let compSource = NSColor(calibratedRed: 0.65, green: 0.85, blue: 0.45, alpha: 1.0)
    static let bannerBG   = NSColor(calibratedRed: 0.20, green: 0.62, blue: 0.30, alpha: 1.0)
    static let bannerFG   = NSColor.white
    static let errorFG    = NSColor(calibratedRed: 0.95, green: 0.45, blue: 0.40, alpha: 1.0)
}

let monoFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
let monoBold = NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold)

// MARK: - ANSI parsing + line styling

let ansiRegex = try! NSRegularExpression(pattern: "\u{1B}\\[[0-9;]*m")

func stripANSI(_ s: String) -> String {
    let r = NSRange(s.startIndex..., in: s)
    return ansiRegex.stringByReplacingMatches(in: s, range: r, withTemplate: "")
}

// [HH:MM:SS] text   — the "Source: " prefix is present only when >1 source is
// active. Anchored to the known source literals so an in-text colon (e.g.
// "Note: ...") in single-source output isn't mistaken for a source label.
let transcriptRegex = try! NSRegularExpression(pattern: "^\\[(\\d{2}:\\d{2}:\\d{2})\\] (?:(Microphone|Computer): )?(.*)$")

struct StyledLine {
    let attr: NSAttributedString
    let plain: String
    let isTranscript: Bool
}

func styleLine(_ raw: String) -> StyledLine {
    // Green banner — detected from the RAW escape before stripping.
    if raw.contains("\u{1B}[42m") {
        let text = stripANSI(raw).trimmingCharacters(in: .whitespaces)
        let a = NSMutableAttributedString(
            string: " " + text + " ",
            attributes: [
                .font: monoBold,
                .foregroundColor: Palette.bannerFG,
                .backgroundColor: Palette.bannerBG,
            ])
        return StyledLine(attr: a, plain: text, isTranscript: false)
    }

    let plain = stripANSI(raw)
    let range = NSRange(plain.startIndex..., in: plain)

    if let m = transcriptRegex.firstMatch(in: plain, range: range),
       let tsR = Range(m.range(at: 1), in: plain),
       let txtR = Range(m.range(at: 3), in: plain) {
        let ts = String(plain[tsR])
        let txt = String(plain[txtR])
        let a = NSMutableAttributedString()
        a.append(NSAttributedString(string: "[\(ts)] ", attributes: [.font: monoFont, .foregroundColor: Palette.timestamp]))
        // Source span only when the engine emitted one (multi-source sessions).
        if let srcR = Range(m.range(at: 2), in: plain) {
            let src = String(plain[srcR])
            let srcColor = src.lowercased().hasPrefix("comp") ? Palette.compSource : Palette.micSource
            a.append(NSAttributedString(string: "\(src): ", attributes: [.font: monoBold, .foregroundColor: srcColor]))
        }
        a.append(NSAttributedString(string: txt, attributes: [.font: monoFont, .foregroundColor: Palette.normal]))
        return StyledLine(attr: a, plain: plain, isTranscript: true)
    }

    let a = NSAttributedString(string: plain, attributes: [.font: monoFont, .foregroundColor: Palette.dim])
    return StyledLine(attr: a, plain: plain, isTranscript: false)
}

// MARK: - Copy mode

// How the transcript reaches the clipboard on stop. `.full` copies the whole
// transcript (default, Alt+Space); `.reference` copies a short `read <path>`
// line (Cmd+Alt+Space → live-transcribe-launch --ref → SIGUSR1) for when the
// transcript would overflow a chat message limit.
enum CopyMode { case full, reference }

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private var panel: NSPanel!
    private var textView: NSTextView!
    private var statusItem: NSStatusItem!

    private var engine: Process?
    private var enginePipe: Pipe?
    private var logHandle: FileHandle?
    private var lineBuffer = Data()   // touched only on the pipe's serial reader

    private var transcriptPath: String?
    private var accumulated: [String] = []
    private var terminating = false
    private var signalSources: [DispatchSourceSignal] = []
    private var copyMode: CopyMode = .full

    // Menu items whose actions need a known transcript path; disabled until then.
    private var copyTranscriptItem: NSMenuItem!
    private var copyRefItem: NSMenuItem!
    private var revealItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Single-instance: a second launch just reveals the first.
        if let bid = Bundle.main.bundleIdentifier {
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: bid)
                .filter { $0 != NSRunningApplication.current }
            if let other = others.first {
                other.activate(options: [])
                NSApp.terminate(nil)
                return
            }
        }

        buildPanel()
        buildStatusItem()
        installSignalHandlers()
        startEngine()

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    // MARK: UI

    private func buildPanel() {
        let w: CGFloat = 460, h: CGFloat = 520
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: w, height: h),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered, defer: false)
        panel.title = "Live Transcribe"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.backgroundColor = Palette.background

        let content = panel.contentView!
        let scroll = NSScrollView(frame: content.bounds)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = Palette.background

        let tv = NSTextView(frame: content.bounds)
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = true
        tv.backgroundColor = Palette.background
        tv.textContainerInset = NSSize(width: 8, height: 8)
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.containerSize = NSSize(width: content.bounds.width, height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = true
        scroll.documentView = tv
        content.addSubview(scroll)
        textView = tv

        // Remember the last position/size across launches. Once the autosave
        // name is set, AppKit persists the frame (keyed to the bundle id) on every
        // move/resize; setFrameUsingName returns false when nothing is saved yet.
        panel.setFrameAutosaveName("LiveTranscribePanel")
        let restored = panel.setFrameUsingName("LiveTranscribePanel")
        let onScreen = NSScreen.screens.contains { $0.frame.intersects(panel.frame) }
        if !restored || !onScreen {
            // Default: top-right of the main screen. Also the fallback when the
            // saved frame belonged to a display that's since been disconnected.
            if let screen = NSScreen.main {
                let vf = screen.visibleFrame
                panel.setFrame(NSRect(x: vf.maxX - w - 20, y: vf.maxY - h - 20, width: w, height: h), display: true)
            }
        }
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon(running: true)
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false   // enablement is managed in menuNeedsUpdate

        let toggle = NSMenuItem(title: "Hide Panel", action: #selector(togglePanel), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)

        menu.addItem(.separator())

        // Copy actions on the current session — grab the reference mid-session if
        // you know it'll be long, without waiting for stop.
        copyTranscriptItem = NSMenuItem(title: "Copy Transcript", action: #selector(copyTranscriptAction), keyEquivalent: "")
        copyTranscriptItem.target = self
        menu.addItem(copyTranscriptItem)

        copyRefItem = NSMenuItem(title: "Copy \u{201C}read <path>\u{201D} Reference", action: #selector(copyReferenceAction), keyEquivalent: "")
        copyRefItem.target = self
        menu.addItem(copyRefItem)

        revealItem = NSMenuItem(title: "Reveal Transcript in Finder", action: #selector(revealInFinder), keyEquivalent: "")
        revealItem.target = self
        menu.addItem(revealItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
    }

    private func updateIcon(running: Bool) {
        guard let button = statusItem?.button else { return }
        if #available(macOS 11.0, *) {
            let name = running ? "waveform" : "waveform.slash"
            button.image = NSImage(systemSymbolName: name, accessibilityDescription: "Live Transcribe")
        } else {
            button.title = running ? "●" : "○"
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.item(at: 0)?.title = panel.isVisible ? "Hide Panel" : "Show Panel"
        // The copy/reveal actions need a known transcript path (nil for ~1s at
        // startup until the engine emits "Writing transcript to:").
        let hasPath = (transcriptPath != nil)
        copyTranscriptItem?.isEnabled = hasPath
        copyRefItem?.isEnabled = hasPath
        revealItem?.isEnabled = hasPath
    }

    @objc private func copyTranscriptAction() { copyFullToPasteboard() }
    @objc private func copyReferenceAction() { copyReferenceToPasteboard() }

    @objc private func revealInFinder() {
        // Mid-session the .m4a doesn't exist yet (transcode happens at stop), so
        // reveal the .txt — it's flushed per line and always present.
        guard let p = transcriptPath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)])
    }

    @objc private func togglePanel() {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // Closing the panel only hides it; the menu-bar item keeps the session alive.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        panel.orderOut(nil)
        return false
    }

    // MARK: Engine

    private func startEngine() {
        // Fresh log for this session (also tee'd here for debugging).
        FileManager.default.createFile(atPath: logFilePath, contents: nil)
        logHandle = FileHandle(forWritingAtPath: logFilePath)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: enginePath)
        // --output-dir pins the canonical ~/Cloud path (so the reference string
        // resolves to ~/Cloud/... cross-device); --save-audio keeps the recording.
        p.arguments = ["--mic-device", micDevice, "--output-dir", cloudTranscriptsDir, "--save-audio"]
        p.environment = enrichedEnvironment()
        // LaunchServices gives the app CWD "/" (read-only). whisper-server writes
        // a relative temp WAV for ffmpeg, so the chain needs a writable CWD or
        // every conversion fails ("FFmpeg conversion failed" → empty transcript).
        p.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())

        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] fh in
            let data = fh.availableData
            guard !data.isEmpty else { return }
            self?.ingest(data)
        }
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.engineEnded() }
        }

        engine = p
        enginePipe = pipe
        do {
            try p.run()
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.appendError("Failed to launch engine: \(error.localizedDescription)")
            }
        }
    }

    // Called on the pipe's serial reader thread.
    private func ingest(_ data: Data) {
        logHandle?.write(data)
        lineBuffer.append(data)
        while let nl = lineBuffer.firstIndex(of: 0x0A) {
            let lineData = lineBuffer.subdata(in: lineBuffer.startIndex..<nl)
            lineBuffer.removeSubrange(lineBuffer.startIndex...nl)
            var line = String(decoding: lineData, as: UTF8.self)
            if line.hasSuffix("\r") { line.removeLast() }
            DispatchQueue.main.async { [weak self] in self?.handle(line) }
        }
    }

    private func handle(_ raw: String) {
        if transcriptPath == nil, let r = raw.range(of: "Writing transcript to: ") {
            transcriptPath = String(raw[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let styled = styleLine(raw)
        if styled.isTranscript { accumulated.append(styled.plain) }
        append(styled.attr)
    }

    private func appendError(_ msg: String) {
        append(NSAttributedString(string: msg, attributes: [.font: monoBold, .foregroundColor: Palette.errorFG]))
    }

    private func append(_ attr: NSAttributedString) {
        guard let storage = textView.textStorage else { return }
        let line = NSMutableAttributedString(attributedString: attr)
        line.append(NSAttributedString(string: "\n"))
        storage.append(line)
        textView.scrollToEndOfDocument(nil)
    }

    // MARK: Shutdown

    // The engine exited on its own (self-stop / crash). Wrap up and close.
    private func engineEnded() {
        enginePipe?.fileHandleForReading.readabilityHandler = nil
        updateIcon(running: false)
        if terminating { return }
        terminating = true
        copyTranscriptToClipboard()
        NSApp.terminate(nil)
    }

    private func installSignalHandlers() {
        // Full-copy terminators (Alt+Space → launcher SIGTERM; ⌃C).
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler { NSApp.terminate(nil) }
            src.resume()
            signalSources.append(src)
        }
        // SIGUSR1 = "stop and copy a `read <path>` reference instead of the full
        // text" (Cmd+Alt+Space → live-transcribe-launch --ref). SIGUSR1's default
        // disposition is *terminate*, so SIG_IGN MUST come first or the process
        // dies before the handler sets copyMode.
        signal(SIGUSR1, SIG_IGN)
        let refSrc = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        refSrc.setEventHandler { [weak self] in
            self?.copyMode = .reference
            NSApp.terminate(nil)
        }
        refSrc.resume()
        signalSources.append(refSrc)
    }

    // Runs for every quit route (menu, SIGTERM from the launcher, engine exit).
    // Guarantees the child dies — no orphan engine — and the transcript is copied.
    func applicationWillTerminate(_ notification: Notification) {
        terminating = true
        enginePipe?.fileHandleForReading.readabilityHandler = nil
        if let p = engine, p.isRunning {
            kill(p.processIdentifier, SIGINT)
            // The engine finalizes the audio early (before its transcript-queue
            // drain), so the .m4a is safe well within this window. The headroom
            // (was 2s) lets the network-bound transcript drain finish on longer
            // sessions instead of losing the tail to SIGKILL.
            let deadline = Date().addingTimeInterval(10.0)
            while p.isRunning && Date() < deadline { usleep(100_000) }
            if p.isRunning { kill(p.processIdentifier, SIGKILL) }
        }
        copyTranscriptToClipboard()
    }

    // Called on every stop route. Reference mode requires a known path; if the
    // engine died before emitting one, fall through to a full copy rather than
    // clobbering the clipboard with a bare "read ".
    private func copyTranscriptToClipboard() {
        if copyMode == .reference, transcriptPath != nil {
            copyReferenceToPasteboard()
        } else {
            copyFullToPasteboard()
        }
    }

    private func copyFullToPasteboard() {
        var text: String?
        if let p = transcriptPath, let s = try? String(contentsOfFile: p, encoding: .utf8),
           !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text = s
        }
        if text == nil, !accumulated.isEmpty {
            text = accumulated.joined(separator: "\n") + "\n"
        }
        guard let out = text, !out.isEmpty else { return }   // never clobber with empty
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(out, forType: .string)
    }

    // Short cross-device reference for when the full transcript overflows a chat
    // limit — ~/Cloud/... resolves on other devices since the folder syncs.
    private func copyReferenceToPasteboard() {
        guard let p = transcriptPath else { return }
        let ref = "read " + (p as NSString).abbreviatingWithTildeInPath
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(ref, forType: .string)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        togglePanel()
        return true
    }
}

// MARK: - Entry point

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
