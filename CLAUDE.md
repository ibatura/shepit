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
- `make test` runs everything: Swift tests, installer and signing tests, accuracy tools. It must stay green (452 tests on 2026-11-12).
- `scripts/`: build, sign, install, uninstall, model downloads (pinned SHA-256 in `scripts/models/`).

## Docs

- `docs/future-ideas.md`: what comes next, and what was set aside and why. Read it before planning.
- `docs/superpowers/specs/`: designs. `docs/superpowers/plans/`: implementation plans of phases 1–3.
- `docs/manual-test-checklist.md`: manual checks on a real Mac and real calls.

## Where things stand (2026-11-12)

- Phases 1–3 are done: dictation, settings, statistics, meeting transcripts.
- Meeting names: Teams window title, Meet tab title or page bar, remembered names for repeats (`meeting-names.json`). Zoom shows no topic. Mute state is read from all three apps. Checked on real calls in each app.
- Open manual checks: M1, M4, M7, M9, M22 (M22 needs repeating meetings over weeks).
- Next, in this order unless the author says otherwise:
  1. Offer to record when a call starts: built on branch `call-offer`, not merged. A floating panel with the call's name and a Start button (`CallWatch` polls which app holds the microphone, `CallOffer` in `ShepitCore` decides, `CallPanel` shows it, `AppHost+Calls.swift` wires them); it starts on its own only with `callAutoStart` on. `Shepit call-watch` and `Shepit panel-test` are its debug commands. Manual checks C1–C10 passed (2026-11-13). Open: the author's end-of-branch reviews, then the merge.
  2. The main window, built in parts: shell with Home and Settings; Meetings (database, names, merge, reassign a line); Dictations and Dictionary; Statistics; voice prints; import names. The menu keeps quick actions only. The current UI was rejected; don't polish it piece by piece. A plan for each part first.
  The look and the screens are fixed in `docs/superpowers/specs/2026-11-11-visual-style/` (spec and `mockups.html`).
  Decisions and the build order are in `docs/future-ideas.md`.
- This repository (GitHub `ibatura/shepit`) is where work continues. The older copy with full history is on GitLab (`local-dictation-tool`); it is no longer updated.
