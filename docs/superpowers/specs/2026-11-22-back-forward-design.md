# Main window, part 7: Back and forward

Date: 2026-11-22
Status: Approved by the author on 2026-11-22, with the decisions in §2.
Build order: item 14 in `docs/future-ideas.md` ("Planned, in this order"), moved first by the author on 2026-11-22. Branch `back-forward`. The version is agreed with the author before the pull request.
Builds on: `2026-11-13-window-shell-design.md` ("the shell spec": the sidebar, the title bar shows the section's name, window state is in the app's preferences), `2026-11-14-meetings-design.md` (Meetings, the running transcript) and `2026-11-17-voices-design.md` (People, a person's meetings).

## 1. Intent

A click on a meeting in People opens it in Meetings, and there is no way back to that person. Shepit gets arrows at the top of the window, as a browser or Finder has. Each section is a step, and so is the meeting or person chosen in it. Back goes to the step before, and Forward undoes a Back.

## 2. Decided by the author (2026-11-22)

- **A step is a section and what is chosen in it**:
  - the meeting chosen in Meetings, or the running transcript;
  - the person chosen in People;
  - the page chosen in Settings.

  Each choice is a step, as in a browser: three meetings clicked one after another are three steps. These are not steps: the period, the Statistics view (Overview, Dictation, Meetings), highlighted people, Only highlighted people, and scrolling.
- **Controls**: ‹ and › at the top of the window, ⌘[ and ⌘], and a hint on hover that says where the arrow goes ("Back to People: Olena K."). There are no mouse side buttons and no swipe.
- **A step to a meeting or person that is gone** is skipped. A meeting is gone when it was removed from the list or its file was moved to the Trash. A person is gone when it was merged into another or is no longer in People.
- **The history lasts while Shepit runs.** Closing the window keeps it, and quitting Shepit clears it. It holds up to 50 steps.

## 3. Goals, non-goals, anti-goals

**Goals.** After any jump inside the window, Back returns to where you were. These are the jumps:
- Open in Meetings from People;
- All dictations and Download models… on Home;
- the History and privacy link in Dictations and Statistics;
- the recording card;
- a section opened from the 🎙 menu or the call panel.

**Non-goals.**
- A list of steps on a long press or right-click, as Finder has.
- Going back to a period, a scroll position or a Statistics view.
- Mouse side buttons and swipes. The author didn't pick them, and a two-finger swipe would conflict with scrolling tables and charts sideways.

**Anti-goals.**
- History written to disk or to `settings.json`.
- A step for every keystroke, filter or highlight.

## 4. Steps

A **place** is one of these:
- Home, Dictations, Dictionary or Statistics;
- Meetings, with the running transcript, a meeting, or nothing chosen;
- People, with a person or nothing chosen;
- Settings, with its page.

**Every change of place is a new step**, whoever makes it:
- a click in the sidebar or a list, or ↑↓ in a list;
- the links listed in §3;
- the recording card;
- Open Shepit and Settings… from the 🎙 menu;
- the call panel;
- Merge into… in People, which chooses the person merged into.

**More rules:**
- **A change made in one go counts once.** Open in Meetings sets the section and the meeting together, so it makes one step.
- **The place the window opens on at launch** (the remembered section and choice) is the first step.
- **A new step after Back** drops the steps ahead, as in a browser.
- **The running transcript is a step of its own.** When it finishes and becomes a meeting, its steps become that meeting's, so Back never lands on Meetings with nothing running. The finished meeting already stays chosen today (`MeetingsModel.added`).
- **With 50 steps**, the oldest one goes.

## 5. Going back and forward

- **Back** shows the step before: its section, with its meeting, person or Settings page chosen. Everything else in that section stays as it is now: the period, the view and the highlights.
- **Forward** does the same with the step ahead.
- **Going back or forward makes no step of its own.**
- **A step whose meeting or person is gone** is dropped from the history, and the next step in that direction is taken. When no step is left in a direction, its arrow is greyed out.
- **Closing the window** keeps the history. Open Shepit returns to the last place, as today, with the history intact. A menu item that opens a section, such as Settings…, adds a step.

## 6. Controls

- **‹ and ›** are on the left of the title bar, before the section's name, as in System Settings and Finder: SF Symbols `chevron.left` and `chevron.right`.
- **⌘[ and ⌘]** work wherever the focus is in the window, also in a list or a name field. A name field that loses focus this way saves as it does today: each change names its meeting.
- **The hint on hover** says where the arrow goes, with the name the list shows now:
  - "Back to People: Olena K."
  - "Forward to Meetings: Daily sync"
  - "Back to Meetings: the running transcript"
  - "Back to Settings: Engines and models"
  - "Back to Home"

  It skips gone steps, as the arrow does. With nothing to go to, the hint is just "Back" or "Forward". Hints show after 0.25 s, the delay set in v0.2.0.

## 7. Structure

- **`BackForward<Step: Equatable>`** (ShepitCore) is a pure value:
  - visit a step; a visit equal to the current step does nothing;
  - go back or forward, skipping the steps a given test calls gone;
  - look at the step back or ahead without moving, for the hints and the greyed arrows;
  - replace steps, for the running transcript that became a meeting;
  - drop the oldest step after 50.

  It has tests of its own.
- **`WindowPlace`** (in the app, `Window/`) is built from four values: `WindowNavigation.section`, `settingsSection`, `MeetingsModel.selection` and `PeopleModel.selection`. Applying a place sets them.
- **`WindowNavigation`** already owns the section and the Settings page, and now owns the history too, in memory.
- **Steps are recorded in one place**: `MainView` watches the place and visits it on each change. Going back sets the place, and that visit is equal to the current step, so nothing is recorded. Nothing in the sections changes to record steps.
- **The arrows** are a toolbar item of the window's detail column. The names in the hints come from the Meetings list and the People list.
- **Whether a meeting or person still exists** is decided in the plan: from the sections' lists, or from the store, since People reads its list only when the section appears.
- Nothing changes in `settings.json`, the databases or the notes.

## 8. Tests and manual checks

**Tests:**
- `BackForward`:
  - visit;
  - back and forward;
  - a new visit drops the steps ahead;
  - a visit equal to the current step;
  - the 50-step cap;
  - gone steps skipped in both directions and dropped;
  - looking without moving;
  - replacing steps.
- In the app:
  - a place from the window's state and back;
  - Open in Meetings is one step;
  - going back records nothing;
  - after Merge into…, Back skips the merged person;
  - the running transcript's steps become the meeting's.

**Manual checks**, B1–B9 in `docs/manual-test-checklist.md`:
- **B1:** in People, choose a person and click Open in Meetings on one of their meetings. ‹ returns to People with that person.
- **B2:** › returns to the meeting.
- **B3:** ⌘[ and ⌘] do the same, also with the focus in the meetings list or in a name field.
- **B4:** the hint on each arrow names where it goes.
- **B5:** remove a meeting from the list. Back skips it.
- **B6:** merge a person into another. Back skips the merged one.
- **B7:** close the window and open it again from the 🎙 menu: the arrows still work. Quit and launch Shepit: both arrows are greyed out.
- **B8:** while in Meetings, choose Settings… in the 🎙 menu. ‹ returns to Meetings.
- **B9:** click the recording card, then go somewhere else. After Stop, ‹ leads to the finished meeting, not to an empty Meetings.

## 9. My calls (not confirmed one by one)

- The arrows sit left of the section's name in the title bar, as in System Settings.
- A click on the section already shown makes no step, since the place doesn't change.
- Merge into… choosing the other person is a step, because the place changes. Back from it skips the merged person.
- ↑↓ through the meetings list makes a step for each meeting, which follows "each choice is a step".
- ⌘[ and ⌘] belong to the arrows, not to a menu: the app menu has no Go menu, and one isn't needed for two keys.
