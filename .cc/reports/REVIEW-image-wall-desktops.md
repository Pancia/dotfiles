# Review: image-wall desktop autosave (commit 986180872a97)

Date: 2026-11-17
Scope: `cmd/image-wall/main.swift`, `cmd/image-wall/Makefile`, `install` (task_image_wall),
`bin/vpc.py` (launch_image_wall), `vpc/wallpapers.vpc`.
Method: read the diff and the surrounding code (Save to VPC, Reload, Add image, Remove image,
createWindows); built a copy in a scratch folder (clean, no warnings); probed
`SLSCopyManagedDisplaySpaces` read-only and compared it with `yabai -m query --spaces`;
round-tripped a copy of `wallpapers.vpc` through the same JSONSerialization path. The running
image-wall and `bin/image-wall` were not touched. No second instance was launched.

## Findings, most severe first

### 1. The "first sighting is only a baseline" guard does not protect anything (high confidence)

`main.swift:762-773` and `789-802`. `checkSpaces` only decides *whether* to save. When any
window changes desktop, `saveSpacesToVPC` writes `knownSpaces` for **every** window, not just
the one that moved. A window whose saved desktop was missing at launch has its fallback
desktop in `knownSpaces` (from its first sighting), so it is written out too.

Scenario: `sunflower.png` is saved with `"space": 12`. At launch only 8 desktops exist (a
desktop was removed, or a display is unplugged). `moveWindow` prints a warning and leaves it on
the active desktop, say 1. The baseline records 1. Later the user drags `lily.png` from desktop
2 to 3. `changed` becomes true, and the save writes `lily=3` and also `sunflower=1`. The saved
12 is lost, which is exactly the case the comment at 758-759 says is handled.

The same root cause also overwrites:
- an entry with no `"space"` key (it gains one, the desktop it happened to open on);
- a `"space"` value edited by hand in the file and not yet reloaded;
- any window whose `SLSMoveWindowsToManagedSpace` silently failed.

If the move at launch is applied asynchronously, the first poll may see a pre-move desktop for
some windows; the next poll then sees a "change" and saves, so this can fire with no user action
at all. I did not verify whether the move is asynchronous.

"Save to VPC" (`buildSnapshotEntries`, 498-500) also writes the live desktop, so it overwrites
the missing-desktop value too, but that is an explicit user action.

Fix: track which windows actually changed, and write only those. For example keep a
`dirtySpaces: Set<ObjectIdentifier>` set in `checkSpaces` when `old != space`, and in
`saveSpacesToVPC` only update file entries matched to a dirty window (still consuming
non-dirty windows from `pending` so duplicate matching stays aligned).

### 2. A change in the desktop list rewrites many entries at once (medium confidence)

`main.swift:49-67, 769`. The saved value is an index into the Mission Control order, and the
poll treats any index change as a move. When the list itself changes, many windows change
index without moving:
- a native fullscreen app creates a space inserted after the current desktop, shifting every
  later index by one;
- a display is unplugged and macOS moves its windows to the remaining display;
- a desktop is deleted or added in Mission Control.

Each of these makes the poll save shifted numbers. For a deleted desktop that is correct (the
window really is on the new index). For a fullscreen space it is transient: the numbers shift
back when the app leaves fullscreen and the next poll rewrites them. The harm is when the
process ends while the shift is in effect (reboot, logout, `killall` from vpc.py) and the next
launch happens without that fullscreen space: every window after it opens one desktop late, and
the highest one may point at a desktop that does not exist (which then feeds finding 1).

Verified: the SkyLight list and yabai's index list are identical here (13 desktops, one
display, same IDs and order), and `mru-spaces` is 0, so automatic reordering by recent use is
off. Not verified: I saw no fullscreen (type 4) space in the list, so the fullscreen shift is
inferred from how yabai and SkyLight number fullscreen spaces, not observed. Also not verified
with two displays.

Fix options: skip the save when the set of space IDs differs from the set seen on the previous
poll (record `orderedSpaceIDs()` alongside `knownSpaces`); or count only regular desktops
(`type == 0`) when building the index, so fullscreen spaces never shift numbers.

### 3. Duplicate paths plus an unsaved Remove or Add give a desktop to the wrong entry (medium confidence, low impact)

`main.swift:789-802`. Matching takes the first unmatched file entry with the same path. That is
only right while the windows list and the file list are in the same order with the same members.

Scenario: the file has two entries for `A` (desktop 2 at position p1, desktop 5 at position
p2). The user removes the first `A` window with "Remove image" and does not save. Any later
desktop change makes `pending = [(A, 5)]`, which is matched to file entry 0. The file now says
both entries are on desktop 5; at the next launch the removed window returns at p1 on desktop 5
instead of 2.

The same happens when a window has no `knownSpaces` value yet (it is left out of `pending`, so
the next duplicate shifts up), and when "Add image" re-adds a path whose only window was removed
(the new window's desktop goes onto the old, still-saved entry).

Fix: match by identity rather than path. Give each window the index of the file entry it came
from (set in `createWindows`, cleared on Remove, absent for added images), and update only that
entry. Reload and Save to VPC already rebuild that mapping.

### 4. Entries with an absolute path are never autosaved (high confidence, low impact)

`main.swift:791` vs `796`. The window side is normalised (`$HOME` substituted), the file side is
compared raw. `canvas.filePath` is `entry.path` exactly as written. An entry written by hand as
`/Users/anthony/Pictures/x.png` becomes `$HOME/Pictures/x.png` on the window side and never
equals the file's string, so its desktop is silently never saved. (Save to VPC writes `$HOME`
form, so this only affects hand-edited entries; the shipped file is all `$HOME`.) The plain
`replacingOccurrences` also rewrites a path such as `/Users/anthony2/...`; that pattern predates
this commit.

Fix: compare `canvas.filePath` to the file's `path` directly (they come from the same JSON), or
normalise both sides the same way.

### 5. Stale `ObjectIdentifier` keys across Reload (low confidence, low impact)

`main.swift:760, 1054-1057`. `knownSpaces` is keyed by object address and not cleared in
`doReload`. If an old window is freed in `windows.removeAll()` and a new window is allocated at
the same address, the new window inherits the old baseline and the guard in finding 1 is skipped
for it. The filter at 772 runs only on the next poll, after the new windows exist. The undo
manager is not purged on Reload, so old windows that have undo entries stay alive and mask this;
windows without undo entries may be freed. Fix: `knownSpaces.removeAll()` in `doReload`.

### 6. Autosave now writes a tracked repo file with no user action (high confidence, low impact)

`main.swift:808-811`. The config path vpc.py passes is `~/dotfiles/vpc/wallpapers.vpc`, a
tracked file. Every desktop move now rewrites it: keys sorted, `/` escaped, trailing newline
dropped (visible in this commit's diff), and any fractional number re-printed by
JSONSerialization. The round-trip test showed `0.3` written as `0.29999999999999999`. The shipped
file has no `volume` or `pan`, so nothing churns today, and Save to VPC already did all of this.
What is new is that it happens unprompted: the working copy changes while other Claude sessions
work in this repo, and `ccjj audit` reports a change no session owns. The atomic write also
replaces the file under any editor that has it open.

### 7. The `[]` collection behaviour changes app activation (unverified, low)

`main.swift:308-311`. With `[]` the windows belong to one desktop. image-wall uses the
`.regular` activation policy, so with the default "switch to a Space with open windows for the
application" setting, Cmd-Tab or a Dock click on image-wall can now jump to another desktop.
Actions from the status-item menu that activate the app (Add image runs a modal open panel) may
do the same when the current desktop has no image-wall window. This is a behaviour change, not
data loss. Not tested. The worklog that introduced `.moveToActiveSpace` (2026-03-10) gives no
reason for it, so nothing obvious depended on it.

Related, also unverified: window frames are computed from `NSScreen.main` (325-330). Moving a
window to a desktop on a second display keeps a main-screen frame, so it may land off-screen or
be clamped. Only one display is attached, so I could not test it.

### 8. vpc.py now discards all image-wall output (high confidence, low)

`bin/vpc.py:855-857`. `DEVNULL` for stdout and stderr hides every `print`, including
"desktop N does not exist", "Could not read VPC file to save desktops", "Could not write" and
"Could not find video". Those are the only signals when autosave or a launch fails. Detaching is
correct for the stated pipe problem; sending output to a log file (for example
`~/.log/image-wall.log`, opened in append mode) would keep both. `start_new_session=True` does
not affect the `killall image-wall` at 849, which matches by name.

### 9. Makefile and install (high confidence, low)

`install:100`, `cmd/image-wall/Makefile:6`. The old install line built with `-O`; the Makefile
has no optimisation flag, so `./install image-wall` now produces a debug build. Not a
correctness bug. `make` also skips the build when the committed `bin/image-wall` is newer than
`main.swift`, so a stale committed binary would not be rebuilt by install. The committed binary
does contain the new code (its strings include "Saved desktops"). The change itself is an
improvement: the old install line linked only AppKit and could not have linked the AVFoundation
code. `-F /System/Library/PrivateFrameworks -framework SkyLight` links correctly (built here; the
four `SLS*` symbols resolve to SkyLight).

## Checked and refuted

- SkyLight declarations: `SLSMainConnectionID` returns a 32-bit int, `SLSCopySpacesForWindows`
  takes `(int cid, int mask, CFArrayRef)`, mask 0x7 covers all space kinds, and
  `SLSMoveWindowsToManagedSpace` takes a 64-bit space ID. These match yabai's declarations.
- `ManagedSpaceID` equals `id64` for every space here and matches yabai's space IDs. The order
  matches yabai's index.
- `@_silgen_name` uses the Swift calling convention, not C. It works for these integer and
  pointer arguments, and the "Copy" functions return +1, which matches Swift's owned return, so
  there is no over-release or leak. A bridging header or `dlsym` with `@convention(c)` would be
  the supported route, but this is not a bug.
- Timer and observer lifetime: the run loop retains the repeating timer, the closure captures
  `self` weakly, and the delegate lives for the whole process. `activeSpaceDidChangeNotification`
  is posted on the NSWorkspace notification center, which is the one used.
- Autosave versus Save to VPC, Reload and Add image: autosave reads the file fresh and changes
  only `"space"` on matched entries, so it never writes unsaved positions, sizes, zoom, removals
  or added images. All paths run on the main thread, so there is no write race.
- Entries for missing files: they create no window, so they are never matched and keep their
  saved value.
