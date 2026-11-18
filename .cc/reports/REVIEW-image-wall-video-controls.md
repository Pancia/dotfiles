# Review: image-wall video playback controls (uncommitted change, 2026-11-17)

File: `cmd/image-wall/main.swift`. Line numbers are those of the working copy at review time.

## Verdict

Nothing serious. I found no crash, leak, retain cycle or AVFoundation misuse in the new code.
The findings below are all low severity. The first one is the only one a user is likely to notice.

Each finding says how it is known:

- **proven**: a test driver built from main.swift (minus its `// MARK: - Main` section) showed it.
- **code**: read from the code, not run.
- **unverified**: likely, but not tested.

## Findings, most severe first

### 1. Play from a menu starts a covered or sleeping video (proven, low)

`togglePause()`, main.swift:328-332, calls `player.play()` directly when it clears `userPaused`.
It skips the occlusion and screen-sleep rules in `AppDelegate.updatePlayback` (main.swift:1057).

Scenario: a silent video is fully covered, so occlusion paused it. The user pauses it and later picks
Play from its status-bar submenu. The video plays while covered, and it keeps decoding until the next
occlusion change. The driver showed this: after `pause()` then `togglePause()`, time advanced 0.6 s.

Fix: route the unpause through the delegate, which already knows about occlusion and sleep.

```swift
func togglePause() {
    userPaused.toggle()
    if userPaused {
        player.pause()
    } else if let w = window as? WallWindow, let d = NSApp.delegate as? AppDelegate {
        d.updatePlayback(for: w)   // plays only if visible (or audio on) and the screen is awake
    } else {
        player.play()
    }
    refreshControls()
}
```

### 2. Holding k, space or 0 repeats the action (code, low)

`WallWindow.keyDown`, main.swift:525-546, does not check `event.isARepeat`.
If you hold space or k a little too long, pause toggles at the key-repeat rate, so the video flickers
between play and pause and stops in a random state. Holding 0 keeps restarting.
Repeat is right for j, l, the arrows, `,` and `.`.

Fix: `if event.isARepeat { return }` before the toggle and restart cases only.

### 3. A drag that starts on a time label moves the window with no undo step (partly proven, low)

The comment on `ControlsBarView` (main.swift:178) says a click on the bar neither drags the window nor
saves an undo step. That holds for the bar background, the button and the slider. It does not hold
for the two time labels. The driver showed that a hit on the elapsed label returns the `NSTextField`,
and that its `mouseDownCanMoveWindow` is `true` (the bar, button and slider return `false`).

Inferred, not tested with a real mouse: on an unlocked window, a drag from a label moves the window,
because the window is movable by its background. The label's `mouseDown` goes up the responder chain
to `ControlsBarView.mouseDown`, which swallows it. So `WallWindow.mouseDown` never saves the undo step,
and Cmd-Z cannot undo that move.

Fix, either one:

- Make the labels a small `NSTextField` subclass with `mouseDownCanMoveWindow` returning `false`.
- Or override `ControlsBarView.hitTest` to return the bar itself when the hit is a label.

### 4. A seek before the item is ready is dropped, and a failed item keeps live controls (proven, low)

`seek(to:)` (main.swift:335) does not check `player.currentItem?.status`.

- A seek issued right after launch or Reload, before the item is ready, is silently lost.
  The driver called `seek(by: 10)` at once. One second later the time was 0.84 s, not about 10.8 s.
  The completion still ran, so `pendingSeek` did not go stale. For a local file the window is short.
- `videoExtensions` includes webm, mkv and avi, which AVFoundation usually cannot play. Such an item
  fails, and the window stays black. The menu still enables Pause, Back, Forward and Restart.
  They do nothing. There is no exception and no crash: the driver tried this with a file that is not a
  video. The Position slider is already disabled, because `durationSeconds` is nil.

Fix, optional: disable the playback items when `durationSeconds == nil`, as the Position slider does.

### 5. Status-bar submenus repeat unmodified key equivalents (unverified, low)

`playbackItem` (main.swift:1184-1195) gives k, j, l and 0 with an empty modifier mask. The status-bar
menu builds the same items for every video submenu (main.swift:1125). While that menu is open, a
typed k or j probably fires the first video's item, not type-select. The hints are also wrong there:
the keys work only while that video's window is key.

The driver showed that the right-click menu kept in `canvas.menu` is not checked for key equivalents
(`win.performKeyEquivalent` with an `l` event returned false, and the time did not move). So
there is no double-fire when the window has focus.

Fix: show the key hints only in the right-click menu. For example, pass a flag to
`addImageMenuItems`, or set `keyEquivalent = ""` when building the status submenus.

### 6. Very small items (code, very low)

- `controlScrub` (main.swift:459-465) returns at `guard let d = durationSeconds` before it resets
  `isScrubbing`. If the duration were nil at mouse-up, the slider would stop following playback until
  the next click. A loaded item does not lose its duration, so this is theory. Fix: reset
  `isScrubbing` before the guard.
- `layoutControls` (main.swift:425-436): the bar is at least 140 pt wide and 44 pt from the bottom.
  A window narrower than about 164 pt clips it at both sides, and one shorter than 44 pt clips its
  top. This is cosmetic only.
- On a video shorter than 10 s, Forward 10 Seconds lands at `(t + 10) mod d`, which looks random.
  This is the documented wrap. It is not a bug.

## Checked and found correct

- **Step during an in-flight seek.** `seek(to: 10)` then `step(frames: 1)` at once ended at
  10.033 s. The step applies after the seek; it is not lost.
- **Step at the loop end.** It stops at exactly the duration (30.0 s) and stays there. Play then
  loops normally to the next item, and `seek(by: -5)` from there gives 25.0 s.
- **Clamp and wrap.** Back clamps at 0. Forward wraps (25 + 10 gave 5 on a 30 s clip). Playing past
  the loop and seeking back works.
- **Rapid seeks.** Back-to-back `seek(by:)` calls accumulate correctly. "0, 0, l" from 15 s gave 10 s.
- **Time observer.** It is added in `buildControls`, removed in `teardownControls` and `deinit`, and
  always on the same player. Its closure captures `self` weakly. The seek completion is weak and hops
  to main. The button and slider targets are weak (AppKit). The new code adds no retain cycle.
- **Responder chain.**
  - A click on the slider or button does not take keyboard focus, even with Full Keyboard Access on.
    The firstResponder stayed the window, so arrows and space still reach `WallWindow.keyDown`.
  - Both controls accept the first mouse.
  - Right-click and scroll on the bar fall through the responder chain to the canvas.
  - Cmd, Ctrl and Opt keys pass to `super`, so Cmd-Z still reaches the main menu.
- **Slider click.** A click in the middle of the slider seeked to 15.0 s exactly. The drag is
  inexact; the mouse-up seek is exact.
- **Zoom, pan and undo.** The player layer still uses the canvas bounds. The bar is a sibling view,
  so zoom and pan do not move it. Undo and redo call `applyZoomAndPan`, which is unchanged.
- **Reload and remove.** These pause the player as before. New windows start with `userPaused` false
  and the controls hidden.

## Existing problem the change extends (not introduced)

Each item in `canvas.menu` holds the canvas strongly through `representedObject`. The audio item, the
zoom items and Remove Image already did this. So after the first right-click, a `VideoCanvasView` never
deallocates, even after Remove Image or Reload, and the new `deinit` (main.swift:242) never runs.
Today this costs only memory and a paused player. A removed window's time observer stays registered,
but it does not fire while the player is paused. To fix it, clear `canvas.menu` (or its items) in
`doRemoveImage` and `doReload`, or use a weak box for `representedObject`.

## Simplifications (lower priority)

- **`pendingSeek` is mostly redundant.** The driver showed that `player.currentTime()` reports the
  new target one run-loop turn after `seek` (under 2 ms), whether playing or paused. Each real key
  event is a separate turn, so `currentSeconds` already reads the last target. `pendingSeek` helps
  only for calls in the same turn, which happen in tests, not in use. It does no harm.
  - Its known race is harmless for the same reason. Two seeks to the same target let the cancelled one
    clear it early, but `currentSeconds` is already correct by then.
  - Keep it or drop it. If you keep it, `refreshControls` could show `pendingSeek ?? currentSeconds`.
    That removes the tiny chance of the slider thumb jumping back on mouse release.
- **One helper for drag detection.** `controlScrub` (main.swift:461-462) and `doSliderPosition`
  (main.swift:1492-1493) test the same "is this a left-mouse drag" condition. A helper such as
  `isMouseDrag(NSApp.currentEvent)` would keep them the same.
- **`refreshControls` work.** It sets the button image and tint every 0.25 s. They change only on a
  pause toggle, so they could be set in `togglePause` and `step` alone. The cost is trivial.
