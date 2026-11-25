# How we work on Shepit

How every part of Shepit is made, from an idea to a release. `CLAUDE.md` links here; read this before planning or building. The process lives in this file only: plans and memory point here instead of copying it, and a change to the process is made here.

The author decides three things: what is built (the spec), how it looks (the gates) and what is fixed after a review. Claude does the rest.

```
idea → future-ideas.md → spec → plan → plan review → branch → tasks (each reviewed) → docs and version → end-of-branch reviews → pull request → the author merges → release
```

## 1. Ideas

- Every idea of the author's goes to `docs/future-ideas.md` under "New ideas", with its date, even when it is not for now.
- The build order is its "Planned, in this order" list and "Next" there. Read it before planning.
- What is set aside goes under "Set aside", with why. What a finished part leaves goes under "<Part>: left open".

## 2. Spec

`docs/features/specs/<date>-<name>-design.md`, one per part.

- **How it is made:** questions to the author in rounds, with drawings where the look matters (the look: `docs/features/specs/2026-11-11-visual-style/`). Claude marks the option it recommends; every answer is written down as the author's, with its date.
- **Sections:**
  - A header: date, status, place in the build order, the specs it builds on.
  - 1 Intent: what is wrong now and what the part changes.
  - 2 Decided by the author: each decision, "recommended" where the author took Claude's proposal.
  - 3 Goals, non-goals, anti-goals.
  - One section per area of the part.
  - Structure: what goes in `ShepitCore` and what in the app.
  - Tests and manual checks.
  - My calls (not confirmed one by one): what Claude decided alone, so the author can overrule it.
  - The state today, when the part changes something that exists.
- **Status:** first draft → complete, for the author's approval → "Approved by the author on <date>". A commit at each step.

## 3. Plan

`docs/features/plans/<date>-<name>.md`, written after the spec is approved.

- **Sections:** Goal; Architecture; Spec (sections cited as §N); Branch; Execution notes (only what this part adds to this file: risky tasks, gates, its test data); Global constraints; Review focus (the 3–4 places a mistake is most likely); File structure; Tasks; Open questions (asked when the task starts, not blockers); Progress.
- **Tasks:** plain bullets, no checkboxes. Each says its tests (first, for logic in `ShepitCore`), the change and its commit message. A **GATE** task ends with the author looking at the installed app.
- **Progress** is the plan's state: per finished task, its date and commits, what came out differently from the plan, and the author's words at a gate.

### Plan review

Once the plan is written, before the author reads it:

1. Claude spawns two agents at the same time (§7): the **critic** and the **improver**, each with the spec and the plan.
2. Their findings come back to the main session. Claude decides on each: take it into the plan, or leave it, and why.
3. Claude shows the author both lists with those decisions, and the plan as changed.
4. The author reviews the plan last. The build starts after their OK.

## 4. Build

On a branch of its own (never on `main`), one task at a time:

1. **Tests first** for logic in `ShepitCore`.
2. **Ponytail (full)** (`~/.claude/skills/ponytail`): the smallest change that does the whole task.
3. **`make test` green.**
4. **Task review:** Claude spawns the task reviewer (§7) on the task's diff. Its findings come back to the main session, and Claude fixes them there; a finding left unfixed goes in Progress with why. `make test` again.
5. **A commit per task** with a short message that says what changed and why, and a Progress line.
6. **At a GATE:** ask before installing (`scripts/install.sh` restarts Shepit, and a transcript may be running), install, and the author looks. Their remarks are fixed in the same task, before the next one.

**Test data** lives in temporary folders and `UserDefaults` suites of its own: never `~/.config/dictation`, `~/.local/share/dictation`, the author's meetings folder or Shepit's own preferences. The author's `settings.json` is not changed by code or tests.

## 5. End of branch

1. **Docs:** the README; `examples/settings.json` when keys changed; the part's manual checks in `docs/manual-test-checklist.md`; `docs/future-ideas.md` (the item built, "<Part>: left open"); the part in `docs/architecture.md`; "Now" in `CLAUDE.md`.
2. **Version:** agreed with the author; `CFBundleShortVersionString` in `app/Resources/Info.plist` and the notes in `docs/releases/<version>.md`.
3. **Reviews of the whole branch** (`git diff main...HEAD`), in this order:
   1. Once the docs and the version are done, Claude spawns the **code reviewer** and the **security reviewer** (§7) at the same time, without waiting to be asked.
   2. When both have reported, Claude writes its opinion on each finding (fix it or leave it, and why) and shows the author one numbered list, by review, most severe first. The author picks; Claude fixes what was picked, runs `make test` and commits.
   3. Last, the author runs `/thermo-nuclear-code-quality-review`; only the author can start it. Its points go the same way: Claude's opinion on each, the author picks, Claude fixes.
4. **Manual checks of the branch:** each one is marked ✅ or ❌, or moves to "Need to test later" with its reason, or is removed with the author's OK.

## 6. Pull request and release

- Claude asks "open the PR?" and pushes the branch and opens it only after the author's yes. The description has **What changed** and **How it was checked** (tests, the reviews and what the author picked, the manual checks passed and those still open).
- The author merges in the GitHub web UI. Claude never merges: not with `gh`, the API or locally, and doesn't offer to.
- `.github/workflows/release.yml` sees the new version in `Info.plist` on `main` and makes the tag `v<version>` and the release with `docs/releases/<version>.md`; a version already released is skipped.
- After the merge: `git switch main && git pull --ff-only`.
- A small change (a docs fix, a rule) gets no branch or pull request of its own: it is committed and goes with the next branch.

## 7. Agents

- **Every agent spawned for Shepit runs on Sonnet 5.5**: the Agent tool with `model: "sonnet"` and `effort: "high"`. Sonnet 5.5's guidance starts routine agentic coding at `medium` and keeps `high` as the floor where judgement is the work; reviews and critique are. This file is the author's request for these agents and that effort (2026-11-24).
- **Agents only read and report.** They don't edit files, commit, push or install. What they find comes back to the main session, which decides and fixes.
- **Each finding:** `file:line` (or the plan's task), what is wrong, a concrete case where it goes wrong, how sure the agent is, and a fix. Most severe first; nothing about style unless the brief asks.
- **Every brief names** the spec, the plan, the diff or files to read, the rules in `CLAUDE.md` (all local, no iCloud defaults, the author's `settings.json` untouched, call content confidential), and the report format above.

### The plan critic

> Read the spec and the plan. Your job is to find everything really wrong with the plan, and to be as harsh as the facts allow: tasks in the wrong order, steps missing, a task that can't be done as written, anything the spec asks for that no task builds, tests that would not catch the mistake they are for, risks nobody named, and places where the plan contradicts the code as it is now (read the code it touches). Only real problems, each with the case where it bites. Don't propose a new design; say what breaks.

### The plan improver

> Read the spec and the plan. Find what is best in the plan and make it better: a shorter way to the same result, work that can be dropped or merged, existing code to reuse (read the code it touches), an order that reaches the first thing the author can look at sooner, tests that cover more with less, and anything that makes a task easier to carry out exactly as written. Each suggestion with what it saves or what it makes surer.

### The task reviewer

> Load the `ponytail` skill and review the task's diff by its rules: the smallest complete change, nothing nobody asked for, existing helpers used, nothing left half done (callers, tests, fixtures). Then check that the diff does what the task and the spec's sections say, find bugs (edge cases, wrong state, what breaks for a caller), check that new branches have tests, and go through the plan's review focus where it touches this task. On a task the plan marks risky, read every caller of what changed. Run `EXPLAIN QUERY PLAN` on every SQL statement the task adds or changes, against a file made from the store's schema and upgrades, and report a scan of a whole table or a temporary B-tree that the code doesn't call a read by design.

### The code reviewer (end of branch)

> Review the whole branch, `git diff main...HEAD`, for correctness: bugs, data loss, wrong state between parts, races, what breaks for an old settings file or database. Use the `code-review` skill on the branch if it runs for you; if not, review by hand to the same brief.

### The security reviewer (end of branch)

> Review the whole branch, `git diff main...HEAD`, for security and privacy: anything sent over the network, user data written outside its setting's folder or to a synced folder, call content or file paths in logs, files and databases written with loose permissions or without care, input from files the user picks. Use the `security-review` skill on the branch if it runs for you; if not, review by hand to the same brief.

## 8. Tests and checks

- `make test` runs everything locally: the Swift tests, the installer and signing tests and the accuracy tools. It is green after every task.
- Tests run only on this Mac. GitHub runs none (the author, 2026-11-24: runners cost minutes); its one workflow makes the release.
- Manual checks live only in `docs/manual-test-checklist.md`. A spec says what to check; the checklist gives each check its number (a letter per part, R1–R11 for the settings review), its result and its date.

## 9. Where things are written

| What | Where |
|---|---|
| What every session needs | `CLAUDE.md` |
| This process | `docs/process.md` |
| How the code fits together | `docs/architecture.md` |
| Ideas, the build order, left open, set aside | `docs/future-ideas.md` |
| Designs | `docs/features/specs/` |
| Plans and their progress | `docs/features/plans/` |
| Manual checks and their results | `docs/manual-test-checklist.md` |
| Release notes | `docs/releases/<version>.md` |
| User docs | `README.md` |

The October plans (phases 1–3) were run with the superpowers skills and still mention them. Since the call offer (2026-11-12) the parts follow this process, which replaces those skills: specs and plans go to `docs/features/`, in the format above.
