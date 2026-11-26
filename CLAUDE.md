# Shepit: notes for Claude

Shepit is a macOS menu-bar app: local dictation (Ukrainian and English) and meeting transcripts for Teams, Zoom and Google Meet. User docs are in `README.md`.

## Read first

- **`docs/process.md`**: how every change is made: spec, plan, tasks, the agents that review plans and code, pull request, release. Read it before planning or building. The agents it asks for are the author's request.
- **`docs/architecture.md`**: how the code fits together, part by part. Read the part you are changing.
- **`docs/future-ideas.md`**: what comes next ("Next"), the build order, what was left open and set aside. Read it before planning.

## Working with the author

- Reply in Ukrainian. Messages are often dictated, so they can contain spoken self-corrections («…через Meet. Ой, через Teams»): follow the corrected intent.
- Write code, comments, commits and docs in plain English.
- Work on a branch of its own; never commit to `main`. Commit each finished change with a short message that says what changed and why, ending with the `Co-Authored-By` line the session gives.
- Ask before opening a pull request and before installing (`scripts/install.sh` restarts Shepit, and a transcript may be running). Never merge: the author merges in GitHub.

## Rules

- **Everything stays local.** No network except model downloads the user asked for. No cloud services, no sign-in.
- **Never default user data to iCloud** or another synced folder, even though the author's Obsidian vault is there. Every new output gets a path setting in `settings.json` with a local default under `~/.local/share/dictation/`. Exception: SQLite databases (`stats.sqlite`, `meetings.sqlite`, `dictations.sqlite`) share one setting, `databasesFolder` (default `~/.local/share/dictation`); a new database goes there and gets no setting of its own.
- **Call content is confidential work material.** When checking a real meeting note or transcript, report only counts and short fragments, never whole passages.
- The author's own `~/.config/dictation/settings.json` is not changed by code or tests.
- Security and privacy settings (Accessibility, Microphone, System Audio Recording) are changed by the user, not by scripts.
- macOS ties Accessibility to the signing certificate: never create a new "Shepit Local Signing" certificate when one exists (`scripts/signing.sh`).

## Code

- SwiftPM package in `app/`: `ShepitCore` (pure logic with tests), `ShepitEngines` (the speech engines), `Shepit` (the app). Details in `docs/architecture.md`.
- `make test` runs everything: Swift tests, installer, icon and signing tests, accuracy tools. It must stay green (682 Swift tests on 2026-11-26).

## Now (2026-11-26)

- The settings review is merged into `main` (2026-11-24, release `v0.4.0`); its manual checks R6–R8 are open.
- The query plans are merged into `main` (2026-11-25, release `v0.4.1`): every query of `meetings.sqlite` on an index (version 3), May also be in and the forgetting of old voices off the main thread.
- Branch `icon-and-name` (2026-11-26), version 0.4.2: the app icon H1 (the menu bar's rhombus in convex bars, black to red, on linen), compiled from `app/Resources/AppIcon.icon` by `scripts/build-icon.sh`, and the rhombus in the menu bar in every state. Spec `docs/features/specs/2026-11-25-icon-and-name-design.md`, plan `docs/features/plans/2026-11-26-icon.md`; manual checks G1–G5 pass. The name is set aside (Amergin for now), and SPT's letter logo with it.
- What comes next: "Next" in `docs/future-ideas.md`.
- This repository (GitHub `ibatura/shepit`) is where work continues. The older copy on GitLab (`local-dictation-tool`) is no longer updated.
