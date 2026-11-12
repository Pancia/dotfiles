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
// One exception, added with the mic picker: an engine that exits NONZERO having
// transcribed nothing never started a session at all, so we go idle instead of
// closing — otherwise a bad device would take the picker down with it.
//
// Microphone: chosen from the 🎙 pull-down in the footer (or the status menu's
// "Microphone" submenu), listed live from CoreAudio and remembered in
// pref.micDevice. The engine binds its device at start-up, so switching stops it
// and starts a fresh one on the new device — which is why the session tracks a
// LIST of transcript files rather than one.
//
// History: the clock pull-down in the panel's top bar and the status menu's "Recent
// Transcripts" submenu list the last 10 saved transcripts, newest first. Clicking one
// copies its `read <path>` reference and opens it in whatever owns .txt. Both end in
// "Open Transcripts Folder". When no session runs, `transcript-pick` (Hermes ⌘Space
// → u → t) browses them all.
//
// Build: see Makefile (plain swiftc → .app bundle, codesigned).

import AppKit
import CoreGraphics   // CGEvent + CGPreflight/RequestPostEventAccess (auto-linked via AppKit)
import Carbon.HIToolbox   // RegisterEventHotKey — the global Escape grab (see registerEscapeHotKey)
import CoreAudio          // AudioObject* — the input-device list behind the mic picker
import Foundation

// MARK: - Config / args

func argValue(_ name: String) -> String? {
    let a = CommandLine.arguments
    if let i = a.firstIndex(of: name), i + 1 < a.count { return a[i + 1] }
    return nil
}

// The device a session opens with when nothing better is known. A mic chosen in the UI
// (pref.micDevice) outranks it: the launcher passes --mic from a hardcoded default,
// while the preference is a decision somebody made. See resolveMicDevice().
let micArgDefault = argValue("--mic") ?? "BOYA"

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

// MARK: - Audio input devices

// Enumerated through CoreAudio rather than by shelling out to the engine's
// `--list-devices`: that means a second Python + PortAudio start-up (seconds) racing the
// engine's own, and the picker re-reads the list every time it opens.
//
// The engine resolves --mic-device by case-insensitive SUBSTRING match over PortAudio's
// device list, and PortAudio on macOS reports the CoreAudio device name verbatim — so
// handing it a full name read here selects the same device. Names are not guaranteed
// unique (two identical USB interfaces), which the engine can't disambiguate either.
struct AudioInputDevice {
    let id: AudioDeviceID
    let name: String
}

private func audioObjectString(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
    var addr = AudioObjectPropertyAddress(mSelector: selector,
                                          mScope: kAudioObjectPropertyScopeGlobal,
                                          mElement: kAudioObjectPropertyElementMain)
    // Unmanaged, not a plain CFString?: CoreAudio hands back a +1 reference here, and
    // writing it through a raw pointer into a managed optional leaves ARC guessing.
    var out: Unmanaged<CFString>? = nil
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    let err = withUnsafeMutablePointer(to: &out) {
        AudioObjectGetPropertyData(id, &addr, 0, nil, &size, UnsafeMutableRawPointer($0))
    }
    guard err == noErr, let name = out else { return nil }
    return name.takeRetainedValue() as String
}

// Total input channels across the device's input streams. Zero means it can't record,
// which is how output-only devices (and the output half of a duplex device) are dropped.
private func inputChannelCount(_ id: AudioDeviceID) -> UInt32 {
    var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                          mScope: kAudioObjectPropertyScopeInput,
                                          mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
    let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size),
                                               alignment: MemoryLayout<AudioBufferList>.alignment)
    defer { raw.deallocate() }
    guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr else { return 0 }
    let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
    return list.reduce(0) { $0 + $1.mNumberChannels }
}

func availableInputDevices() -> [AudioInputDevice] {
    var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                          mScope: kAudioObjectPropertyScopeGlobal,
                                          mElement: kAudioObjectPropertyElementMain)
    let sys = AudioObjectID(kAudioObjectSystemObject)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(sys, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
    var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(sys, &addr, 0, nil, &size, &ids) == noErr else { return [] }
    return ids.compactMap { id in
        guard inputChannelCount(id) > 0,
              let name = audioObjectString(id, kAudioObjectPropertyName) else { return nil }
        return AudioInputDevice(id: id, name: name)
    }
}

func defaultInputDeviceName() -> String? {
    var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                          mScope: kAudioObjectPropertyScopeGlobal,
                                          mElement: kAudioObjectPropertyElementMain)
    var id = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr,
          id != 0 else { return nil }
    return audioObjectString(id, kAudioObjectPropertyName)
}

// Which device this session opens on. Preference first (a choice made in the picker),
// then --mic (the launcher's hardcoded default), then whatever macOS is currently using
// for input — so an unplugged BOYA degrades to something that records instead of the
// engine dying on "No device found matching 'BOYA'" before the UI can offer an
// alternative. Matching is the same case-insensitive substring test the engine applies,
// so a stored name and the engine agree on which device it names; the FULL name of the
// device that matched is what we return and pass on.
func resolveMicDevice() -> String {
    let devices = availableInputDevices()
    func present(_ needle: String) -> String? {
        let n = needle.lowercased()
        return devices.first { $0.name.lowercased().contains(n) }?.name
    }
    if let pref = UserDefaults.standard.string(forKey: "pref.micDevice"), let hit = present(pref) { return hit }
    if let hit = present(micArgDefault) { return hit }
    if let fallback = defaultInputDeviceName() { return fallback }
    return micArgDefault
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

    // The CURRENT engine run's transcript, and the latch that captures it: reset to nil
    // on a mic switch so the replacement engine's path is picked up too.
    private var transcriptPath: String?
    // Every transcript file this session has produced, oldest first — one per engine run,
    // so a mic switch APPENDS a file rather than replacing the one a copy reads. This,
    // not transcriptPath, is what every copy/reveal/overflow check reads.
    private var transcriptPaths: [String] = []
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
    private var micPopup: NSPopUpButton!
    private var optionsPopup: NSPopUpButton!   // ⚙ pull-down holding every toggle
    private var historyPopup: NSPopUpButton!   // clock pull-down: earlier transcripts
    // Inline copies of the same toggles, shown only while the top bar has room for them.
    private var tsCheck: NSButton!
    private var refCheck: NSButton!
    private var pasteCheck: NSButton!
    private var enterCheck: NSButton!
    private var completeButton: NSButton!
    private var cancelButton: NSButton!

    // The device the engine is currently recording from — a real device name resolved
    // against the live CoreAudio list, not whatever string happened to be stored.
    private var micDevice = micArgDefault
    // Set while a mic switch is tearing the old engine down, so the shutdown funnel
    // doesn't read a deliberate restart as the session ending.
    private var restarting = false

    // Menu items whose actions need a known transcript path; disabled until then.
    private var cancelItem: NSMenuItem!
    private var micMenuItem: NSMenuItem!    // "Microphone" submenu; rebuilt on every open
    private var recentItem: NSMenuItem!     // "Recent Transcripts" submenu; ditto
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
            "pref.autoEnter": false,
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

        // Resolved before the UI is built: the panel title and both pickers name it.
        micDevice = resolveMicDevice()

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
        refreshTitle()
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
        // 300pt is what the footer needs (mic button + compact meter); the top bar needs
        // ~250. 72pt of transcript is about three lines at 22pt.
        panel.contentMinSize = NSSize(width: 300, height: topH + barH + 72)

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

        // The mic picker is a 44pt icon-only pull-down: this strip's real tenant is the
        // meter, so a popup wide enough to show a device NAME would truncate it — the
        // name goes in the panel title instead. The button TAKES OVER the meter's
        // leading "🎙 " rather than adding to it.
        let micW: CGFloat = 44
        let micH: CGFloat = 22
        let mic = NSPopUpButton(frame: NSRect(x: 4, y: (barH - micH) / 2, width: micW, height: micH),
                                pullsDown: true)
        mic.font = NSFont.systemFont(ofSize: 13)
        mic.autoresizingMask = [.maxXMargin, .maxYMargin]
        mic.toolTip = "Microphone — switching restarts the engine"
        content.addSubview(mic)
        micPopup = mic
        rebuildMicPopup()
        mic.menu?.delegate = self   // repopulated on open, so a hot-plugged device shows up

        let sfH: CGFloat = 24
        let sfX: CGFloat = 4 + micW + 6
        let sf = NSTextField(frame: NSRect(x: sfX, y: (barH - sfH) / 2, width: content.bounds.width - sfX - 6, height: sfH))
        sf.isEditable = false
        sf.isSelectable = false
        sf.isBordered = false
        sf.drawsBackground = false
        sf.font = statusFont
        sf.textColor = Palette.dim   // covers the initial text + any parse-miss fallback
        sf.usesSingleLineMode = true
        sf.lineBreakMode = .byTruncatingTail
        sf.stringValue = "waiting for audio…"
        sf.toolTip = "Mic level · speech state · audio chunks sent to the transcriber"
        sf.autoresizingMask = [.width, .maxYMargin]
        content.addSubview(sf)
        statusField = sf

        showDebug = UserDefaults.standard.bool(forKey: "pref.showDebug")

        // Top control bar: ⚙ options (left) + Cancel/Complete (right).
        buildControlBar(in: content, topH: topH)
        refreshTitle()   // again: buildControlBar just seeded the output mode

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

    // Top strip: ⚙ options left, Cancel/Complete right. A programmatic NSStackView
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
        // Responsive: when the bar is too narrow, the stack DETACHES the lowest-visibility
        // checkboxes instead of widening the window. Low clipping resistance is what lets
        // the window win; at the default (required) the stack forces the panel wider.
        bar.detachesHiddenViews = true
        bar.setClippingResistancePriority(.defaultLow, for: .horizontal)

        // The hotkey's mode wins; the registered defaults only cover a bare launch with
        // no --mode (opening the .app straight from Finder).
        let d = UserDefaults.standard
        showTimestamps  = launchMode?.wantsTimestamps ?? d.bool(forKey: "pref.timestamps")
        copyAsReference = launchMode?.wantsReference  ?? d.bool(forKey: "pref.copyAsReference")

        // Every toggle lives in one pull-down, so the window can go down to ~300pt wide.
        // When it is wider, checkboxes for the same toggles fill the space next to it.
        // The panel title also carries the output options (see panelTitle).
        let opts = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 44, height: 22), pullsDown: true)
        opts.font = NSFont.systemFont(ofSize: 13)
        opts.toolTip = "Options"
        optionsPopup = opts
        rebuildOptionsMenu()
        opts.menu?.delegate = self   // rebuilt on open, so checkmarks track the hotkey mode
        opts.setContentHuggingPriority(.required, for: .horizontal)   // else it soaks up slack

        // Earlier transcripts, the same list as the status menu's "Recent Transcripts".
        // Here too because the menu-bar item is easy to miss. Up top, not in the footer:
        // the footer's width belongs to the meter (see rebuildRecentSubmenu's comment).
        let hist = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 44, height: 22), pullsDown: true)
        hist.font = NSFont.systemFont(ofSize: 13)
        hist.toolTip = "Earlier transcripts — click one to open it and copy its `read <path>`"
        historyPopup = hist
        rebuildHistoryMenu()
        hist.menu?.delegate = self   // rebuilt on open, so a session that just ended shows up
        hist.setContentHuggingPriority(.required, for: .horizontal)

        func check(_ title: String, _ action: Selector, _ tip: String) -> NSButton {
            let b = NSButton(checkboxWithTitle: title, target: self, action: action)
            b.font = NSFont.systemFont(ofSize: 13)     // NOT tiny .small next to 22pt transcript
            b.toolTip = tip
            return b
        }
        tsCheck    = check("Timestamps",     #selector(toggleTimestamps),
                           "Keep [HH:MM:SS] timestamps in the view and the copied text")
        refCheck   = check("File reference", #selector(togglePrefRef),
                           "Copy a `read <path>` reference to the saved transcript instead of the text")
        pasteCheck = check("Auto-paste",     #selector(togglePrefPaste),
                           "On Complete, switch back to the previous app and press ⌘V")
        enterCheck = check("+ Enter",        #selector(togglePrefEnter),
                           "After auto-paste, also press Return (submits in Claude Code, sends in chat apps)")

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

        bar.addView(opts, in: .leading)
        bar.addView(hist, in: .leading)
        // Outlasts every checkbox as the bar narrows; only Cancel/Complete matter more.
        bar.setVisibilityPriority(NSStackView.VisibilityPriority(500), for: hist)
        // Visibility order as the bar narrows: Timestamps goes first (the transcript shows
        // it anyway), then File reference, then the Auto-paste/+ Enter pair together.
        for (b, pri) in [(tsCheck!, 250), (refCheck!, 300), (pasteCheck!, 400), (enterCheck!, 400)] {
            bar.addView(b, in: .leading)
            bar.setVisibilityPriority(NSStackView.VisibilityPriority(Float(pri)), for: b)
        }
        bar.setCustomSpacing(4, after: pasteCheck)     // reads as a sub-option of Auto-paste
        syncToggleViews()
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

    // The active device rides in the title bar because the footer strip it is picked
    // from has to keep its width for the meter. Recomputed on every switch.
    // Every title change goes through here. A never-key panel draws its title in the
    // dim inactive colour, so recolour AppKit's own title field each time. Found by
    // walking the titlebar view; if a future macOS renames it, the title is just dim.
    private func refreshTitle() {
        panel.title = panelTitle()
        guard let titlebar = panel.standardWindowButton(.closeButton)?.superview else { return }
        func fields(_ v: NSView) -> [NSTextField] {
            if let tf = v as? NSTextField { return [tf] }
            return v.subviews.flatMap(fields)
        }
        fields(titlebar).forEach { $0.textColor = Palette.normal }
    }

    // Checkbox states follow the model, so the menu and the inline checkboxes agree.
    private func syncToggleViews() {
        let d = UserDefaults.standard
        let paste = d.bool(forKey: "pref.autoPaste")
        tsCheck?.state    = showTimestamps ? .on : .off
        refCheck?.state   = copyAsReference ? .on : .off
        pasteCheck?.state = paste ? .on : .off
        enterCheck?.state = d.bool(forKey: "pref.autoEnter") ? .on : .off
        enterCheck?.isEnabled = paste && !finishing
        refreshTitle()
    }

    // The output options come before the device so a narrow window truncates the device
    // name, not them. Timestamps is left out: the transcript itself shows that one.
    private func panelTitle() -> String {
        var tags: [String] = []
        if copyAsReference { tags.append("ref") }
        let d = UserDefaults.standard
        if d.bool(forKey: "pref.autoPaste") { tags.append(d.bool(forKey: "pref.autoEnter") ? "paste+⏎" : "paste") }
        let opts = tags.isEmpty ? "" : " · " + tags.joined(separator: " · ")
        return "Live Transcribe" + opts + " — " + micDevice
    }

    // A pull-down's item 0 is its button title and is never listed, so the toggles
    // start at index 1 (same pattern as the mic picker).
    private func rebuildOptionsMenu() {
        guard let menu = optionsPopup?.menu else { return }
        menu.removeAllItems()
        menu.autoenablesItems = false
        menu.addItem(NSMenuItem(title: "⚙︎", action: nil, keyEquivalent: ""))
        let d = UserDefaults.standard
        let paste = d.bool(forKey: "pref.autoPaste")
        func item(_ title: String, _ on: Bool, _ action: Selector, tip: String, enabled: Bool = true) {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
            i.target = self
            i.state = on ? .on : .off
            i.toolTip = tip
            i.isEnabled = enabled && !finishing
            menu.addItem(i)
        }
        item("Timestamps", showTimestamps, #selector(toggleTimestamps),
             tip: "Keep [HH:MM:SS] timestamps in the view and the copied text")
        item("File reference", copyAsReference, #selector(togglePrefRef),
             tip: "Copy a `read <path>` reference to the saved transcript instead of the text")
        item("Auto-paste", paste, #selector(togglePrefPaste),
             tip: "On Complete, switch back to the previous app and press ⌘V")
        item("    + Enter", d.bool(forKey: "pref.autoEnter"), #selector(togglePrefEnter),
             tip: "After auto-paste, also press Return (submits in Claude Code, sends in chat apps)",
             enabled: paste)   // its state persists; it just can't act without paste
        menu.addItem(.separator())
        item("Debug", showDebug, #selector(toggleDebug),
             tip: "Show the engine's startup chatter in the transcript")
    }

    private func setControlsEnabled(_ on: Bool) {
        [micPopup, optionsPopup, tsCheck, refCheck, pasteCheck, completeButton, cancelButton].forEach { $0?.isEnabled = on }
        enterCheck?.isEnabled = on && pasteCheck?.state == .on
    }

    // Neither of these persists any more: the launch mode reseeds them every session, so
    // a stored value could only ever be stale. They are session overrides, and the
    // `touched` flag is what protects them from the stop hotkey re-asserting its mode.
    @objc private func toggleTimestamps() {
        showTimestamps.toggle()
        tsTouched = true
        syncToggleViews()
        rerenderTranscript()
    }

    @objc private func togglePrefRef() {
        copyAsReference.toggle()
        refTouched = true
        syncToggleViews()
    }

    @objc private func toggleDebug() {
        showDebug.toggle()
        UserDefaults.standard.set(showDebug, forKey: "pref.showDebug")
        rerenderTranscript()
    }

    @objc private func togglePrefPaste() {
        let on = !UserDefaults.standard.bool(forKey: "pref.autoPaste")
        UserDefaults.standard.set(on, forKey: "pref.autoPaste")
        syncToggleViews()
        // Prompt for Accessibility now (app is active). The grant lands async and
        // usually needs a relaunch, so triggering it here beats prompting mid-stop.
        if on, !CGPreflightPostEventAccess() { _ = CGRequestPostEventAccess() }
    }

    @objc private func togglePrefEnter() {
        let d = UserDefaults.standard
        d.set(!d.bool(forKey: "pref.autoEnter"), forKey: "pref.autoEnter")
        syncToggleViews()
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

        // The same picker as the panel's, for when the panel is hidden. Contents are
        // rebuilt in menuNeedsUpdate, so a device plugged in mid-session shows up here too.
        micMenuItem = NSMenuItem(title: "Microphone", action: nil, keyEquivalent: "")
        micMenuItem.submenu = NSMenu()
        micMenuItem.submenu?.autoenablesItems = false
        menu.addItem(micMenuItem)

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

        // Earlier sessions, opened in whatever owns .txt. Lives here rather than in the
        // panel because the footer strip it would have shared has no width left: the
        // meter needs up to 436pt of it, and a second 40pt pull-down plus its gap put a
        // four-digit chunk count past the truncation point at the default window size.
        recentItem = NSMenuItem(title: "Recent Transcripts", action: nil, keyEquivalent: "")
        recentItem.submenu = NSMenu()
        recentItem.submenu?.autoenablesItems = false
        menu.addItem(recentItem)

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
        // Three menus share this delegate. The popup's has no "Hide Panel" at index 0, so
        // the status-menu maintenance below would rewrite its button title.
        if let popup = micPopup, menu === popup.menu { rebuildMicPopup(); return }
        if let popup = optionsPopup, menu === popup.menu { rebuildOptionsMenu(); return }
        if let popup = historyPopup, menu === popup.menu { rebuildHistoryMenu(); return }
        rebuildMicSubmenu()
        rebuildRecentSubmenu()
        menu.item(at: 0)?.title = panel.isVisible ? "Hide Panel" : "Show Panel"
        // The copy/reveal actions need a known transcript path (empty for ~1s at
        // startup until the engine emits "Writing transcript to:").
        let hasPath = !transcriptPaths.isEmpty
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
        guard !transcriptPaths.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(transcriptPaths.map { URL(fileURLWithPath: $0) })
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

    // MARK: Mic picker

    // Both pickers are rebuilt from the live CoreAudio list every time they are about to
    // open, so a mic plugged in mid-session appears without a relaunch. The active device
    // is always in the list even when CoreAudio has stopped reporting it (unplugged while
    // recording), so neither picker can offer a set of names excluding the one in use.
    private func micMenuNames() -> [String] {
        var names = availableInputDevices().map { $0.name }
        if !names.contains(micDevice) { names.insert(micDevice, at: 0) }
        return names
    }

    private func micItem(_ name: String) -> NSMenuItem {
        let item = NSMenuItem(title: name, action: #selector(micPicked(_:)), keyEquivalent: "")
        item.target = self
        item.state = (name == micDevice) ? .on : .off
        // Once the session is stopping there is no engine left to point anywhere.
        item.isEnabled = !finishing
        return item
    }

    // A pull-down, not a pop-up: the button keeps its narrow "🎙" title instead of
    // widening to whatever the selected device is called. Item 0 IS that title — a
    // pull-down never lists its first item — so the devices start at index 1.
    private func rebuildMicPopup() {
        guard let menu = micPopup?.menu else { return }
        menu.removeAllItems()
        menu.autoenablesItems = false
        menu.addItem(NSMenuItem(title: "🎙", action: nil, keyEquivalent: ""))
        for name in micMenuNames() { menu.addItem(micItem(name)) }
    }

    private func rebuildMicSubmenu() {
        guard let menu = micMenuItem?.submenu else { return }
        menu.removeAllItems()
        for name in micMenuNames() { menu.addItem(micItem(name)) }
    }

    @objc private func micPicked(_ sender: NSMenuItem) { switchMic(to: sender.title) }

    // Move the session to another input device. The engine binds its device at start-up
    // and offers no way to retune it, so this stops the running one and starts a fresh
    // one — which is why the transcript is tracked as a LIST of files: the new engine
    // opens its own transcript_<ts>.txt and .m4a, and a copy at stop has to carry both.
    //
    // Strictly sequential, never overlapping. Each engine sweeps orphan
    // ~/.local/state/live-transcribe/rec_*.wav at start-up. Since 2026-11-12 it only
    // takes ones untouched for 14 days, so overlap no longer deletes a live recording,
    // but two engines on one device still fight over it.
    private func switchMic(to name: String) {
        guard !finishing, !restarting else { return }
        let idle = (engine == nil)
        // From idle this is a retry, so re-picking the SAME device has to be honoured.
        guard idle || name != micDevice else { return }

        micDevice = name
        UserDefaults.standard.set(name, forKey: "pref.micDevice")
        refreshTitle()

        if idle {
            statusField?.stringValue = "starting on \(name)…"
            transcriptPath = nil
            startEngine()
            updateIcon(running: true)
            return
        }

        restarting = true
        statusField?.stringValue = "switching to \(name)…"
        appendNotice("— switching microphone to \(name) —")

        // Drop the termination handler BEFORE the kill. Left in place it would race the
        // restart onto the main queue and end the whole session for us, and `restarting`
        // is not a reliable guard against it: both hops land on main in no fixed order.
        //
        // `engine` deliberately keeps pointing at the old process until it is dead, so a
        // Complete/Cancel landing in this window still finds something to SIGINT and wait
        // on rather than copying a transcript the engine is mid-flush of.
        let old = engine
        old?.terminationHandler = nil
        enginePipe?.fileHandleForReading.readabilityHandler = nil

        DispatchQueue.global(qos: .userInitiated).async {
            if let p = old, p.isRunning {
                kill(p.processIdentifier, SIGINT)
                let deadline = Date().addingTimeInterval(10.0)
                while p.isRunning && Date() < deadline { usleep(100_000) }
                if p.isRunning { kill(p.processIdentifier, SIGKILL) }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.restarting = false
                guard !self.finishing else { return }   // a stop landed mid-teardown
                self.engine = nil
                self.enginePipe = nil
                self.transcriptPath = nil               // the new engine announces its own
                self.lineBuffer = Data()                // no reader is attached; drop any half line
                self.startEngine()
                self.updateIcon(running: true)
            }
        }
    }

    // Engine dead but the session is NOT over: nothing was recorded, so there is nothing
    // to copy and nothing to flush. Keep the panel, the menu and the picker alive so a
    // different device can be chosen — picking one starts a fresh engine.
    private func enterIdle() {
        enginePipe?.fileHandleForReading.readabilityHandler = nil
        engine = nil
        enginePipe = nil
        updateIcon(running: false)
        statusField?.stringValue = "engine stopped — pick a microphone to retry"
        appendNotice("— engine exited before recording started; pick a microphone from 🎙 to retry —")
    }

    // MARK: Recent transcripts

    // Built once: a DateFormatter is expensive, and these are used ten at a time every
    // time the menu opens. The parser is pinned to POSIX because the filename stamp is a
    // fixed format, not a localized one — a user locale with a non-Gregorian calendar
    // would otherwise fail to parse it.
    private static let stampParser: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
    private static let stampDisplay: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        f.doesRelativeDateFormatting = true   // "Today, 7:28 PM"
        return f
    }()

    private func rebuildRecentSubmenu() {
        guard let menu = recentItem?.submenu else { return }
        menu.removeAllItems()
        fillRecent(menu)
    }

    // The panel's history pull-down. Item 0 of a pull-down is its button face, never
    // shown as an entry, so it carries the icon and the list starts at item 1.
    private func rebuildHistoryMenu() {
        guard let menu = historyPopup?.menu else { return }
        menu.removeAllItems()
        menu.autoenablesItems = false
        let face = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        if #available(macOS 11.0, *),
           let img = NSImage(systemSymbolName: "clock.arrow.circlepath",
                             accessibilityDescription: "Earlier transcripts") {
            face.image = img
        } else {
            face.title = "🕘"
        }
        menu.addItem(face)
        fillRecent(menu)
    }

    // Shared body of both history menus: the recent list, then a way to everything older.
    private func fillRecent(_ menu: NSMenu) {
        let items = recentTranscriptItems()
        if items.isEmpty {
            let empty = NSMenuItem(title: "No earlier transcripts", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for item in items { menu.addItem(item) }
        menu.addItem(.separator())
        let all = NSMenuItem(title: "Open Transcripts Folder", action: #selector(openTranscriptsFolder),
                             keyEquivalent: "")
        all.target = self
        all.toolTip = cloudTranscriptsDir
        menu.addItem(all)
    }

    @objc private func openTranscriptsFolder() {
        NSWorkspace.shared.open(URL(fileURLWithPath: cloudTranscriptsDir, isDirectory: true))
    }

    // The last `limit` saved transcripts, newest first, as ready-made menu items.
    //
    // Ordered by FILENAME, not mtime — the same reason live-transcribe-launch's --copy
    // recovery is: transcript_<ts> sorts lexically with record-start, and ProtonDrive
    // rewrites mtimes when it syncs a file back down from another device, which would
    // shuffle this list into "whatever synced last".
    //
    // This session's own files are left out; Copy Transcript and Reveal in Finder already
    // address those, and a file still being appended to reads oddly as history. Empty ones
    // are left out too — an aborted session would otherwise cost a slot a real transcript
    // wants. That test is a stat, so it rejects them without a read.
    private func recentTranscriptItems(limit: Int = 10) -> [NSMenuItem] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: cloudTranscriptsDir) else { return [] }
        let mine = Set(transcriptPaths)
        var items: [NSMenuItem] = []
        for name in names.filter({ $0.hasPrefix("transcript_") && $0.hasSuffix(".txt") }).sorted(by: >) {
            if items.count >= limit { break }
            let path = cloudTranscriptsDir + "/" + name
            if mine.contains(path) { continue }
            let size = ((try? fm.attributesOfItem(atPath: path))?[.size] as? NSNumber)?.intValue ?? 0
            if size == 0 { continue }
            let item = NSMenuItem(title: transcriptLabel(name: name, path: path),
                                  action: #selector(openTranscript(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = path
            // Says what clicking does, because the copy half of it is otherwise silent:
            // the footer is the meter, which the engine repaints ten times a second.
            item.toolTip = "Opens \(path)\nand copies: \(referenceString(for: [path]))"
            items.append(item)
        }
        return items
    }

    // "Today, 7:28 PM  ·  Testing 1, 2, 3." — a bare column of timestamps is unusable for
    // picking one out, and the opening words are what a session is actually recognisable by.
    private func transcriptLabel(name: String, path: String) -> String {
        let stamp = String(name.dropFirst("transcript_".count).dropLast(".txt".count))
        let when = AppDelegate.stampParser.date(from: stamp)
            .map { AppDelegate.stampDisplay.string(from: $0) } ?? stamp
        guard let preview = transcriptPreview(path) else { return when }
        return when + "  ·  " + preview
    }

    // First line of the file, with the engine's "[HH:MM:SS] " and any "Microphone: "
    // source label stripped. Reads the head only: these sit in ~/Cloud/transcripts, today
    // a plain local directory that ProtonDrive syncs, but building a menu should not
    // depend on that — or on how long the first line of a transcript happens to be.
    private func transcriptPreview(_ path: String, max: Int = 44) -> String? {
        guard let fh = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? fh.close() }
        guard let head = try? fh.read(upToCount: 512), !head.isEmpty else { return nil }
        // A fixed-byte cut can land mid-codepoint; the U+FFFD that leaves behind is dropped.
        var line = String(decoding: head, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
        line = line.replacingOccurrences(of: "\u{FFFD}", with: "")
        let range = NSRange(line.startIndex..., in: line)
        if let m = transcriptRegex.firstMatch(in: line, range: range),
           let textR = Range(m.range(at: 3), in: line) {
            line = String(line[textR])
        }
        line = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.isEmpty { return nil }
        return line.count > max ? String(line.prefix(max - 1)) + "…" : line
    }

    // Puts the file's `read <path>` reference on the clipboard, then hands the file to
    // whatever owns .txt (TextEdit unless you've changed it). Clipboard FIRST, so a
    // LaunchServices open that fails still leaves you the reference.
    //
    // Deliberately does NOT set `clipboardWritten`: that flag means "this session's
    // transcript has been delivered", and the terminate safety net reads it to decide
    // whether it still owes you a copy. Setting it here would make opening a piece of
    // history silently cancel the delivery of the session you're recording.
    //
    // The stop path will overwrite this clipboard when the session ends — unavoidable,
    // one clipboard — so this is for grabbing a reference in passing, not for parking one.
    //
    // Opening also moves the auto-paste target: the app you open becomes frontmost, and
    // appActivated tracks whatever that is. Deliberately not special-cased — the rule is
    // "paste where you were last", and clicking back to your editor restores it — but a
    // stop issued while the transcript is still frontmost pastes there.
    @objc private func openTranscript(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(referenceString(for: [path]), forType: .string)
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    // MARK: Engine

    private func startEngine() {
        // Fresh log for this session (also tee'd here for debugging). A restart after a
        // mic switch appends to the same file instead of truncating it — what you open
        // last.log to read is usually whatever went wrong BEFORE the switch.
        if logHandle == nil {
            FileManager.default.createFile(atPath: logFilePath, contents: nil)
            logHandle = FileHandle(forWritingAtPath: logFilePath)
        } else {
            logHandle?.write(Data("\n--- engine restart on \(micDevice) ---\n".utf8))
        }

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
        p.terminationHandler = { [weak self] proc in
            let status = proc.terminationStatus
            DispatchQueue.main.async { self?.engineEnded(status: status) }
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
            let path = String(raw[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            transcriptPath = path
            if !transcriptPaths.contains(path) { transcriptPaths.append(path) }
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

        // The bar grows with the footer: as many cells as fit beside the text, between
        // 8 (still readable at ~300pt) and 24 (wider looked absurd spanning the strip). The engine sends 20
        // cells, so a wider bar is resampled — same level, finer drawing.
        let suffix = NSMutableAttributedString()
        suffix.append(NSAttributedString(string: " \(word)", attributes: [.font: statusFontBold, .foregroundColor: color]))
        suffix.append(NSAttributedString(string: " · \(chunks)", attributes: [.font: statusFont, .foregroundColor: Palette.dim]))
        let cellW = ("█" as NSString).size(withAttributes: [.font: statusFont]).width
        let capsW = ("▐▌" as NSString).size(withAttributes: [.font: statusFont]).width
        // Reserve a FIXED suffix width (the widest word, a 5-digit count), not this
        // update's: else the bar would jump a cell each time "sound"/"speech" swaps or
        // the count gains a digit.
        let reserveW = NSAttributedString(string: " speech · 99999", attributes: [.font: statusFontBold]).size().width
        let room = statusField.bounds.width - reserveW - capsW - 8   // 8: field padding
        let cellCount = min(24, max(8, cellW > 0 ? Int(room / cellW) : 8))
        let raw = plain[fillR]
        let filled = raw.isEmpty ? 0
            : Int((Double(raw.filter { $0 == "#" }.count) / Double(raw.count) * Double(cellCount)).rounded())
        let bar = "▐" + String(repeating: "█", count: filled)
                      + String(repeating: "░", count: cellCount - filled) + "▌"

        let s = NSMutableAttributedString()
        s.append(NSAttributedString(string: bar, attributes: [.font: statusFont, .foregroundColor: color]))
        s.append(suffix)
        statusField.attributedStringValue = s
    }

    // A line the app itself contributes to the scroll. Amber, never filtered by the
    // Debug checkbox, because it explains a discontinuity in the transcript around it.
    // Like appendError it bypasses `displayedRawLines`, so a Timestamps toggle drops it.
    private func appendNotice(_ msg: String) {
        append(NSAttributedString(string: msg, attributes: [.font: monoBold, .foregroundColor: Palette.amber]))
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
    //
    // Except when it never got going: a NONZERO exit with nothing transcribed is a
    // start-up failure — a mic name matching no device, a missing model, whisper-server
    // refusing to come up — and quitting there would close the one piece of UI that can
    // choose a different microphone. Go idle and leave the picker live instead. A clean
    // stop exits 0 (the engine catches KeyboardInterrupt), so this can't swallow one.
    private func engineEnded(status: Int32) {
        if restarting { return }   // a deliberate teardown for a mic switch; a new engine follows
        if status != 0, accumulated.isEmpty {
            enterIdle()
            return
        }
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
        statusField?.stringValue = "stopped"
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
            guard UserDefaults.standard.bool(forKey: "pref.autoEnter") else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { [weak self] in self?.terminateNow() }
                return
            }
            // Give the target time to take the paste before Return arrives. A large
            // bracketed paste into a terminal, or an Electron/web field, can still be
            // inserting when a back-to-back keystroke lands, and Return would then submit
            // a partial message. Re-check frontmost: if focus moved, don't press Return.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                if NSWorkspace.shared.frontmostApplication == app { self?.postReturn() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { [weak self] in self?.terminateNow() }
            }
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

    private func postReturn() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let ret: CGKeyCode = 0x24   // kVK_Return
        let down = CGEvent(keyboardEventSource: src, virtualKey: ret, keyDown: true)
        let up   = CGEvent(keyboardEventSource: src, virtualKey: ret, keyDown: false)
        // Clear flags explicitly: the combined source carries any modifier still held —
        // e.g. Alt from the Alt+Space stop — and Alt/Shift+Return means "newline, don't
        // send" in Claude Code and most chat apps.
        down?.flags = []
        up?.flags = []
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
        guard !cancelled, pasteEligible, !copyAsReference, !transcriptPaths.isEmpty,
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
        if useRef, !transcriptPaths.isEmpty { return copyReferenceToPasteboard() }
        return copyFullToPasteboard()   // full, or reference with an unknown path
    }

    // The text a full copy would place on the clipboard — the saved .txt files when
    // they're readable, else the in-memory accumulation, flowed into prose when
    // Timestamps is off. nil when there's nothing worth writing, so no caller can clobber
    // the clipboard with empty. Read twice per stop at most (the override probe, then the
    // copy); a once-per-session file read isn't worth caching around.
    private func fullTranscriptText() -> String? {
        var text: String?
        // Every file the session wrote, in order. A mic switch splits the transcript
        // across engine runs, and reading only the newest would silently drop everything
        // recorded before the switch. Empty ones (a run that died at start-up) drop out.
        let parts = transcriptPaths.compactMap { path -> String? in
            guard let s = try? String(contentsOfFile: path, encoding: .utf8),
                  !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return s.hasSuffix("\n") ? s : s + "\n"
        }
        if !parts.isEmpty { text = parts.joined() }
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

    // The `read <path>` form, one line per file. Shared with the Recent Transcripts
    // menu so a reference copied from history is byte-identical to one copied at stop —
    // both are pasted into the same place and must read the same there.
    private func referenceString(for paths: [String]) -> String {
        paths.map { "read " + ($0 as NSString).abbreviatingWithTildeInPath }.joined(separator: "\n")
    }

    // Short cross-device reference for when the full transcript overflows a chat
    // limit — ~/Cloud/... resolves on other devices since the folder syncs.
    @discardableResult
    private func copyReferenceToPasteboard() -> Bool {
        guard !transcriptPaths.isEmpty else { return false }
        // One `read` line per engine run: a mic switch splits the session across files,
        // and a reference naming only the last would point at half the transcript.
        let ref = referenceString(for: transcriptPaths)
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
