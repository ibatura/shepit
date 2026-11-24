# Main window, part 7 (Back and forward): implementation plan

**Goal:** ‹ and › at the top of the window, ⌘[ and ⌘], and a hint on hover take the author back and forward through the places they have been. A place is a section and what is chosen in it.

**Architecture:**
- **`BackForward<Step>`** (ShepitCore) is a pure value: visit, back, forward, look without moving, replace steps, and a cap of 50. It skips the steps a given test calls gone.
- **`WindowPlace`** (app) is a section and its choice:
  - the meeting or running transcript in Meetings;
  - the person in People;
  - the page in Settings.
- **`WindowNavigation`** already owns the section and the Settings page. It gets the history and the two models whose choices make a place: Meetings and People. It builds the place, applies it, goes back and forward, and gives the hints.
- **`MainView`** records a step whenever the place changes, and draws the arrows.

**Spec:** `docs/features/specs/2026-11-22-back-forward-design.md` ("the spec"; section numbers refer to it). Builds on `2026-11-13-window-shell-design.md` §4 (the sidebar and the title bar) and `2026-11-17-voices-design.md` §6 (People, a person's meetings).

**Branch:** `back-forward`. It was renamed from `next-part` and holds the docs commits of 2026-11-21 and 2026-11-22. When it is ready, ask the author whether to open the pull request; push the branch and open it only after they say yes. The author merges it in GitHub; Claude never merges.

## Execution notes

- **Style: Ponytail (full)** for every task (`~/.claude/skills/ponytail`): the smallest complete change, a test for every non-trivial branch, and no options nobody asked for.
- **Review per task:** check each task's diff against the Ponytail rules. Task 2 also gets `/code-review` on its diff: the place, the skipping and the running transcript.
- **Review at the end (Task 5):**
  - The author runs `/thermo-nuclear-code-quality-review` on the branch; only the author can start it.
  - Then `/code-review` and `/security-review` on the whole branch.
  - Show the findings to the author as a list; the author picks what to change.
- **One task at a time,** with a commit per task and a short message. `make test` must be green after each task (649 tests on 2026-11-20).
- **Tests first** for `BackForward`.
- **Test data:** tests use stores and notes in temporary folders and `UserDefaults` suites of their own, never `~/.local/share/dictation`, the author's meetings folder or Shepit's own preferences.
- **Settings:** the author's own `~/.config/dictation/settings.json` is not changed by code or tests.
- **Ask before installing:** it restarts Shepit, and a transcript may be running.
- **Author gates:** Task 3 (the arrows on the installed app) and Task 5.

## Global constraints

- **The history lives in memory only.** It is not written to `UserDefaults`, `settings.json` or a database. Closing the window keeps it, and quitting clears it.
- **One step per change of place.** A change made in one go is one step: Open in Meetings sets the section and the meeting together. Going back or forward makes no step.
- **Not part of a place:** the period, the Statistics view, the highlights and scrolling. Going back leaves them as they are.
- **Nothing is read from the store while drawing.** The hints and greyed arrows use the lists the sections have.
- **No new setting**, no network, no new permission.
- **Controls:** standard SwiftUI toolbar buttons and SF Symbols, with the English hint texts of spec §6.

## Review focus

1. **Exactly one step per change**, and none from going back or forward:
   - Open in Meetings, the recording card, and `MainWindow.show(section)` from the menu or the call panel;
   - a click on the section already shown.
   
   Tasks 2 and 3.
2. **Gone steps are skipped, never shown with nothing chosen** (Task 2):
   - a removed meeting;
   - a person merged in People;
   - a person who lost all their lines through an edit in Meetings while People's list was left behind.
3. **The running transcript:** its steps become the meeting's when it is added, and are skipped when it couldn't be added. Task 2.
4. **The cap:** 50 steps, the oldest dropped. Task 1.

## File structure

```
app/Sources/ShepitCore/
  BackForward.swift          new: the history of steps (Task 1)
app/Sources/Shepit/Window/
  MainWindow.swift           WindowPlace; WindowNavigation gets the history, place, apply, back, forward, hints;
                             meetingAdded replaces the running transcript's steps (Task 2)
  PeopleModel.swift          reloadIfChanged: the list again when the store changed since it was read (Task 2)
  MainView.swift             records a step on each change of place; the arrows, keys and hints (Task 3)
app/Tests/ShepitCoreTests/
  BackForwardTests.swift     new (Task 1)
app/Tests/ShepitTests/
  WindowNavigationTests.swift  new (Task 2)
```

`MainWindow.swift` has 177 lines now. If Task 2 takes it past about 300, move `WindowNavigation` and `WindowPlace` to a new `Window/WindowNavigation.swift`.

---

### Task 1: BackForward

- **Tests first** for `BackForward<Step: Equatable>` in ShepitCore:
  - **`visit(_:)`:**
    - the first visit makes the current step;
    - a visit equal to the current step does nothing;
    - any other visit puts the current step behind and drops the steps ahead.
  - **`back(alive:)` and `forward(alive:)`:**
    - each moves one step and returns the step it moved to, or nil at the end, without moving;
    - the current step goes to the other side, so back then forward returns to where you were.
  - **Gone steps:**
    - a step the `alive` test refuses is dropped, and the next one is taken, in both directions;
    - when every step in a direction is gone, it returns nil and drops them all;
    - the current step is never tested.
  - **`peekBack(alive:)` and `peekForward(alive:)`:** they return the step a move would reach and change nothing.
  - **`replace(_:with:)`:** every step equal to the first value becomes the second, behind, current and ahead.
  - **Cap:** after 52 visits, 50 steps lie behind and the first one is gone. The number is a constant with a comment pointing to spec §2.
- Implement `BackForward` in `app/Sources/ShepitCore/BackForward.swift`: an optional `current` and two arrays.
- Commit `Shepit: a history of steps for back and forward`.

### Task 2: The window's place and its history

- **`WindowPlace`** (an `Equatable` enum in the app):
  - `.section(WindowSection)` for Home, Dictations, Dictionary and Statistics;
  - `.meetings(MeetingsModel.Selection?)`;
  - `.people(Int?)`;
  - `.settings(SettingsModel.Section)`.
- **`WindowNavigation`**:
  - `init(meetings:people:defaults:)`, made in `MainWindow.init` instead of the property's default value. Its first step is the place it starts on, which comes from the remembered section and choices.
  - **`place`**: built from `section`, `settingsSection`, `meetings.selection` and `people.selection`. Only the choice of the section shown counts, so a change in Meetings' choice while People is shown is no step.
  - **`visit(_ place:)`**: forwards to the history.
  - **`back()` and `forward()`**:
    - first `people.reloadIfChanged()`, since edits in Meetings can leave People's list behind;
    - then move through the history with the alive test, and apply the step: set the section and the choice of that section, in one go.
  - **The alive test:**
    - a meeting is alive while it is in `meetings.meetings`;
    - a person while they are in `people.people`;
    - the running transcript while `meetings.live` isn't nil;
    - "nothing chosen" and the other sections are always alive.
  - **`canGoBack` and `canGoForward`**: peeks with the same test.
  - **`backHint` and `forwardHint`** use the peeked step, with the texts of spec §6:
    - the meeting's title as the list shows it, via `MeetingPage.title`;
    - the person's name from `people.people`;
    - the Settings page's name.

    With nothing to go to, the hint is "Back" or "Forward".
  - **`finished(running:)`**: replaces `.meetings(.running)` with `.meetings(.meeting(id))` in the history.
- **`MainWindow.meetingAdded`** calls `navigation.finished(running:)` before `sections.meetings.added(id)`. The place then equals the replaced current step, and no step is recorded.
- **`PeopleModel.reloadIfChanged()`**: reloads when the list was never read in this run, or when `store.version` differs from the version at the last `reload()`. The window can start on People and open on another section from the menu, so People's list may never have been read.
- **Tests** (`WindowNavigationTests`), on a temporary store with two meetings and named people, as `PeopleModelTests` builds them:
  - The place follows the section and its choice. A change of Meetings' choice while People is shown leaves the place as it is.
  - Visit People with Olena, then Meetings with meeting 2. `back()` gives People with Olena chosen, and `forward()` gives meeting 2 again.
  - Applying a step and visiting the place it gives records nothing: `canGoForward` stays true.
  - Remove meeting 1 through the model: a step to it is skipped.
  - Merge a person through `PeopleModel.merge`: Back skips them.
  - An edit in Meetings leaves a person with no lines while People's list was read before. Back skips them, because of `reloadIfChanged`.
  - The running transcript: after `finished(running:)`, Back reaches the meeting. Without it (the meeting couldn't be added, `live` nil), the running step is skipped.
  - Hints: "Back to People: Olena", "Forward to Meetings: <title>", "Back to Settings: Engines and models", "Back to Home", and "Back" with nothing to go to.
- `/code-review` on the task's diff.
- Commit `Shepit: the window's place, and back and forward through it`.

### Task 3: GATE: the arrows (with the author)

- **`MainView`** records with `.onChange(of: navigation.place) { navigation.visit($1) }` on the split view. One update that sets the section and the choice gives one change.
- **The arrows** go in `.toolbar { ToolbarItemGroup(placement: .navigation) { … } }` on the detail column:
  - two buttons, `chevron.left` and `chevron.right`;
  - `.disabled(!canGoBack)` and `.disabled(!canGoForward)`;
  - `.help(backHint)` and `.help(forwardHint)`;
  - `.keyboardShortcut("[", modifiers: .command)` and `.keyboardShortcut("]", modifiers: .command)`.
- **Check the look:** run `make test`, then ask before installing. On the installed app, check where the arrows sit (left of the section's name), in light and dark, and B1–B4 with the author.
- **If ⌘[ doesn't reach the buttons while a name field has focus,** tell the author before adding a menu item for it.
- Commit `Shepit: back and forward arrows in the window`.

### Task 3b: GATE: the sidebar collapsed to its icons (spec §10, with the author)

- **Render first.** A scratch test puts `MainView` in an `NSWindow` with today's style mask and captures the window's frame view (`cacheDisplay`) to a PNG in the scratchpad. Check where the window buttons, the sidebar button, the arrows and the title sit, full and collapsed, in light and dark. Delete the test before the commit.
- **`WindowNavigation.sidebarCollapsed`**: kept in `UserDefaults` under `sidebarCollapsed`. Extend `theWindowRemembersItsSections`.
- **`MainView`**:
  - an `HStack` of the sidebar list (190 pt, or about 52 pt collapsed), a `Divider` and the section, in place of `NavigationSplitView`;
  - the rows use `.labelStyle(.iconOnly)` and their name as `.help` when collapsed;
  - one toolbar: `ToolbarItemGroup(placement: .navigation)` with the sidebar button (`sidebar.left`, ⌃⌘S, a hint) and `BackForwardButtons`;
  - `.navigationTitle` stays the section's name.
- **`RecordingCard`**: collapsed, a red dot button with `.help` of the card's headline and detail.
- `make test`, then ask before installing; the author checks B10–B13 and picks the arrows' place.
- Commit `Shepit: a sidebar that collapses to its icons`.

### Task 4: Docs and version

- **README:** a line on the arrows and keys, after the line on the recording card.
- **`docs/manual-test-checklist.md`:** a "Main window: Back and forward" section with B1–B9 from spec §8.
- **`docs/future-ideas.md`:**
  - item 14 built on `back-forward`;
  - what is left, under a "Back and forward: left open" heading.
- **`CLAUDE.md`:**
  - "Where things stand": a bullet with how it fits together;
  - the Next list;
  - the test count.
- **Version:**
  - 0.3.0 (the author, 2026-11-22);
  - raise `CFBundleShortVersionString` in `app/Resources/Info.plist`;
  - write `docs/releases/<version>.md`.
- Commit `Docs: back and forward; version <version>`.

### Task 5: GATE: the author's checks and reviews

- **Manual checks:** the author goes through B5–B9 on the installed app.
- **Reviews:**
  - the author runs `/thermo-nuclear-code-quality-review`;
  - then `/code-review` and `/security-review` on the branch;
  - the findings go to the author as a list, and the author picks what to fix.
- **Pull request:** ask the author whether to open it. Its description says what changed and how it was checked.

## Open questions to raise when the task starts (not blockers)

- **Task 3:** if the toolbar puts the arrows somewhere other than left of the title (the sidebar toggle shares the area), show the author before moving them.

## Changed after the plan (2026-11-22)

- **Task 2, the alive test asks the store, not the sections' lists.** The lists are read only when a section appears, so they can be behind in three ways:
  - a meeting added while Meetings wasn't shown (the running transcript's steps become it);
  - a list never read in this run (the window opened on another section from the menu);
  - People's list after an edit in Meetings.

  `PeopleModel.reloadIfChanged` would have covered only the last. So instead:
  - a meeting step is alive while `store.meeting(id)` finds it;
  - a person step while the new `MeetingStore.lists(person:)` says People lists them (a line in some meeting, as `summaries` counts);
  - the running transcript while `meetings.live` isn't nil.

  These are single-row reads, made for the arrows' state and hints too. The hints take a person's name from People's list, and say just "People" while the list is unread.
- **After the thermo-nuclear review (2026-11-22; the author picked all six points):**
  - `WindowNavigation` moved to its own file and records changes of place itself, so the tests change state and check the history, without calling `visit`.
  - The sections describe their own choices: `MeetingsModel.describe`, `PeopleModel.describe`. A person's name now comes from the store, You's from the settings.
  - `MeetingStore.listed(person:)` replaces `lists(person:)` and shares its condition with `summaries`.
  - In `MainView`: one `SectionList` for both sidebars; `RecordingCard` lost its mode flag to a separate `RecordingDot`; the sidebar button joined the arrows in `WindowButtons`.
- **After `/code-review` (2026-11-22; the author picked all five):**
  - A running transcript that ends without becoming a meeting loses its steps: `finished(running:)` takes nil, and `onFinished` calls it on every way out. Before, the steps came back to life with the next transcript.
  - `BackForward` skips a step equal to the current one, which a gone step between them can leave next to it; Back no longer "goes" to where the window already is.
  - A sidebar collapsed or opened by dragging its divider keeps the list's focus too.
  - A doubled `await` in a test, and CLAUDE.md's import-names checks.
