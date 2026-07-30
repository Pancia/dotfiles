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
import CoreGraphics   // CGEvent + CGPreflight/RequestPostEventAccess (auto-linked via AppKit)
import Carbon.HIToolbox   // RegisterEventHotKey — the global Escape grab (see registerEscapeHotKey)
import Foundation

// MARK: - Config / args

func argValue(_ name: String) -> String? {
    let a = CommandLine.arguments
    if let i = a.firstIndex(of: name), i + 1 < a.count { return a[i + 1] }
    return nil
}

let micDevice = argValue("--mic") ?? "BOYA"

// Which hotkey drives this session. The mode — not a persisted preference — is the
// authority on the two output settings, so each key means exactly one thing:
//   plain (Alt+Space)      -> no timestamps, full transcript
//   ref   (Cmd+Alt+Space)  -> timestamps, `read <path>` reference
// It's seeded at launch (so the panel renders right from the first line) and
// re-asserted by the stop signal, so a session started with one key and stopped with
// the other still obeys the key that stopped it.
enum OutputMode {
    case plain, reference
    var wantsTimestamps: Bool { self == .reference }
    var wantsReference: Bool { self == .reference }
}

let launchMode: OutputMode? = argValue("--mode").flatMap {
    switch $0 {
    case "plain": return OutputMode.plain
    case "ref":   return OutputMode.reference
    default:      return nil
    }
}

// The Brave PWA for Telegram Web (~/Applications/Brave Browser Apps.localized/Telegram Web.app).
// Telegram caps a single message at 4096 UTF-16 units, so an auto-paste aimed here
// degrades to the reference rather than dropping text the far end will reject.
let telegramBundleID = "com.brave.Browser.app.ibblmnobmgdmpoeblocemifbpglakpoi"

// Telegram's real cap is 4096 UTF-16 units. Overridable at runtime solely so the
// overflow path can be exercised with a 5-second recording instead of ~5 minutes of
// talking — the genuine limit would otherwise be untestable by hand:
//   defaults write org.pancia.live-transcribe-app debug.telegramLimit 20
//   defaults delete org.pancia.live-transcribe-app debug.telegramLimit
// Non-positive or absent (integer(forKey:) returns 0 for both) falls back to the real cap.
func telegramMessageLimit() -> Int {
    let n = UserDefaults.standard.integer(forKey: "debug.telegramLimit")
    return n > 0 ? n : 4096
}

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
    static let amber      = NSColor(calibratedRed: 0.95, green: 0.75, blue: 0.30, alpha: 1.0)
    static let separator  = NSColor(calibratedWhite: 0.22, alpha: 1.0)
}

let monoFont = NSFont.monospacedSystemFont(ofSize: 22, weight: .regular)
let monoBold = NSFont.monospacedSystemFont(ofSize: 22, weight: .semibold)
let statusFont = NSFont.monospacedSystemFont(ofSize: 16, weight: .regular)
let statusFontBold = NSFont.monospacedSystemFont(ofSize: 16, weight: .semibold)

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

// [mic] [####----] peak=0.045 avg=0.012  <state>  chunks_sent=3  — the periodic
// signal meter (bin/live-transcribe _meter_loop). Captured: bar fill, state, count.
let meterRegex = try! NSRegularExpression(pattern: "^\\[mic\\] \\[([#-]*)\\] peak=[0-9.]+ avg=[0-9.]+\\s+(.+?)\\s+chunks_sent=(\\d+)$")

// Collapses a timestamped transcript into flowing prose — what the Timestamps
// checkbox produces when it's off. The `[HH:MM:SS] ` prefix is dropped and
// consecutive lines from the same source are joined with a space; a source change
// starts a new line (re-printing the `Microphone: `/`Computer: ` label) so speech
// stays attributed. Lines that aren't transcript output (headers, blanks) pass
// through untouched on their own line and break the run, which also makes this
// safe to run on both the file and the in-memory `accumulated` fallback.
func flowTranscript(_ text: String) -> String {
    var out: [String] = []
    var runSource: String?
    var runOpen = false
    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
        let s = String(line)
        let r = NSRange(s.startIndex..., in: s)
        guard let m = transcriptRegex.firstMatch(in: s, range: r),
              let txtR = Range(m.range(at: 3), in: s) else {
            // Older archives contain multi-segment entries whose 2nd+ lines carry no
            // timestamp (whisper joined segments with newlines; the engine now folds
            // those, see bin/live-transcribe). Fold them into the open paragraph rather
            // than stranding them unattributed. With no run open — an already-flowed
            // file, a header — the line stands alone and does NOT open a run, which is
            // what keeps re-flowing a flowed file a no-op.
            let cont = String(s.drop(while: { $0 == " " || $0 == "\t" }))
            if runOpen, !cont.isEmpty, var last = out.popLast() {
                if !last.isEmpty && !last.hasSuffix(" ") { last += " " }
                out.append(last + cont)
            } else {
                out.append(s)
                runOpen = false
            }
            continue
        }
        let src = Range(m.range(at: 2), in: s).map { String(s[$0]) }
        let txt = String(s[txtR])
        if runOpen, src == runSource, var last = out.popLast() {
            if !last.isEmpty && !last.hasSuffix(" ") && !txt.isEmpty { last += " " }
            out.append(last + txt)
        } else {
            out.append(src.map { "\($0): \(txt)" } ?? txt)
            runSource = src
            runOpen = true
        }
    }
    return out.joined(separator: "\n")
}

struct StyledLine {
    let attr: NSAttributedString
    let plain: String
    let isTranscript: Bool
    let source: String?   // "Microphone"/"Computer" when the engine labeled the line
}

// `continuing` = this line is being joined onto the previous one as flowing prose
// (Timestamps off), so its source label would be a redundant mid-sentence repeat.
func styleLine(_ raw: String, showTimestamps: Bool, continuing: Bool = false) -> StyledLine {
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
        return StyledLine(attr: a, plain: text, isTranscript: false, source: nil)
    }

    let plain = stripANSI(raw)
    let range = NSRange(plain.startIndex..., in: plain)

    if let m = transcriptRegex.firstMatch(in: plain, range: range),
       let tsR = Range(m.range(at: 1), in: plain),
       let txtR = Range(m.range(at: 3), in: plain) {
        let ts = String(plain[tsR])
        let txt = String(plain[txtR])
        let a = NSMutableAttributedString()
        // The [HH:MM:SS] span is display-only and suppressed when the Timestamps
        // checkbox is off. `plain` keeps the timestamp so `accumulated` stays canonical.
        if showTimestamps {
            a.append(NSAttributedString(string: "[\(ts)] ", attributes: [.font: monoFont, .foregroundColor: Palette.timestamp]))
        }
        // Source span only when the engine emitted one (multi-source sessions), and
        // only at the head of a flowed paragraph.
        let src = Range(m.range(at: 2), in: plain).map { String(plain[$0]) }
        if let src, !continuing {
            let srcColor = src.lowercased().hasPrefix("comp") ? Palette.compSource : Palette.micSource
            a.append(NSAttributedString(string: "\(src): ", attributes: [.font: monoBold, .foregroundColor: srcColor]))
        }
        a.append(NSAttributedString(string: txt, attributes: [.font: monoFont, .foregroundColor: Palette.normal]))
        return StyledLine(attr: a, plain: plain, isTranscript: true, source: src)
    }

    let a = NSAttributedString(string: plain, attributes: [.font: monoFont, .foregroundColor: Palette.dim])
    return StyledLine(attr: a, plain: plain, isTranscript: false, source: nil)
}

// MARK: - Panel

// The transcript panel, which must NEVER take keyboard focus: it floats over whatever
// you're dictating into, and a keystroke landing here instead of there is the bug this
// window is designed around.
//
// `becomesKeyOnlyIfNeeded` alone does NOT get you that. It's a conditional — AppKit asks
// the clicked view's `needsPanelToBecomeKey`, and NSTextView answers true whenever it is
// *selectable*, not merely when it's editable (measured: selectable=true → true,
// selectable=false → false, NSButton → false). So buttons and checkboxes were safe but
// drag-selecting transcript text would quietly make the panel key — the exact gesture
// this was meant to protect, and a worse version of the original bug, since the app you
// were typing into keeps its solid caret and gives no sign the keys stopped arriving.
//
// Overriding canBecomeKey is the guarantee. Clicks, buttons, the close button, window
// dragging and text selection all still work (selection just draws in the inactive
// colour); ⌘C on a selection does not, since a never-key app receives no key
// equivalents — the status menu's "Copy Transcript" is the route for that.
final class NonKeyPanel: NSPanel {
    override var canBecomeKey: Bool { false }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private var panel: NSPanel!
    private var textView: NSTextView!
    private var statusField: NSTextField!   // bottom footer: live mic meter
    private var statusItem: NSStatusItem!

    private var engine: Process?
    private var enginePipe: Pipe?
    private var logHandle: FileHandle?
    private var lineBuffer = Data()   // touched only on the pipe's serial reader

    private var transcriptPath: String?
    private var accumulated: [String] = []
    // Every raw line that reached the transcript scroll (meter lines excluded), in
    // order — replayed by rerenderTranscript() when the Timestamps checkbox toggles.
    private var displayedRawLines: [String] = []
    private var signalSources: [DispatchSourceSignal] = []
    // Global bare-Escape grab; released at the top of finish(). See registerEscapeHotKey.
    private var escapeHotKey: EventHotKeyRef?
    private var escapeEventHandler: EventHandlerRef?

    // Stop/copy state (was `enum CopyMode`). `cancelled` = Escape/Cancel → no copy;
    // `overflowReference` = this paste target can't take the full text (see
    // applyPasteTargetOverride) → send the reference instead. `pasteEligible` = an
    // explicit user stop (Complete/Alt+Space/Cmd+Alt+Space) — the only routes allowed
    // to auto-paste.
    private var cancelled = false
    private var overflowReference = false
    private var pasteEligible = false
    private var finishing = false          // guards the shutdown funnel (first caller wins)
    // True once the transcript has been placed on the clipboard this session. Guards the
    // applicationWillTerminate safety net so it copies exactly once — including the race
    // where a hard terminate (logout/Force-Quit) fires DURING finish()'s off-main drain,
    // before afterEngineStopped() got to copy (there `finishing` is already true).
    private var clipboardWritten = false

    // Session output settings — owned by the launch/stop mode, not UserDefaults (the
    // checkboxes stay live overrides for the session). `showTimestamps` is also the
    // hot-path render flag, read once per line.
    private var showTimestamps = true
    private var copyAsReference = false
    // Set when the user hand-toggles a checkbox mid-session. Their choice then outranks
    // the stop hotkey's mode, which would otherwise silently discard it.
    private var tsTouched = false
    private var refTouched = false
    // Display-only filter for the engine's startup chatter. A real preference (it has
    // nothing to do with the hotkey mode), so it persists.
    private var showDebug = false
    // Flow state for the scroll when Timestamps is off: what the last appended line
    // was, so a transcript line continuing the same source joins it with a space
    // instead of starting a new one. Any other line ends the paragraph.
    private var lastLineWasTranscript = false
    private var lastLineSource: String?
    // The app to reactivate + paste into on an auto-paste stop. Seeded at launch,
    // kept current by the didActivateApplication observer.
    private var targetApp: NSRunningApplication?

    // In-window controls.
    private var tsCheck: NSButton!
    private var refCheck: NSButton!
    private var pasteCheck: NSButton!
    private var debugCheck: NSButton!
    private var completeButton: NSButton!
    private var cancelButton: NSButton!

    // Menu items whose actions need a known transcript path; disabled until then.
    private var cancelItem: NSMenuItem!
    private var copyTranscriptItem: NSMenuItem!
    private var copyRefItem: NSMenuItem!
    private var revealItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Non-persisted fallback layer. Only pref.autoPaste is still read/written as a
        // real preference; the other two are seeded by --mode on every hotkey launch and
        // matter solely when the .app is opened directly with no mode.
        UserDefaults.standard.register(defaults: [
            "pref.timestamps": true,
            "pref.copyAsReference": false,
            "pref.autoPaste": false,
            "pref.showDebug": false,
        ])

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

        // Track the app to paste into on an auto-paste stop. Subscribe FIRST (on the
        // WORKSPACE center — the default NotificationCenter never gets this), then seed
        // from the current frontmost (self-filtered). We no longer activate at all, so the
        // seed can't be polluted by our own activation the way it once could.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
        if let seed = NSWorkspace.shared.frontmostApplication, seed != .current {
            targetApp = seed
        }

        buildPanel()
        buildStatusItem()
        installSignalHandlers()
        startEngine()

        // Show WITHOUT taking focus. We used to NSApp.activate + makeKeyAndOrderFront,
        // which made us the active app: the window you were dictating into lost key
        // status and its caret went hollow, while the menu bar kept naming that app
        // (.accessory apps never take the menu bar). A confusing split state — and a real
        // hazard, since a key panel meant Return = Complete and Escape = Cancel could
        // swallow keystrokes aimed at the terminal.
        //
        // orderFrontRegardless() + .nonactivatingPanel, over a panel whose canBecomeKey is
        // false (see NonKeyPanel), means it cannot capture a keystroke even after you click
        // it. Escape-to-cancel survives as a real global hotkey instead — see
        // registerEscapeHotKey.
        panel.orderFrontRegardless()
        registerEscapeHotKey()
    }

    // MARK: Global Escape

    // Escape cancels the session from anywhere. The panel can no longer receive it (it
    // never becomes key), so we grab the key itself.
    //
    // Carbon's RegisterEventHotKey rather than the alternatives, deliberately:
    //   - It needs no TCC grant. A CGEventTap or an NSEvent global monitor both want
    //     Accessibility, which this bundle doesn't hold on a clean machine and which a
    //     background .accessory app can't prompt for cleanly.
    //   - Its lifetime is exactly this process's: the system drops the registration when
    //     we die, so a crash cannot leave Escape swallowed system-wide. Every
    //     external-state design (a Karabiner variable, a tap someone else owns) has a
    //     stale-state failure whose symptom is "my Escape key stopped working".
    //   - It sees the REMAPPED Escape. This machine's Escape is Caps Lock →
    //     right_control → to_if_alone escape, i.e. produced BY a Karabiner complex
    //     modification. Karabiner posts that through its virtual keyboard upstream of
    //     hotkey dispatch, so we get it — confirmed by hand on this machine, and the
    //     load-bearing assumption of this whole approach. A Karabiner rule matching on
    //     `escape` would NOT have seen it: complex modifications are a single pass, so
    //     one rule's output is never re-fed into another
    //     (pqrs-org/Karabiner-Elements#2742).
    //
    // The cost, accepted knowingly: while a session runs, Escape is consumed everywhere,
    // so it won't leave vim's insert mode or dismiss a dialog in the app you're dictating
    // into. Released at the top of finish(), so the grab ends with the recording rather
    // than lingering through the ~10s engine drain that follows it.
    private static let hotKeySignature: OSType = 0x4C54_4358   // 'LTCX'

    private func registerEscapeHotKey() {
        // Idempotent. A second call would leak the first handler (unremovable, and it
        // would double-fire) and then overwrite escapeHotKey with the nil that
        // eventHotKeyExistsErr leaves behind — stranding the live grab with no way to
        // release it, i.e. Escape dead for the rest of the process.
        guard escapeHotKey == nil, escapeEventHandler == nil else { return }

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let err = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                        EventParamType(typeEventHotKeyID), nil,
                                        MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard err == noErr, id.signature == AppDelegate.hotKeySignature else {
                return OSStatus(eventNotHandledErr)
            }
            // Hop to main rather than tearing down UI and the engine on the Carbon
            // callback's own frame.
            let me = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { me.cancelSession() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &escapeEventHandler)

        // Order matters, and so does bailing out here. Registering the hotkey with no
        // handler installed is the worst reachable state: bare Escape is grabbed
        // system-wide for the whole session with nothing listening, so it neither cancels
        // nor reaches the app you're typing into.
        guard installed == noErr else {
            escapeEventHandler = nil
            appendError("⚠︎ Escape-to-cancel unavailable (InstallEventHandler \(installed)) — use the menu bar item.")
            return
        }

        // modifiers: 0 — bare Escape. Unusual for a hotkey, and the reason releasing it
        // promptly at stop matters.
        let registered = RegisterEventHotKey(UInt32(kVK_Escape), 0,
                                             EventHotKeyID(signature: AppDelegate.hotKeySignature, id: 1),
                                             GetApplicationEventTarget(), 0, &escapeHotKey)
        if registered != noErr {
            escapeHotKey = nil
            appendError("⚠︎ Escape-to-cancel unavailable (RegisterEventHotKey \(registered)) — use the menu bar item.")
        }
    }

    private func unregisterEscapeHotKey() {
        if let k = escapeHotKey { UnregisterEventHotKey(k); escapeHotKey = nil }
        if let h = escapeEventHandler { RemoveEventHandler(h); escapeEventHandler = nil }
    }

    // Keep `targetApp` on the latest non-self foreground app so auto-paste follows
    // the user if they switch apps mid-session. Ignore our own activations.
    @objc private func appActivated(_ note: Notification) {
        if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
           app != .current {
            targetApp = app
        }
    }

    // MARK: UI

    private func buildPanel() {
        let w: CGFloat = 660, h: CGFloat = 740
        // NonKeyPanel, not NSPanel: canBecomeKey is overridden to false, which is what
        // actually keeps the keyboard with the app you're dictating into. See the type.
        panel = NonKeyPanel(
            contentRect: NSRect(x: 0, y: 0, width: w, height: h),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.title = "Live Transcribe"
        panel.level = .floating
        panel.isFloatingPanel = true
        // Redundant next to the canBecomeKey override, kept as a second line of defence:
        // it also stops AppKit even *asking* for key on a button or checkbox click.
        panel.becomesKeyOnlyIfNeeded = true
        // Load-bearing: .utilityWindow defaults this to true, and we are essentially never
        // the active app any more, so leaving it would hide the panel for the whole session.
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.backgroundColor = Palette.background
        // Pin to dark so checkbox labels/checkmarks/scroller render light-on-dark
        // against the near-black background even when the system is in Light mode.
        panel.appearance = NSAppearance(named: .darkAqua)

        let content = panel.contentView!
        let barH: CGFloat = 38   // mic-meter footer strip at the bottom
        let topH: CGFloat = 40   // control bar (checkboxes + buttons) at the top
        panel.contentMinSize = NSSize(width: 520, height: topH + barH + 200)

        // Middle: transcript scroll, inset by the top control bar AND the bottom footer.
        let scroll = NSScrollView(frame: NSRect(x: 0, y: barH, width: content.bounds.width, height: content.bounds.height - barH - topH))
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

        // Status footer: the periodic mic meter is routed here (updateStatus)
        // and updates in place, instead of scrolling with the transcript.
        let sep = NSView(frame: NSRect(x: 0, y: barH - 1, width: content.bounds.width, height: 1))
        sep.wantsLayer = true
        sep.layer?.backgroundColor = Palette.separator.cgColor
        sep.autoresizingMask = [.width, .maxYMargin]
        content.addSubview(sep)

        // The Debug toggle rides at the right end of this bar rather than in the top
        // control row: at the default 586pt window that row is already full, and a
        // fourth checkbox there would clip Cancel/Complete.
        let dbgW: CGFloat = 86
        let sfH: CGFloat = 24
        let sf = NSTextField(frame: NSRect(x: 8, y: (barH - sfH) / 2, width: content.bounds.width - 16 - dbgW, height: sfH))
        sf.isEditable = false
        sf.isSelectable = false
        sf.isBordered = false
        sf.drawsBackground = false
        sf.font = statusFont
        sf.textColor = Palette.dim   // covers the initial text + any parse-miss fallback
        sf.usesSingleLineMode = true
        sf.lineBreakMode = .byTruncatingTail
        sf.stringValue = "🎙 waiting for audio…"
        sf.autoresizingMask = [.width, .maxYMargin]
        content.addSubview(sf)
        statusField = sf

        // Pinned to the right edge (minXMargin), so the status field keeps all the
        // slack as the window widens.
        showDebug = UserDefaults.standard.bool(forKey: "pref.showDebug")
        let dbgH: CGFloat = 20
        let dbg = NSButton(checkboxWithTitle: "Debug", target: self, action: #selector(toggleDebug(_:)))
        dbg.font = NSFont.systemFont(ofSize: 12)
        dbg.state = showDebug ? .on : .off
        dbg.frame = NSRect(x: content.bounds.width - dbgW - 6, y: (barH - dbgH) / 2, width: dbgW, height: dbgH)
        dbg.autoresizingMask = [.minXMargin, .maxYMargin]
        content.addSubview(dbg)
        debugCheck = dbg

        // Top control bar: 3 checkboxes (left) + Cancel/Complete (right).
        buildControlBar(in: content, topH: topH)

        // Remember the last position/size across launches. Once the autosave
        // name is set, AppKit persists the frame (keyed to the bundle id) on every
        // move/resize; setFrameUsingName returns false when nothing is saved yet.
        // V2: the old key's saved ~460×520 frame is unusable at 22pt + a top bar, so
        // bump the key to reset everyone to the new default once (then re-persist).
        panel.setFrameAutosaveName("LiveTranscribePanelV2")
        let restored = panel.setFrameUsingName("LiveTranscribePanelV2")
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

    // Top strip: 3 checkboxes left, Cancel/Complete right. A programmatic NSStackView
    // keeps translatesAutoresizingMask=true, so positioning it by frame + mask is legal
    // while it lays out its ARRANGED subviews via constraints.
    private func buildControlBar(in content: NSView, topH: CGFloat) {
        let bar = NSStackView(frame: NSRect(x: 0, y: content.bounds.height - topH,
                                            width: content.bounds.width, height: topH))
        bar.autoresizingMask = [.width, .minYMargin]   // pinned to top, fixed height
        bar.orientation = .horizontal
        bar.alignment = .centerY
        bar.distribution = .gravityAreas               // leading pinned left, trailing right
        bar.spacing = 10
        bar.edgeInsets = NSEdgeInsets(top: 4, left: 12, bottom: 4, right: 12)

        func check(_ title: String, _ on: Bool, _ action: Selector) -> NSButton {
            let b = NSButton(checkboxWithTitle: title, target: self, action: action)
            b.font = NSFont.systemFont(ofSize: 13)     // NOT tiny .small next to 22pt transcript
            b.state = on ? .on : .off
            return b
        }
        // The hotkey's mode wins; the registered defaults only cover a bare launch with
        // no --mode (opening the .app straight from Finder).
        let d = UserDefaults.standard
        showTimestamps  = launchMode?.wantsTimestamps ?? d.bool(forKey: "pref.timestamps")
        copyAsReference = launchMode?.wantsReference  ?? d.bool(forKey: "pref.copyAsReference")
        tsCheck    = check("Timestamps",             showTimestamps,                  #selector(toggleTimestamps(_:)))
        refCheck   = check("Copy as file reference", copyAsReference,                 #selector(togglePrefRef(_:)))
        pasteCheck = check("Auto-paste (⌘V)",        d.bool(forKey: "pref.autoPaste"), #selector(togglePrefPaste(_:)))

        completeButton = NSButton(title: "Complete", target: self, action: #selector(completeAction))
        completeButton.bezelStyle = .rounded
        // No keyEquivalent = "\r". Removing it — not the focus change — is what actually
        // kills the Return-ends-your-session hazard, and Alt+Space already completes from
        // anywhere. It also cost the default button's accent fill, so restore the primary/
        // secondary hierarchy by hand (a default button only draws accented while its
        // window is key, which this one never is, so nothing is lost by doing it here).
        if #available(macOS 10.14, *) { completeButton.bezelColor = .controlAccentColor }
        cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelSession))
        cancelButton.bezelStyle = .rounded

        bar.addView(tsCheck, in: .leading)
        bar.addView(refCheck, in: .leading)
        bar.addView(pasteCheck, in: .leading)
        bar.addView(cancelButton, in: .trailing)
        bar.addView(completeButton, in: .trailing)     // Complete rightmost
        content.addSubview(bar)

        // Separator under the bar, mirroring the bottom footer's.
        let topSep = NSView(frame: NSRect(x: 0, y: content.bounds.height - topH, width: content.bounds.width, height: 1))
        topSep.wantsLayer = true
        topSep.layer?.backgroundColor = Palette.separator.cgColor
        topSep.autoresizingMask = [.width, .minYMargin]
        content.addSubview(topSep)
    }

    private func setControlsEnabled(_ on: Bool) {
        [tsCheck, refCheck, pasteCheck, debugCheck, completeButton, cancelButton].forEach { $0?.isEnabled = on }
    }

    // Neither of these persists any more: the launch mode reseeds them every session, so
    // a stored value could only ever be stale. They are session overrides, and the
    // `touched` flag is what protects them from the stop hotkey re-asserting its mode.
    @objc private func toggleTimestamps(_ s: NSButton) {
        showTimestamps = (s.state == .on)
        tsTouched = true
        rerenderTranscript()
    }

    @objc private func togglePrefRef(_ s: NSButton) {
        copyAsReference = (s.state == .on)
        refTouched = true
    }

    @objc private func toggleDebug(_ s: NSButton) {
        showDebug = (s.state == .on)
        UserDefaults.standard.set(showDebug, forKey: "pref.showDebug")
        rerenderTranscript()
    }

    @objc private func togglePrefPaste(_ s: NSButton) {
        let on = (s.state == .on)
        UserDefaults.standard.set(on, forKey: "pref.autoPaste")
        // Prompt for Accessibility now (app is active). The grant lands async and
        // usually needs a relaunch, so triggering it here beats prompting mid-stop.
        if on, !CGPreflightPostEventAccess() { _ = CGRequestPostEventAccess() }
    }

    @objc private func completeAction() { finish(cancelled: false, userInitiated: true) }

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

        // Cancel needs a home outside the panel: Quit below stops and COPIES, so without
        // this the menu had no way to end a session without touching the clipboard. Also
        // the fallback if the global Escape hotkey is ever unavailable.
        cancelItem = NSMenuItem(title: "Cancel Session (no copy)", action: #selector(cancelSession), keyEquivalent: "")
        cancelItem.target = self
        menu.addItem(cancelItem)

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
        // Cancel is meaningless once we're already stopping (finish() is guarded), so grey
        // it out rather than leave a visible no-op.
        cancelItem?.isEnabled = !finishing
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
            // Same no-focus-theft rule as launch — never activate, never take key.
            panel.orderFrontRegardless()
        }
    }

    @objc private func quit() { finish(cancelled: false, userInitiated: false) }

    // Closing the window — the red button; Escape now arrives via the global hotkey and
    // calls cancelSession() directly, never through here — cancels
    // the session: stop recording, keep the saved .txt/.m4a, but don't copy
    // anything to the clipboard. (Use the menu's "Hide Panel" to hide while
    // recording continues.)
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        cancelSession()
        return false
    }

    @objc private func cancelSession() { finish(cancelled: true, userInitiated: false) }

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
        lineBuffer.append(data)
        while let nl = lineBuffer.firstIndex(of: 0x0A) {
            let lineData = lineBuffer.subdata(in: lineBuffer.startIndex..<nl)
            lineBuffer.removeSubrange(lineBuffer.startIndex...nl)
            var line = String(decoding: lineData, as: UTF8.self)
            if line.hasSuffix("\r") { line.removeLast() }
            // Tee to last.log per LINE rather than per chunk, so the meter can be left
            // out: at 10 Hz it was ~90% of the file, burying the startup/error lines you
            // actually open the log to read. Nothing is lost — the footer renders it live
            // and it's pure instantaneous state, worthless after the fact.
            // Tradeoff of per-line: a trailing unterminated fragment is no longer logged.
            // That needs the engine to be SIGKILLed mid-write, since it only ever prints
            // whole lines.
            if !stripANSI(line).hasPrefix("[mic] [") {
                logHandle?.write(Data((line + "\n").utf8))
            }
            DispatchQueue.main.async { [weak self] in self?.handle(line) }
        }
    }

    private func handle(_ raw: String) {
        // Route the periodic mic meter to the status footer instead of the scroll.
        // (Warnings "[mic] ⚠ …" don't start with "[mic] [", so they fall through
        // and persist in the transcript scroll.)
        let plain = stripANSI(raw)
        if plain.hasPrefix("[mic] [") {
            updateStatus(plain)
            return
        }
        if transcriptPath == nil, let r = raw.range(of: "Writing transcript to: ") {
            transcriptPath = String(raw[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        displayedRawLines.append(raw)   // replayed by rerenderTranscript() on a Timestamps toggle
        let styled = styleLine(raw, showTimestamps: showTimestamps)
        if styled.isTranscript { accumulated.append(styled.plain) }
        guard let storage = textView.textStorage else { return }
        appendStyled(styled, raw: raw, to: storage)
        textView.scrollToEndOfDocument(nil)
    }

    // Render the periodic mic meter into the bottom footer (color-coded bar +
    // state), replacing the previous value. Parse-miss → show the line verbatim
    // (dim, via the cell's textColor set in buildPanel).
    private func updateStatus(_ plain: String) {
        let range = NSRange(plain.startIndex..., in: plain)
        guard let m = meterRegex.firstMatch(in: plain, range: range),
              let fillR = Range(m.range(at: 1), in: plain),
              let stateR = Range(m.range(at: 2), in: plain),
              let chunkR = Range(m.range(at: 3), in: plain) else {
            statusField.stringValue = plain
            return
        }
        let cells = plain[fillR].map { $0 == "#" ? Character("█") : Character("░") }
        let bar = "▐" + String(cells) + "▌"
        let stateText = String(plain[stateR])
        let chunks = String(plain[chunkR])

        // Check "sound" before "speech": the state "sound, no speech" contains
        // the substring "speech", so a speech-first test would misclassify it.
        let word: String
        let color: NSColor
        if stateText.contains("SILENT") {
            word = "silent"; color = Palette.dim
        } else if stateText.contains("sound") {
            word = "sound"; color = Palette.amber
        } else {
            word = "speech"; color = Palette.compSource
        }

        let s = NSMutableAttributedString()
        s.append(NSAttributedString(string: "🎙 ", attributes: [.font: statusFont]))
        s.append(NSAttributedString(string: bar, attributes: [.font: statusFont, .foregroundColor: color]))
        s.append(NSAttributedString(string: "  \(word)", attributes: [.font: statusFontBold, .foregroundColor: color]))
        s.append(NSAttributedString(string: "  · sent \(chunks)", attributes: [.font: statusFont, .foregroundColor: Palette.dim]))
        statusField.attributedStringValue = s
    }

    private func appendError(_ msg: String) {
        append(NSAttributedString(string: msg, attributes: [.font: monoBold, .foregroundColor: Palette.errorFG]))
    }

    // Non-transcript output (errors, notices) always gets its own line and ends any
    // paragraph in progress.
    private func append(_ attr: NSAttributedString) {
        guard let storage = textView.textStorage else { return }
        if storage.length > 0 { storage.append(NSAttributedString(string: "\n", attributes: [.font: monoFont])) }
        storage.append(attr)
        lastLineWasTranscript = false
        lastLineSource = nil
        textView.scrollToEndOfDocument(nil)
    }

    // Appends one styled line, choosing the separator that PRECEDES it: with
    // Timestamps off, a transcript line continuing the same source is joined onto the
    // previous one with a space (and re-rendered without its now-redundant source
    // label); everything else starts a new line.
    // What the Debug checkbox hides: the engine's startup chatter (device probe, ports,
    // output paths, "Press Ctrl+C to stop"). Deliberately NOT hidden — transcript text,
    // the green "Recording started" banner, and anything reading like a real failure, so
    // a display filter can never swallow the reason a session produced nothing.
    //
    // "[mic] ⚠ no signal for ~9s …" IS hidden: the footer meter already reports exactly
    // that condition as "silent · sent 0", live and in place, so the scrolled copy is
    // pure duplication. (Plain "[mic] [" meter lines never reach here — handle() routes
    // them to the footer before this point.)
    private func isDebugChatter(_ styled: StyledLine, raw: String) -> Bool {
        if styled.isTranscript { return false }
        if raw.contains("\u{1B}[42m") { return false }
        let s = styled.plain.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return true }
        if s.hasPrefix("[mic]") { return true }
        let lower = s.lowercased()
        for token in ["error", "traceback", "exception", "failed", "fatal"] where lower.contains(token) {
            return false
        }
        return true
    }

    private func appendStyled(_ styled: StyledLine, raw: String, to storage: NSTextStorage) {
        // Skipping without touching the flow state is intentional: a hidden line between
        // two transcript lines lets them join as one paragraph, which is what you'd want
        // if it had never been printed.
        if !showDebug, isDebugChatter(styled, raw: raw) { return }
        let joins = !showTimestamps && styled.isTranscript
            && lastLineWasTranscript && styled.source == lastLineSource
        if storage.length > 0 {
            storage.append(NSAttributedString(string: joins ? " " : "\n", attributes: [.font: monoFont]))
        }
        let attr = (joins && styled.source != nil)
            ? styleLine(raw, showTimestamps: showTimestamps, continuing: true).attr
            : styled.attr
        storage.append(attr)
        lastLineWasTranscript = styled.isTranscript
        lastLineSource = styled.source
    }

    // Rebuild the whole scroll under the current `showTimestamps` — called when the
    // Timestamps checkbox toggles. Replays every stored raw line (meter lines aren't
    // stored; pre-engine appendError lines bypass handle() and are dropped on rebuild).
    private func rerenderTranscript() {
        guard let storage = textView.textStorage else { return }
        storage.beginEditing()
        storage.setAttributedString(NSAttributedString())
        lastLineWasTranscript = false
        lastLineSource = nil
        for raw in displayedRawLines {
            appendStyled(styleLine(raw, showTimestamps: showTimestamps), raw: raw, to: storage)
        }
        storage.endEditing()
        textView.scrollToEndOfDocument(nil)
    }

    // MARK: Shutdown

    // The engine exited on its own (self-stop / crash). Copy per prefs, no paste.
    // The `finishing` guard absorbs the race with a concurrent user stop.
    private func engineEnded() {
        finish(cancelled: false, userInitiated: false)
    }

    private func installSignalHandlers() {
        // SIGTERM (launcher Alt+Space stop) = explicit user stop → force plain mode
        // (no timestamps, full transcript) + paste.
        signal(SIGTERM, SIG_IGN)
        let termSrc = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        termSrc.setEventHandler { [weak self] in self?.finish(cancelled: false, userInitiated: true, mode: .plain) }
        termSrc.resume()
        signalSources.append(termSrc)

        // SIGINT (⌃C / logout) = hard stop → copy per prefs, no paste.
        signal(SIGINT, SIG_IGN)
        let intSrc = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        intSrc.setEventHandler { [weak self] in self?.finish(cancelled: false, userInitiated: false) }
        intSrc.resume()
        signalSources.append(intSrc)

        // SIGUSR1 (Cmd+Alt+Space → live-transcribe-launch --ref) = explicit user stop
        // that forces reference mode (timestamps + `read <path>`). Its default
        // disposition is *terminate*, so SIG_IGN MUST come first.
        signal(SIGUSR1, SIG_IGN)
        let refSrc = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        refSrc.setEventHandler { [weak self] in self?.finish(cancelled: false, userInitiated: true, mode: .reference) }
        refSrc.resume()
        signalSources.append(refSrc)
    }

    // Safety net for hard-kill/logout routes that bypass finish() (which normally does
    // all of this asynchronously). Guarantees no orphan engine + a best-effort copy;
    // never pastes — there's no runloop left once this returns.
    func applicationWillTerminate(_ notification: Notification) {
        // First, as in finish(). This path blocks the MAIN thread for up to 10s below, so
        // a still-registered grab would eat every Escape in that window and deliver it
        // nowhere — we can't dispatch the Carbon event, and the focused app never sees it.
        unregisterEscapeHotKey()
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
        // Copy iff we haven't already (covers a hard terminate that raced finish()'s
        // async drain). `cancelled` still means "leave the clipboard alone".
        if !clipboardWritten, !cancelled {
            clipboardWritten = deliver()
        }
    }

    // MARK: Stop funnel

    // Single async shutdown path for every stop route; first caller wins (sets the
    // intent). The ≤10s engine-flush wait runs OFF the main thread so the runloop stays
    // live for the async auto-paste; we only terminate at the very end.
    private func finish(cancelled: Bool, userInitiated: Bool, mode: OutputMode? = nil) {
        if finishing { return }
        finishing = true
        // FIRST: give Escape back. Everything below this can take ~10s (the engine drain,
        // then auto-paste), and during that window you're already back in your editor.
        unregisterEscapeHotKey()
        self.cancelled = cancelled
        self.pasteEligible = userInitiated
        // The stop hotkey re-asserts its mode over the launch seed, so the key you stop
        // with decides the output even if the other key started the session. A checkbox
        // the user hand-toggled is exempt — an explicit choice outranks the default.
        if let mode {
            if !tsTouched { showTimestamps = mode.wantsTimestamps }
            if !refTouched { copyAsReference = mode.wantsReference }
        }
        updateIcon(running: false)
        statusField?.stringValue = "🎙 stopped"
        setControlsEnabled(false)

        let p = engine
        DispatchQueue.global(qos: .userInitiated).async {
            if let p = p, p.isRunning {
                kill(p.processIdentifier, SIGINT)
                let deadline = Date().addingTimeInterval(10.0)
                while p.isRunning && Date() < deadline { usleep(100_000) }
                if p.isRunning { kill(p.processIdentifier, SIGKILL) }
            }
            DispatchQueue.main.async { [weak self] in self?.afterEngineStopped() }
        }
    }

    // Engine is dead and the .txt handle is released — safe to copy and (if eligible)
    // auto-paste. The saved .txt is deliberately left exactly as the engine wrote it,
    // timestamps and all: it's the Cloud-synced record aligned with the sibling .m4a,
    // and flattening it would be irreversible. The Timestamps checkbox governs only
    // what's displayed and copied, both of which are re-derivable from the archive.
    private func afterEngineStopped() {
        enginePipe?.fileHandleForReading.readabilityHandler = nil
        applyPasteTargetOverride()
        let didWrite = deliver()
        clipboardWritten = didWrite

        // Auto-paste ONLY when the copy actually wrote — else ⌘V would paste a STALE
        // clipboard into a live field. Also gated on: an explicit user stop, not
        // cancelled, the checkbox, live permission, and a valid non-self target app.
        guard pasteEligible, !cancelled, didWrite,
              UserDefaults.standard.bool(forKey: "pref.autoPaste"),
              CGPreflightPostEventAccess(),
              let target = targetApp, !target.isTerminated, target != .current
        else { terminateNow(); return }

        if #available(macOS 14.0, *) { NSApp.yieldActivation(to: target) }
        target.activate(options: [.activateIgnoringOtherApps])
        pollFrontmost(target, attempts: 20)        // runloop-based, ~1s cap
    }

    // Wait — via the runloop, NOT a blocking sleep — until the target is actually
    // frontmost, then post ⌘V. On timeout, do NOT blind-fire: leave the text on the
    // clipboard so the keystroke can't land in our own view or the wrong app.
    private func pollFrontmost(_ app: NSRunningApplication, attempts: Int) {
        if NSWorkspace.shared.frontmostApplication == app {
            postCommandV()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { [weak self] in self?.terminateNow() }
            return
        }
        if attempts <= 0 { terminateNow(); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.pollFrontmost(app, attempts: attempts - 1)
        }
    }

    private func postCommandV() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let v: CGKeyCode = 0x09   // kVK_ANSI_V (physical 'v'; assumes a QWERTY/ANSI layout)
        let down = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: true)
        let up   = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand   // set on both — some apps check the modifier on key-up
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
    }

    private func terminateNow() {
        NSApp.terminate(nil)
    }

    // A full transcript can exceed what the app we're about to ⌘V into will accept. When
    // we know where the paste lands — i.e. auto-paste is on and we have a live target —
    // and the text won't fit, downgrade to the `read <path>` reference: it's short, and
    // ~/Cloud/transcripts syncs via ProtonDrive so the path resolves on the other device
    // you'll actually read it on.
    //
    // Only Telegram Web is special-cased, because it's the only target whose ceiling we
    // know (4096 UTF-16 units per message — Telegram counts UTF-16, not graphemes).
    // Skipped when we're already sending a reference, and when there's no path to point
    // at. Deliberately NOT applied in applicationWillTerminate: that route never pastes,
    // so nothing is known about a destination.
    private func applyPasteTargetOverride() {
        guard !cancelled, pasteEligible, !copyAsReference, transcriptPath != nil,
              UserDefaults.standard.bool(forKey: "pref.autoPaste"),
              let target = targetApp, !target.isTerminated,
              target.bundleIdentifier == telegramBundleID,
              let text = fullTranscriptText(), text.utf16.count > telegramMessageLimit()
        else { return }
        overflowReference = true
    }

    // Puts the transcript on the clipboard per the session mode; returns whether it
    // actually wrote. Either flavour of reference needs a known path.
    @discardableResult
    private func deliver() -> Bool {
        if cancelled { return false }   // Escape/Cancel/close: leave the clipboard alone
        let useRef = copyAsReference || overflowReference
        if useRef, transcriptPath != nil { return copyReferenceToPasteboard() }
        return copyFullToPasteboard()   // full, or reference with an unknown path
    }

    // The text a full copy would place on the clipboard — the saved .txt when it's
    // readable, else the in-memory accumulation, flowed into prose when Timestamps is
    // off. nil when there's nothing worth writing, so no caller can clobber the
    // clipboard with empty. Read twice per stop at most (the override probe, then the
    // copy); a once-per-session file read isn't worth caching around.
    private func fullTranscriptText() -> String? {
        var text: String?
        if let p = transcriptPath, let s = try? String(contentsOfFile: p, encoding: .utf8),
           !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text = s
        }
        if text == nil, !accumulated.isEmpty {
            text = accumulated.joined(separator: "\n") + "\n"
        }
        guard var out = text, !out.isEmpty else { return nil }
        if !showTimestamps { out = flowTranscript(out) }           // flows file OR accumulated
        // Re-check AFTER flowing: a transcript of nothing but empty entries reduces to
        // whitespace, and a blank clipboard would still satisfy deliver()'s auto-paste gate.
        guard !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return out
    }

    @discardableResult
    private func copyFullToPasteboard() -> Bool {
        guard let out = fullTranscriptText() else { return false }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(out, forType: .string)
        return true
    }

    // Short cross-device reference for when the full transcript overflows a chat
    // limit — ~/Cloud/... resolves on other devices since the folder syncs.
    @discardableResult
    private func copyReferenceToPasteboard() -> Bool {
        guard let p = transcriptPath else { return false }
        let ref = "read " + (p as NSString).abbreviatingWithTildeInPath
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(ref, forType: .string)
        return true
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
