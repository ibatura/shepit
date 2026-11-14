# Shepit: notes for Claude

Shepit is a macOS menu-bar app: local dictation (Ukrainian and English) and meeting transcripts for Teams, Zoom and Google Meet. User docs are in `README.md`.

## Working with the author

- Reply in Ukrainian. Messages are often dictated, so they can contain spoken self-corrections («…через Meet. Ой, через Teams»): follow the corrected intent.
- Write code, comments, commits and docs in plain English.
- Commit each finished change. End commit messages with the `Co-Authored-By` line the session gives.
- Ask before pushing, and before merging into `main`.
- Install the app with `scripts/install.sh` to try a change.

## Rules

- **Everything stays local.** No network except model downloads the user asked for. No cloud services, no sign-in.
- **Never default user data to iCloud** or another synced folder, even though the author's Obsidian vault is there. Every new output gets a path setting in `settings.json` with a local default under `~/.local/share/dictation/`.
- **Call content is confidential work material.** When checking a real meeting note or transcript, report only counts and short fragments, never whole passages.
- The author's own `~/.config/dictation/settings.json` is not changed by code or tests.
- Security and privacy settings (Accessibility, Microphone, System Audio Recording) are changed by the user, not by scripts.
- macOS ties Accessibility to the signing certificate: never create a new "Shepit Local Signing" certificate when one exists (`scripts/signing.sh`).

## Code

- SwiftPM package in `app/`:
  - `ShepitCore`: pure logic with tests (settings, dictionary, meeting session and notes, meeting names, language choice).
  - `ShepitEngines`: whisper.cpp, WhisperKit, Parakeet, Apple Speech.
  - `Shepit`: the app (menu, hotkeys, overlay, audio, call tap, Accessibility scan of meeting apps in `MeetingApps.swift`).
- `make test` runs everything: Swift tests, installer and signing tests, accuracy tools. It must stay green (486 Swift tests on 2026-11-14).
- `scripts/`: build, sign, install, uninstall, model downloads (pinned SHA-256 in `scripts/models/`).

## Docs

- `docs/future-ideas.md`: what comes next, and what was set aside and why. Read it before planning.
- `docs/superpowers/specs/`: designs. `docs/superpowers/plans/`: implementation plans of phases 1–3.
- `docs/manual-test-checklist.md`: manual checks on a real Mac and real calls.

## Where things stand (2026-11-14)

- Phases 1–3 are done: dictation, settings, statistics, meeting transcripts.
- Meeting names: Teams window title, Meet tab title or page bar, remembered names for repeats (`meeting-names.json`). Zoom shows no topic. Mute state is read from all three apps. Checked on real calls in each app.
- Open manual checks: M1, M4, M7, M9, M22 (M22 needs repeating meetings over weeks).
- The offer to record when a call starts is done and merged into `main` (2026-11-13): a floating panel with the call's name and a Start button (`CallWatch` polls which app holds the microphone, `CallOffer` in `ShepitCore` decides, `CallPanel` shows it, `AppHost+Calls.swift` wires them); it starts on its own only with `callAutoStart` on. `Shepit call-watch` and `Shepit panel-test` are its debug commands. Manual checks C1–C10 and the author's three end-of-branch reviews are done (2026-11-13). What the reviews left open is in `docs/future-ideas.md` under "Call offer: left open"; the mute check in Zoom and Meet is the first of them.
- The main window shell is done and merged into `main` (2026-11-14): one window with a sidebar (Home, Dictionary, Statistics, Settings; Meetings, Dictations and People are placeholders), a Dock icon only while it is open, the menu cut to quick actions, the meeting hotkey, theme and accent colour. Spec `docs/superpowers/specs/2026-11-13-window-shell-design.md`, plan `docs/superpowers/plans/2026-11-13-window-shell.md`. The three end-of-branch reviews are done and their findings fixed; the author clicked through the window on the installed app (W1–W10 not checked one by one). What is left open is in `docs/future-ideas.md` under "Window shell: left open".
  - How it fits together: `AppHost.snapshot()` builds an `AppSnapshot` (ShepitCore) from live state plus cached `Lookups` (devices, downloads, history, permissions; gathered when the menu or window opens and by the 2-s poll). `MenuModel` builds the menu and `HomeModel` builds Home from it; `MainWindow` pulls Home through a closure. Actions are `AppAction`. Window code: `app/Sources/Shepit/Window/` and `AppHost+Window.swift`.
- Next, in this order unless the author says otherwise:
  1. The main window's next part: **Meetings** (database, names, merge people, give a line to another person). A spec and a plan first, then the build. After it: Dictations and Dictionary; Statistics; voice prints; import names. The current UI was rejected; don't polish it piece by piece. A plan for each part first.
  The look and the screens are fixed in `docs/superpowers/specs/2026-11-11-visual-style/` (spec and `mockups.html`).
  Decisions and the build order are in `docs/future-ideas.md`.
- This repository (GitHub `ibatura/shepit`) is where work continues. The older copy with full history is on GitLab (`local-dictation-tool`); it is no longer updated.
