# Main window, part 8: Settings review

Date: 2026-11-23
Status: Draft. The author's decisions are in §2 as they come; §3 is still to decide.
Build order: item 10 in `docs/future-ideas.md` ("Planned, in this order"), next after back and forward (the author, 2026-11-23). Branch `settings-review`. The version is agreed with the author before the pull request (0.4.0 proposed).
Builds on: `2026-11-13-window-shell-design.md` (Settings, Home, the 🎙 menu), `2026-11-12-call-offer-design.md` (the offer panel, automatic start and stop), and the author's remarks under "Every setting reviewed" in `docs/future-ideas.md` (2026-11-16, 2026-11-19, 2026-11-22).

## 1. Intent

Settings grew page by page, and some things ended up where nobody looks for them: the dictation language in General, the detection models in Meetings, the dictation panel on a page of its own, meetings and calls on two pages that don't refer to each other. Home and the 🎙 menu repeat settings that live elsewhere. The calls' switches don't say what on means, and there is one automatic start for all apps.

This part puts every setting where it is looked for, makes each page say what it is for, turns Home into a status page and the 🎙 menu into groups, gives each call app its own behaviour with rules by meeting name, and makes the same controls look and sit the same in every section.

## 2. Decided by the author (2026-11-23)

- **One branch, one release.** The author: not that much work, so no split into three versions. Built in this order inside the branch: (1) Settings pages, Home and the 🎙 menu; (2) calls per app and rules by meeting name; (3) the same controls everywhere.
- **Home: Recent meetings** under Recent dictations: the last few meetings, as few as the dictations, each with its name, app and length; a click opens it in Meetings.
- **Each call app has three choices:** Teams, Zoom and Google Meet each get **Auto, Offer or Off**: start a transcript on its own, offer one in the panel, or do nothing. These replace "Offer a transcript when a call starts", "Start automatically" and the apps' on/off switches.
- **Rules by meeting name name the app.** A rule is an app, a meeting name and what to do (Auto, Offer or Off). Zoom gives no name today (only a repeat's remembered name), but it may later, so a rule can be written for any of the three apps.
- **The app's choice comes first.** An app set to Off does nothing for its calls, whatever a rule for it says: a Zoom rule "Auto" is ignored while Zoom is Off. For an app set to Auto or Offer, a rule that matches the call's name decides.

## 3. To decide

My recommendations first; none is decided until the author says so.

### 3.1 Pages

- **Overlay** (the dictation panel): into Dictation as its "Panel" part, with its look (position, size, colours, meter). Other choices: the look to Appearance; or a page of its own named "Dictation panel".
- **Meetings and Calls:** one Meetings page with Calls, Notes and Transcript parts. Other choice: two pages, each pointing to the other.
- **Models:** every model in Engines and models, the voice and speaker detection models included, each saying what it is for; Meetings says only what it needs, with a link. Other choice: keep the detection models in Meetings.
- **Language:** the dictation language goes from General to Dictation.
- **History and privacy:** parts named after what they keep: Dictations, Statistics, Voices, Databases.
- **Every page** starts with a line on what it is for.
- **Reload settings** goes to General → Files, next to Open settings file. **Reload model** goes to Engines and models, or goes altogether (a change of engine already loads the new one).

### 3.2 Home and the 🎙 menu

- **Home**, top to bottom: Needs attention (only when something is wrong, each with one button that fixes it, a chosen model that isn't downloaded among them); Dictation (the status line); Meeting (as today); Recent dictations; Recent meetings (§2). Mode, Language, Microphone, the engine pickers, Download models… and the two Reload buttons leave.
- **The 🎙 menu** in groups, each led by its state as a line that can't be clicked: ⚠ problems first; Meeting (state, Start or Stop meeting transcript); Dictation (state, Copy last dictation, Recent dictations ▸, Add word to dictionary…); Shepit (Open Shepit ⌘O, Settings… ⌘,, About Shepit, Quit Shepit ⌘Q). Mode, Language and Dictation engine leave; if the author switches the dictation language often, "Dictation language ▸" stays in the Dictation group.

### 3.3 Calls

- **The words:** Auto, Offer, Off (the author's choice, 2026-11-23), each with a hint: "Starts a transcript on its own after N s", "Shows a panel with the call's name and a Start button", "Does nothing".
- **How a rule matches:** the call's name contains the rule's text, ignoring case, so "Daily scrum" also catches "Daily scrum & Refinement". Other choice: the whole name, exactly.
- **Two rules match:** the first in the list wins; rules can be moved up and down. Other choice: the longest text wins.
- **No name found:** rules don't apply; the app's choice does.
- **The delays** (start after, hide the panel after, stop after the call ends) stay one setting each for all apps.
- **The settings file:** the new choice per app and the rules get keys of their own; the old `callOffer`, `callAutoStart` and `callApps` are read while the new keys are missing, and nothing rewrites the file on its own.
- **Google Meet in Chrome** gets no offer (item 12 in `docs/future-ideas.md`): fix it in this branch, since it is the same code, or keep it for later.

### 3.4 The same controls

- **The period menu:** one control with one label, in one place, in Dictations, Statistics and People. Where (left or right) is to decide.
- **The rest of the window:** go through every section for other controls that differ.

### 3.5 Voice numbers

- The threshold, margin, samples, microphone minutes and 30 days stay fixed, not settings: they were settled on the author's meetings and need more people in several meetings before they change (Voices, 2026-11-20).

## 4. Settings today (2026-11-23)

- **General:** Launch at login, Sounds, Language (dictation); Files: Open settings file, Open data folder.
- **Hotkeys:** Mode, Dictation hotkey, Cancel key, Add-word hotkey, Meeting transcript hotkey.
- **Engines and models:** the engine and model for Dictation, Live draft and Meetings; Unload when idle; Models on this Mac (engines only).
- **Dictation:** Microphone, Style prompt, Paste into the original app, Restore clipboard, Max recording length.
- **Overlay:** Show panel, Live draft, Preview; Look (position, width, font size, opacity, colours); Texts (three titles, timer); Meter (meter, bars, colour); Timing (final text, notices).
- **Meetings:** Notes (folder, file name, ask for the meeting name, open the folder); Dictation (block dictation during a meeting); Transcript (your name, language, recognition); Models (voice detection, speaker detection).
- **Calls:** Offer (offer, hide the panel after); Automatic start and stop (start automatically, start after, stop after the call ends); Apps (Teams, Zoom, Google Meet switches).
- **History and privacy:** History (save history, keep days, Recent menu items, keep failed audio, Clear history…); Statistics (collect, typing speed, Clear statistics…); Voices (a pointer to People); Databases (folder).
- **Appearance:** Theme, Accent colour.
- **Home:** Status, Mode, Language, Microphone, Reload settings, Reload model; Engines (three pickers, Download models…); Meeting; Last dictations.
- **The 🎙 menu:** the meeting's state, Start or Stop meeting transcript; Open Shepit; Copy last dictation, Recent ▸, Add word…, Mode ▸, Language ▸, Dictation engine ▸; About Shepit, Settings…, Quit Shepit.
- In `settings.json` but in no page: `serverPort`, `previewModel`.
