# Shepit

Local dictation for macOS («шепіт» — Ukrainian for "whisper"). Press a hotkey, speak Ukrainian (English terms mid-sentence are fine), press it again — the text is pasted where your cursor is. Speech recognition runs on your Mac; your audio and text never leave it. See [Privacy](#privacy) for exactly what is stored and what touches the network.

Shepit is a native menu-bar app. It also transcribes Teams, Zoom and Google Meet calls into Markdown notes.

## Requirements

- Mac with Apple Silicon (M1 or newer), macOS 14.2 or later; 16 GB RAM or more recommended
- About 3 GB of free disk space (the default model + build)
- Xcode or just the Command Line Tools: run `xcode-select --install` in Terminal if you have neither. With only the Command Line Tools Shepit has no icon of its own, as its icon is compiled by Xcode's `actool`
- `cmake`: if it's missing, the installer installs it with [Homebrew](https://brew.sh), so install Homebrew first or run `brew install cmake` yourself
- The optional Apple speech engine needs macOS 26
- Meeting transcripts record the call through a Core Audio process tap (macOS 14.2+); headphones give the cleanest result

## Install

**1. Get the code:**

```bash
git clone https://github.com/ibatura/shepit.git ~/Projects/shepit
cd ~/Projects/shepit
```

**2. Run the installer:**

```bash
scripts/install.sh
```

It takes several minutes: it builds the app and downloads about 1.6 GB. It is safe to run again; it skips what's already done and never overwrites your settings. It:
- builds `Shepit.app`, signs it and installs it to `~/Applications`
- downloads the default model, whisper.cpp `large-v3-turbo` (1.6 GB), the voice-detection model (1 MB) and the meeting models (voice detection 1 MB, speaker detection 21 MB) into `~/.local/share/dictation/models/`, checking their SHA-256
- creates `~/.config/dictation/settings.json` and `dictionary.json` if they don't exist
- opens Shepit; it also starts at login (Settings → General)

When it finishes, Shepit's icon, a rhombus of bars, appears in the menu bar at the top right of the screen. On a MacBook with a notch the icon can be hidden behind it if the menu bar is full; close a few menu-bar apps to see it.

Other engines are optional and can also be downloaded later in **Settings → Engines and models**: `scripts/install.sh --with-whisperkit --with-parakeet`.

**Signing.** On the first build, if no Apple Development or Shepit signing identity exists, the build creates the local self-signed **Shepit Local Signing** certificate; macOS asks for your login password once while it is added to your login Keychain. That keeps macOS permissions across rebuilds. To use another identity: `DICTATION_SIGN_IDENTITY="Apple Development: you@example.com (TEAMID)" scripts/install.sh`.

**3. One-time setup in macOS:**

1. **System Settings → Privacy & Security → Accessibility** → turn on **Shepit**. It needs this to paste. If Shepit isn't in the list, click **+** and choose `Shepit.app` in your home folder → **Applications**. Without this permission the text is put on the clipboard and Shepit says so.
2. Make your first dictation (below). macOS asks for **Microphone** access for Shepit — click **Allow**.
3. For meeting transcripts: on the first **Start meeting transcript** macOS asks to let Shepit record system audio — click **Allow**. It's in **System Settings → Privacy & Security → Screen & System Audio Recording → System Audio Recording Only → Shepit**. Without it the call is recorded as silence (only your own voice gets into the note).

## Use

1. Click where you want the text — any app: browser, Slack, VS Code, Terminal.
2. Press **⌥Space** (Option+Space) and speak.
3. Press **⌥Space** again. The text is pasted at the cursor.

While you speak, a small panel shows **🔴 Слухаю**, a timer, a frequency meter and a draft of what you're saying. After you stop it shows **⏳ Розпізнаю…**, then the final text, then disappears. The panel never takes focus — your cursor stays where it was.

- **Esc** while recording cancels it.
- **Hold-to-talk** mode: hold ⌥Space while speaking, release to paste (Settings → Hotkeys → Mode).
- **⌃⌥D** adds the selected word to the dictionary (see [Dictionary](#dictionary)).
- The draft text comes from the draft engine; the pasted text from the dictation engine, so they may differ slightly.
- Your clipboard is restored about a second after pasting (some apps read it late).
- Every result is saved to the history (`dictations.sqlite`) before it's pasted, so text is never lost. The window's **Dictations** section shows it.

### The menu bar menu

The menu has the quick actions, in groups for meetings, dictation and Shepit itself; everything else is in [the window](#the-window).

| Item | What it does |
|---|---|
| ⚠ lines | Settings errors and permission problems; a click opens the fix where there is one |
| Meeting line | While a meeting runs: its name, its time and how many phrases wait for recognition |
| Start / Stop meeting transcript | See [Meeting transcripts](#meeting-transcripts) |
| Meeting language | Ukrainian, English or Auto-detect, for meetings; greyed while a meeting records |
| Dictation: Ready — … | The dictation status with its engine, or the current error |
| Copy last dictation | The newest dictation, to the clipboard |
| Recent dictations | Your last dictations. Click one to copy its full text |
| Add word to dictionary… | Same as ⌃⌥D |
| Dictation language | Ukrainian, English or Auto-detect, for dictation; greyed while you dictate |
| Open Shepit (⌘O) | Opens the window on the section it showed last (also: launch Shepit again) |
| Settings… (⌘,) | Opens the window on Settings |
| About Shepit | The version, and the commit it was built from: "Version 0.4.0 (ff170a9)" |
| Quit Shepit (⌘Q) | Quits Shepit |

Mode and the engines are in Settings (Hotkeys, Engines and models).

Icon: the rhombus when ready · red while recording · faded while transcribing · an orange dot for a problem (open the menu to see it) · a red dot in front while a meeting transcript runs.

### The window

**Open Shepit** in the menu (or launching Shepit again) opens its window. While it is open, Shepit has a Dock icon and is in ⌘Tab; closing the window (⌘W) leaves Shepit running in the menu bar. ⌘Q quits Shepit.

| Section | What is there |
|---|---|
| Home | **Needs attention**, only when something is wrong (the hotkey, Accessibility, microphone access, a model a job needs that isn't downloaded, Apple Speech chosen on a macOS before 26), each with its button; the dictation status; the meeting transcript with Start and Stop; your last 10 dictations with Copy; your last 10 meetings, a click opens one in Meetings |
| Meetings | Every meeting transcript: name the meeting and its people, merge people, give a line to another person (see [Meetings in the window](#meetings-in-the-window)) |
| Dictations | Your kept dictations by day, newest first, with the app each went to and Copy (see [Dictations in the window](#dictations-in-the-window)) |
| Dictionary | Terms, replace rules and drop phrases, and **Add word** (see [Dictionary](#dictionary)) |
| Statistics | Numbers about your dictations and meetings, kept on this Mac (see [Statistics in the window](#statistics-in-the-window)) |
| Settings | All settings (see [Settings](#settings)) |
| People | Everyone you named in meetings: their voice, their meetings and how much they talked; rename and merge; **Remember voices** (see [People in the window](#people-in-the-window)) |

While a meeting transcript runs, a card at the top of the sidebar shows its time and name; a click opens it in Meetings.

‹ and › at the top of the window, or ⌘[ and ⌘], go back and forward through the sections and the meeting or person you chose in them, as in a browser; a hint on each arrow says where it goes. The sidebar button next to them, or ⌃⌘S, collapses the sidebar to its icons and back.

### Dictations in the window

- **The period menu** at the top right picks the days the list shows: Today, Last 7 days, Last month (the default), Last 3, 6 or 9 months, Last year, All history, or **Custom…**, as in Statistics. The list loads more as you scroll.
- A long dictation shows two lines; a click opens the whole text, another closes it. **Copy** always takes the whole text.
- Right-click → **Delete…** removes one dictation (after a question) from Dictations, Home and Recent.
- The bar at the bottom says how long history is kept (a click opens Settings → History and privacy) and has **Clear history…**.
- Dictations from before this version (`history.log`) are not shown; see [Where things are](#where-things-are).

### Statistics in the window

Shepit window → **Statistics** counts what `stats.sqlite` keeps while **Collect statistics** is on. At the top: **Overview · Dictation · Meetings**, and the period menu at the right. Shepit remembers both.

- **The period:** Today, Last 7 days, Last month (the default), Last 3, 6 or 9 months, Last year, All history; and **Custom…**: pick the first and the last day in two calendars and press **Show** (both days count).
- **▲ / ▼ under a number** compares with as many days right before the period, up to the same time: Today against yesterday until now, Last 7 days against the 7 days before. None for All history.
- **Overview:** dictations, words, meetings and hours, and time saved (at your typing speed; **at 40 wpm** opens the setting); words per hour, day, week or month, dictation and meetings stacked (hover a bar for its numbers).
- **Dictation:** speed by engine and model, and over time (the 4 engines used most; a point needs 3 dictations of an engine); the apps text went to; when you dictate (weekday × hour); languages; dictionary fixes; cancelled, failed and nothing recognized.
- **Meetings:** meetings and hours, your share of the words, people per meeting (the voices speaker detection told apart, and you); meetings by app (Teams, Zoom, Google Meet, and **Unknown** for meetings recorded before this version or started with no call window found); length; speaker detection; how the call panel's offers ended.
- With Collect statistics off a note at the top says so; what was recorded before is still shown. **Clear statistics…** (Settings → History and privacy) deletes it all.

Only meetings recorded while statistics were on count: notes added with **Add notes…** don't.

## Meeting transcripts

Shepit can write a transcript of a Teams, Meet or any other call into a Markdown note — for example straight into your Obsidian vault.

1. Join the call, then the menu bar icon → **Start meeting transcript**. A dialog asks for the meeting name, prefilled with the one found in the Teams call window or on the Google Meet page (a meeting from a calendar; a quick meet.new call has no name). Zoom shows no topic, so there the note only records "Zoom". When the app gives no name, a meeting that ran at this time before (same weekday last weeks, or daily) gets the name you gave it then. ▾ in the field lists names you used recently; they are kept only on this Mac, in `~/.local/share/dictation/meeting-names.json`. If the call window was still loading, the name appears in the dialog a second or two later. Enter to accept, empty for none, Cancel to not start.
2. The note appears at once and fills a few seconds behind the conversation. You can keep it open in Obsidian.
3. The menu bar icon → **Stop meeting transcript** when the call ends. The last phrases are finished, then remote voices are told apart: `[Співрозмовники]` becomes `[Person 1]`, `[Person 2]`, … ("Meeting: detecting speakers…" in the menu meanwhile).
4. Name the people in the window: **Meetings** (or **Name people** on the "Transcript ready" panel). See below.

### Meetings in the window

Shepit window → **Meetings** lists every transcript, newest first, grouped by week and then by month. A transcript being recorded is at the top with a red dot: open it to see its time, words, phrases waiting, whether your microphone is muted in the call app, the lines written so far, and **Stop**.

Open a finished meeting to:

- **Rename it:** click its name (or ✎), type, and press **Save** or Enter; **Cancel** or Esc leaves it as it was. The note's `title` and its file name change too (the `meetingFileName` template is filled again, in the folder the note is in now). Links to the note from other Obsidian notes are not updated: Obsidian does that only for renames made inside it.
- **Name people:** type a name next to `Person 1`; names given in earlier meetings are suggested. Every line of that person gets the name in the note. A name another person of the meeting already has asks to merge the two.
- **Import names…:** take the names from the transcript Teams or Zoom saved of the same call (a `.vtt` file; Zoom's captions file `.cc.vtt` has no names). Shepit finds where the file sits in the meeting, even when the transcript was turned on late, and shows a sheet: each person with the name the file gives at the times they speak and how much of their time agrees, ticked when they have no name yet; a person with another name is offered the file's name unticked. Two people of one voice are offered as a merge, and your own voice heard through the call as a merge into you. **Apply names** names them as typing does. A file of another meeting, or of only a few minutes, is refused ("doesn't line up with this meeting"). Only names are taken: the lines stay as they are.
- **Merge into:** all lines of one person go to another (for one voice that speaker detection split in two). Your own voice heard through the call can be merged into you.
- **See who said what:** click people (their initials, their share or an empty spot on the row) to highlight their lines in the transcript, each in their colour; click again to turn one off. **Only highlighted people** above the transcript hides everyone else's lines.
- **Give a line to another person:** click the line. **New person** makes a `Person N` for a voice that speaker detection put under someone else.
- **Delete lines:** click a line and choose **Delete line** (at once), or in a person's **⋯** choose **Delete all their lines…** (asks first, with the count). The lines leave the note and Shepit, with their voice samples; this can't be undone. Useful for "hello" and "bye" that everyone says, or a person speaker detection made of one stray word.
- **Reset people…** puts every line back to the person speaker detection gave it; the names you typed stay.
- **Copy** (the note without its front matter), **Open note**, and in **⋯**: **Remove note from list…** (the note stays) and **Move file to Trash…**.

The transcript's text is not edited here; edit it in Obsidian. Shepit changes only the `[name] time` lines, the `title` line and the lines you delete, and reads the note again right before each change, so your edits stay. If you add or delete a line in Obsidian, the lines with the same time (to the second) can no longer be given to someone else. A label typed by hand in a `[name] time` line is not read back.

A meeting whose note was moved, renamed or deleted shows **note not found**, with **Locate note…** to point at the file. Notes made before this version are not in the list: **Add notes…** under the list adds them (pick several, or ⌘A in the folder); a file with no transcript lines is skipped.

### People in the window

Shepit window → **People** lists everyone you named in meetings: you first, then by their last meeting, newest first. A waveform beside a name means their voice is saved. Choose a person to see:

- **The name:** click it (or ✎) to rename, and press **Save** or Enter. Every meeting with this person, and its note's `[name] time` lines, get the new name. A name another person already has asks to **Merge** the two, or **Keep both** (two people with one name, kept apart).
- **Merge into:** every meeting of this person goes to the person you pick, and the notes get that name (one person named twice, say "Olena" and "Olena K."). The merged person leaves People.
- **Voice:** "Saved from 6 meetings" with **Delete voice…**, or "No voice saved".
- **May also be in 2 meetings:** recent meetings with a `Person N` whose voice is like this person's. **Show…** lists them, all checked; **Name them** names the checked ones, as the Meetings section does; the unchecked ones are not suggested again.
- **Who talked how much** in the period picked beside it (the same menu as Dictations and Statistics, Custom… too; Last month by default): meetings, talk time, words, and their share of all the words of those meetings.
- **Meetings** in that period: each with its date and their talk time and words; a click opens it in Meetings.

Talk time is known for meetings recorded from this version on; older meetings and notes added with Add notes… show "–".

You have no Rename, Merge into or Delete voice: your name in notes is Settings → Meetings → Your name (`meetingMyName`), and **Delete all voices…** deletes your voice too.

**Remember voices** (the switch at the top of People, off by default, `rememberVoices`). While it is on:

- Each line of a meeting Shepit records keeps a **voice sample**: 256 numbers that describe the voice, made by speaker detection after Stop. A sample is not audio; it can't be turned back into sound or words. Your own lines get theirs from your microphone: your first 10 minutes of speech, wherever in the meeting you speak. Your voice is only those: a call line you give to yourself keeps no voice of yours.
- A person's **voice print** is the samples of the lines that are theirs now. Naming a person, merging two, giving a line to someone else or Reset people… moves the samples with the lines, so prints learn from your corrections, and undoing one takes its samples back out.
- When a transcript is ready, each `Person N` is compared with the saved voices. A clear match gets that person's name, in the window and in the note, with **recognised by voice** under the name in Meetings; the Transcript ready panel says how many ("42 min · 3 people · 2 recognised"). Change the name, merge or give lines as for anyone. A match needs 0.7 similarity and a lead of 0.1 over the next voice.

Samples are kept only on this Mac, in `meetings.sqlite`, and are deleted:

- one person's: **Delete voice…** (their name stays in the meetings);
- all of them, yours too: **Delete all voices…** beside the switch;
- a meeting's: **Remove note from list…** or **Move file to Trash…**;
- a `Person N` you never named: 30 days after the meeting;
- a call line you gave to yourself, or a line of your microphone you gave to someone else: 30 days after the meeting (a voice counts only on its own channel).

Turning Remember voices off stops samples and recognition; saved voices stay until you delete them. Meetings recorded while it was off, before this version, or added with Add notes… have no samples, as their audio is gone.

To see how well the saved voices would have recognised your people in earlier meetings, run `~/Applications/Shepit.app/Contents/MacOS/Shepit voices-check`: counts per threshold from 0.30 to 0.95, with no names and no text.

### The call panel

You don't have to open the menu. When Teams, Zoom or a Google Meet tab (Chrome, Edge, Brave, Arc) has held the microphone for 3 seconds, what happens depends on that app's choice in Settings → Meetings → **Calls**:

- **Offer** (the default): a small panel appears in the top right corner with the call's name and **Start transcript**. It never takes the keyboard.
- **Auto**: the same panel counts down 5 seconds (`callAutoStartSeconds`) and the transcript starts by itself unless you press **Don't record**.
- **Off**: nothing. A transcript you start yourself during such a call is an ordinary one: it doesn't stop when the call ends.

**Rules by meeting name** decide for some meetings instead of the app's choice, for example *Teams, contains "Daily scrum", then Auto*, or *then Off* for a meeting you never record. The first rule that matches the call's name decides (↑ and ↓ move a rule); a call that matches none gets its app's choice. While an app has a rule, Shepit waits for the call's name before it decides, up to 5 seconds.

- **Start transcript** starts at once, without the name dialog. The name is the one found in the call window, or the one a repeating meeting had last time; without a name the panel says "Zoom call".
- **Not this call**, or the panel hiding by itself after 15 seconds (`callOfferSeconds`), means no more panels for this call. Start from the menu still works.
- **Nothing is recorded without your click**, unless the app or a rule says Auto.
- When the call ends, the panel counts down 10 seconds (`callAutoStopSeconds`) and the transcript stops by itself; **Keep recording** leaves it running. This applies to a transcript started from the panel, or from the menu during the call of an app that isn't Off. A transcript started with no call is never stopped this way.
- After Stop the panel says **Transcript ready**, with **Name people**, which opens the meeting in the window.
- A call's transcript without a single line is removed (for example Start on a pre-join screen that you then closed).

The settings are in Settings → Meetings → **Calls**. Known limits, because a call is detected only by an app holding the microphone:

- The panel can appear on the pre-join screen (Teams turns the microphone on there).
- A microphone test or a voice message in Teams or Zoom longer than 3 seconds gives a panel.
- Another web page using the microphone in the browser while a Meet tab is open gives a panel.
- Google Meet needs Accessibility (to read tab titles); Teams and Zoom panels work without it, but without names.
- Meet in Safari or Firefox, Slack, Teams in a browser and FaceTime give no panel yet.

Shepit only asks macOS which app uses the microphone; it listens to nothing until a transcript starts. With **Collect statistics** on, each panel leaves one row in `stats.sqlite`: the time, the app and how it ended, never the call's name.

What the note looks like:

```markdown
---
date: 2026-10-26
time: "14:05"
title: "Weekly sync"
app: Teams
tags: [transcript]
---
[Ivan] 2026-10-26 14:05:12
Привіт, почнемо з релізу.
[Person 1] 2026-10-26 14:05:18
Yes, the release candidate is ready.
```

- Your voice comes from the microphone and is labelled with your name (`meetingMyName`, or your macOS account name). Everything the Mac plays is the call.
- Dictation (⌥Space) works during a meeting; what you dictate doesn't get into the transcript. To turn the hotkey off while a meeting records, use Settings → Meetings → Block dictation during a meeting.
- Edit the note freely while it's written: Shepit only ever appends, and after the call changes only header lines that still read exactly `[Співрозмовники] <time>`.
- If you delete the note mid-call it is created again. If Shepit quits mid-call (it asks first) the note ends with `⚠ Запис перервано о HH:MM:SS`.
- A session stops by itself after 30 minutes with no speech, or after 4 hours.

**Limitations:**
- All sound the Mac plays (music, videos, notification sounds) is recorded as call audio, except Shepit's own sounds.
- With speakers instead of headphones the microphone hears the call too. Shepit drops a phrase of yours when most of its words were said on the call within 5 seconds, so most of these repeats are removed; a few misheard ones can stay. Because of that check, lines appear in the note about 5 seconds later.
- While you are muted in Teams, Zoom or Google Meet, your microphone is left out of the transcript (Shepit reads the call's mute button). If the button can't be found, your microphone is recorded as usual.
- Short sounds and Whisper's guesses on near-silence ("Mm-hmm.", "uh", "you") are left out.
- Overlapping speech and similar voices reduce speaker accuracy; a phrase that spans a speaker change gets one label.
- Bluetooth headphones switch to headset mode while their microphone is in use (lower playback quality during the call) — that's macOS, same as in Teams. Switching the output device mid-call loses about a second of call audio.
- Teams and Meet don't tell participants about this recording. Tell them, and follow your company's policy.

## Settings

Everything is in the window's **Settings** section (**Settings…**, ⌘,), on seven pages, each starting with a line on what it is for: General, Hotkeys, Dictation (with the panel shown while you speak), Meetings (with Calls), Engines and models (every model on this Mac, what it is for and what uses it), History and privacy, Appearance. A switch or a menu is saved at once; a text field (your name, the folders, the file name, the panel's titles, a rule's text, the style prompt) shows **Save** while you change it, Enter saves too and Esc puts the saved text back. **History and privacy** has Clear history… (clearing also deletes kept audio of failed attempts) and Clear statistics…; both ask first. **Hotkeys** can also record a shortcut that starts or stops a meeting transcript (`meetingHotkey`); a shortcut another Shepit hotkey already uses is refused. **Appearance** has the theme and the accent colour.

The window reads and writes `~/.config/dictation/settings.json`, which you can also edit by hand (**Settings → General → Open settings file**). Hand edits apply within 2 seconds. Only the fields you set are stored; anything missing uses the default. If the file has an error (wrong value or broken JSON), Shepit keeps working with the last good settings, and the menu and the window name the field and what's allowed — the window is read-only until the file is fixed.

### Engines

Shepit can use several local speech engines, chosen separately for **dictation** (the pasted text), the **live draft** and **meetings**:

| Engine | Notes |
|---|---|
| whisper.cpp `large-v3-turbo` | **Default.** Most accurate on the author's Ukrainian clips with the style prompt, fast, ~1.8 GB of memory |
| whisper.cpp `large-v3` | A bit slower, similar accuracy, ~3.5 GB |
| WhisperKit `large-v3` / `large-v3-turbo` | Core ML; first load compiles the model (a few minutes, once) |
| Parakeet | Very fast, but writes English terms in Cyrillic and takes no prompt |
| Apple Speech | macOS 26; Ukrainian only through the older dictation recognizer, weakest results |

Benchmark details: `docs/features/specs/2026-10-18-native-app/02-engines.md` §7. Compare on your own voice with `tools/accuracy/evaluate.py --engines …`.

### settings.json fields

| Field | Default | Allowed values | Meaning |
|---|---|---|---|
| `mode` | `"toggle"` | `"toggle"`, `"hold"` | Toggle: press to start, press to stop. Hold: speak while holding the key |
| `hotkey` | `{"mods": ["alt"], "key": "space"}` | `mods`: any of `"cmd"`, `"alt"` (Option), `"ctrl"`, `"shift"`. `key`: a single character (`"d"`) or a key name (`"space"`, `"return"`, `"f13"`…) | The dictation hotkey. Keys are physical positions, so they work in any keyboard layout |
| `cancelKey` | `"escape"` | a key name | Cancels a recording. Only active while recording |
| `addWordHotkey` | `{"mods": ["ctrl", "alt"], "key": "d"}` | same format as `hotkey` | Adds the selected word to the dictionary |
| `meetingHotkey` | none | same format as `hotkey`, or `null` | Starts a meeting transcript, or stops the running one. Leave it out for no shortcut |
| `engines` | whisper.cpp `large-v3-turbo` for every task | `{"dictation": {"engine": …, "model": …}, "preview": …, "meetings": …}`; engines `whispercpp`, `whisperkit`, `parakeet`, `apple` | Engine and model per task (Settings → Engines and models). Old files with `model` / `previewModel` still work |
| `language` | `"uk"` | `"uk"`, `"en"`, `"auto"` | Keep `"uk"` for Ukrainian with English terms. `"auto"` may translate your speech into one language |
| `stylePrompt` | a Ukrainian sentence with English terms | any text | Example text the engine imitates. Keep English terms in Latin script — this is what makes it write `pull request` instead of «пул реквест» |
| `microphone` | `""` | `""` or a device name | `""` follows the system default input. If the named device isn't connected, the default is used and the panel says so |
| `refocusOriginalApp` | `true` | `true`, `false` | Paste into the app you started in, even if you switched apps while speaking |
| `restoreClipboard` | `true` | `true`, `false` | Put your previous clipboard back after pasting |
| `sounds` | `true` | `true`, `false` | Start / done / error sounds |
| `maxRecordingSeconds` | `300` | 5–3600 | Recording stops and is transcribed automatically after this many seconds |
| `idleUnloadMinutes` | `0` | 0–1440 | Free the models' memory after this many idle minutes; they load again on the next dictation. `0` = keep loaded |
| `overlay` | `true` | `true`, `false` | Show the floating panel. With `false`, only short notices are shown |
| `livePreview` | `true` | `true`, `false` | Show draft text while you speak; needs the draft engine downloaded |
| `historyMenuItems` | `10` | 0–50 | How many recent dictations the Recent submenu shows. `0` hides it |
| `saveHistory` | `true` | `true`, `false` | Keep every result in the history (Dictations) |
| `historyDays` | `0` | 0–3650 | Delete dictations older than this many days, at launch. `0` = keep forever |
| `failedAudioHours` | `24` | 0–720 | How long the audio of a failed transcription is kept in `~/.local/share/dictation/failed/` |
| `launchAtLogin` | `true` | `true`, `false` | Start Shepit at login |
| `collectStats` | `true` | `true`, `false` | Record usage statistics on this Mac (numbers only) |
| `typingSpeedWpm` | `40` | 10–200 | Your typing speed, for "time saved" in Statistics |
| `databasesFolder` | `"~/.local/share/dictation"` | absolute path or starting with `~/` | Where `dictations.sqlite`, `meetings.sqlite` and `stats.sqlite` are kept. Read at launch; files already there are not moved. A synced folder (iCloud) uploads them |
| `overlayStyle` | see below | object | Look of the panel (Settings → Dictation) |
| `meetingsFolder` | `"~/.local/share/dictation/meetings"` | absolute path or starting with `~/` | Where meeting notes go; created if missing. Point it at a folder in your Obsidian vault |
| `meetingFileName` | `"{date} {time} {title}"` | 1–200 characters; see below | Note file name without `.md`; `/` makes subfolders |
| `meetingAskTitle` | `true` | `true`, `false` | Ask for the meeting name at Start (only when the file name uses `{title}`) |
| `meetingMyName` | `""` | any text | Label for your microphone; `""` = your macOS account name |
| `meetingBlocksDictation` | `false` | `true`, `false` | The dictation hotkey does nothing while a meeting is recording |
| `meetingLanguage` | `"auto"` | `"uk"`, `"en"`, `"auto"` | Language of meeting phrases; `auto` picks Ukrainian or English for each part of a phrase, cut at short pauses (whisper.cpp), so a speaker can switch language mid-phrase; English parts get only the dictionary terms as a hint, not the Ukrainian style sentence. A switch with no pause at all stays in one language |
| `callModes` | `{"Teams": "offer", "Zoom": "offer", "Meet": "offer"}` | `"Teams"`, `"Zoom"`, `"Meet"` to `"auto"`, `"offer"` or `"off"` | What a call in each app does (see [The call panel](#the-call-panel)); an app left out is Off |
| `callRules` | `[]` | a list of `{"app": "Teams", "match": "contains", "text": "Daily scrum", "then": "auto"}`; `match`: `"contains"`, `"is"`; `then`: `"auto"`, `"offer"`, `"off"` | Rules by meeting name, in order; the first that matches the call's name decides. Case doesn't matter; an empty text matches nothing |
| `callOfferSeconds` | `15` | `0`, or 5–120 | Seconds until the offer panel hides; `0` keeps it until you press a button |
| `callAutoStartSeconds` | `5` | 3–60 | Length of the Auto countdown |
| `callAutoStopSeconds` | `10` | 3–120 | Seconds from the call's end until the transcript stops, unless you press Keep recording |
| `theme` | `"system"` | `"system"`, `"light"`, `"dark"` | Light or dark for the window, the call panels and the dialogs; `system` follows macOS |
| `accentColor` | `"system"` | `"system"`, `"blue"`, `"purple"`, `"pink"`, `"red"`, `"orange"`, `"yellow"`, `"green"`, `"graphite"` | Accent colour; `system` follows macOS |
| `rememberVoices` | `false` | `true`, `false` | Keep a voice sample of each transcript line on this Mac, so people you name are recognised in later meetings (set in the window's People section) |

A file from before 0.4.0 has `callOffer`, `callAutoStart` and `callApps` instead of `callModes`. Shepit reads them as before (an app not in `callApps`, or every app with `callOffer` off, is Off; with `callAutoStart` on the rest are Auto) until the first change in Calls, which writes `callModes` and removes them.

**Meeting file names.** Placeholders: `{date}` (2026-10-26), `{time}` (14-05), `{year}`, `{month}`, `{day}`, `{hour}`, `{minute}`, `{weekday}` (Mon), `{title}` (the meeting name, up to 80 characters), `{app}` (Teams, Meet). Empty parts and the separators around them are dropped; a name that's taken gets ` (2)`. Not allowed outside placeholders: `\ : * ? " < > | # ^ [ ]`. Examples for a meeting "Weekly sync" on Monday 26 Oct 2026 at 14:05:

| `meetingFileName` | Note |
|---|---|
| `{date} {time} {title}` (default) | `2026-10-26 14-05 Weekly sync.md` |
| `Meetings/{year}/{month}/{date} {title}` | `Meetings/2026/10/2026-10-26 Weekly sync.md` |
| `{date} {app} {title}` | `2026-10-26 Teams Weekly sync.md` |
| `{date} {time} {title}` with no name | `2026-10-26 14-05.md` |

Settings → Meetings shows a live example as you type.

### Panel look — `overlayStyle`

| Field | Default | Allowed values | Meaning |
|---|---|---|---|
| `position` | `"bottom"` | `"bottom"`, `"top"`, `"center"` | Where on the screen with the active window |
| `width` | `560` | 360–1600 | Panel width in points |
| `opacity` | `0.88` | 0.2–1 | Background opacity (1 = solid) |
| `backgroundColor` | `"#141414"` | `"#RRGGBB"` | Background color |
| `textColor` | `"#FFFFFF"` | `"#RRGGBB"` | Text color (the draft text is a bit dimmer) |
| `fontSize` | `14` | 10–28 | Text size; the panel height follows |
| `listeningText` / `transcribingText` / `doneText` | `"Слухаю"` / `"Розпізнаю…"` / `"Готово"` | any text | Panel titles |
| `showTimer` | `true` | `true`, `false` | Show the recording time |
| `showMeter` | `true` | `true`, `false` | Show the frequency meter |
| `meterColor` | `"#FF4D4D"` | `"#RRGGBB"` or `"#RRGGBBAA"` | Meter bar color |
| `bars` | `10` | 3–24 | Number of meter bars |
| `doneSeconds` | `1.0` | 0–10 | How long the final text stays visible |
| `messageSeconds` | `2.5` | 0.5–10 | How long notices like "Cancelled" stay visible |

## Dictionary

`~/.config/dictation/dictionary.json`, also editable in the window's **Dictionary** section: terms and drop phrases are chips (**+ add**, × on hover to remove, drag a term to change the order; terms past the prompt limit are dimmed), replace rules are edited in place (saved on Enter or when you leave the row), and **Add word** opens the ⌃⌥D dialog.

**Quick way:** select a word that came out wrong, in any app (e.g. «кубернетіс»), press **⌃⌥D**, type how it should be written (`Kubernetes`) and press Enter. This adds the rule `"кубернетіс": "Kubernetes"` to `replace` and `Kubernetes` to `terms`. With nothing selected, type `wrong = right` (e.g. `джира = Jira`) or just a word for `terms`.

| Field | What it does |
|---|---|
| `terms` | **Before recognition — a hint.** Words exactly as they should be written; the engine tries to spell them this way in any form. Only engines that take a prompt use it (whisper.cpp, WhisperKit), and only about 200 tokens are read, so put the most important first |
| `replace` | **After recognition — a guaranteed fix.** `"what was heard": "what it should be"`, with any engine. Ignores case, matches whole words, longer phrases win. Each wrong variant needs its own rule |
| `dropPhrases` | Phrases the engine invents on silence, removed when they're the last sentence. Common ones («Дякую за перегляд!», "Thanks for watching") are built in |

## Troubleshooting

| Problem | Fix |
|---|---|
| Nothing happens on the hotkey | Open the menu bar menu: "Hotkey taken" means another app uses the same shortcut — change it in Settings → Hotkeys |
| `brew: command not found` during install | Install [Homebrew](https://brew.sh), or install cmake another way, then run `scripts/install.sh` again |
| Text isn't pasted, "Text copied — allow Accessibility" | System Settings → Privacy & Security → Accessibility → turn on Shepit. If it's on but doesn't work: remove Shepit with **−**, add it again with **+** from `~/Applications`. The text is on the clipboard and in history meanwhile |
| "no microphone access" | System Settings → Privacy & Security → Microphone → turn on Shepit |
| An orange dot on the menu bar icon | Open the menu to read the error. "Not downloaded" → Settings → Engines and models → Download; otherwise quit Shepit and open it again |
| No draft text in the panel | The draft engine isn't downloaded (Settings → Engines and models), or Settings → Dictation → Live draft is off |
| English words come out in Cyrillic | Add them to `terms` and a `replace` rule (see Dictionary) |
| First words cut off / worse recognition with Bluetooth headphones | Using their microphone switches Bluetooth to a low-quality headset mode, which also takes ~0.5 s to start. Choose MacBook Pro Microphone in Settings → Dictation; your music stays in high quality |
| Meeting note has only your voice | System Settings → Privacy & Security → Screen & System Audio Recording → turn on Shepit (Shepit says so after 2 min of your speech with a silent call) |
| "Start meeting transcript (download the model in Settings)" | Settings → Meetings → Download voice detection, and the meetings engine in Engines and models |
| Speakers stay `[Співрозмовники]` | Settings → Meetings → Download speaker detection; it applies to the next meeting |
| Lost text | Everything is in the window's **Dictations** section (with the period menu → All history for older ones). Audio of failed attempts is kept for 24 h in `~/.local/share/dictation/failed/` |

## Update

```bash
cd ~/Projects/shepit
git pull
scripts/install.sh
```

Your settings, dictionary, history and permissions are kept.

## Uninstall

```bash
scripts/uninstall.sh            # removes Shepit and its login item; keeps settings, dictionary, history, statistics and models
scripts/uninstall.sh --purge    # also deletes all of those
```

`--purge` deletes meeting notes kept in the default folder (`~/.local/share/dictation/meetings`) and the databases (dictations, meetings list, statistics) in the default `databasesFolder`. A custom `meetingsFolder` (your Obsidian vault) or `databasesFolder` is never touched.

cmake and the Shepit Local Signing certificate (Keychain Access → login) are left in place.

## Privacy

**What stays on your Mac:** all recording and recognition. Audio is kept in memory and goes only to the speech engine inside Shepit. There is no server, no telemetry, and nothing is sent anywhere.

**What touches the network:** only when you ask — the installer (`cmake` from Homebrew, the whisper.cpp source pinned to an exact commit, Swift packages pinned to exact versions) and model downloads (the installer or the Download button), from pinned Hugging Face revisions, every file checked against SHA-256. Apple Speech language assets are installed by macOS when you click Install language.

**What is stored on disk:**

| What | Where | How long |
|---|---|---|
| Text of every dictation | `dictations.sqlite` in `databasesFolder` (`~/.local/share/dictation` by default), with its time, app and word count | Forever by default — limit with `historyDays`, turn off with `saveHistory`, delete one in Dictations, or Clear history…, which deletes the file. A deleted dictation's text is overwritten in the file |
| Audio of failed attempts | `~/.local/share/dictation/failed/` | `failedAudioHours` (24 h by default) |
| Usage statistics | `~/.local/share/dictation/stats.sqlite` | Numbers, engine and app names (the app a dictation went to, the call app of a meeting), and which dictionary corrections fired — **never** what you dictated, a meeting's name or anyone's name. Turn off with `collectStats`; Clear statistics… deletes it |
| Clipboard | — | The dictated text passes through the clipboard for a moment; your previous clipboard is put back |
| Meeting notes | `meetingsFolder` (`~/.local/share/dictation/meetings` by default, local) | Until you delete them. A synced folder (iCloud Drive, an Obsidian vault in iCloud) uploads the notes to that service |
| Meeting names | `~/.local/share/dictation/meeting-names.json` | The names you gave meetings, with app and start time, to suggest them again (last 300) |
| Meetings list | `~/.local/share/dictation/meetings.sqlite` | Each meeting's note path, name, app, start and duration, the people you named (one name each, shared by their meetings), who said each line and each line's word count and talk time — **not** what was said, which stays in the note. Remove note from list… deletes a meeting from it; `uninstall.sh --purge` deletes it |
| Voice samples | `meetings.sqlite`, only while **Remember voices** is on | 256 numbers per transcript line describing the voice, not audio; see [People in the window](#people-in-the-window). Until Delete voice…, Delete all voices… or the meeting leaves the list; for people you never named, and for lines given across channels (a call line to you, your microphone to someone else), 30 days. A deleted sample is overwritten in the file; copies macOS keeps in freed disk space or local Time Machine snapshots are out of Shepit's reach (FileVault encrypts them) |
| Meeting audio | a private temporary folder | Only during the meeting and speaker detection (with Remember voices on, your microphone too, silent where you were muted or dictating), then deleted — also after a failure, and at the next launch after a crash |

A transcript file opened with **Import names…** is only read: its path and text are not kept anywhere, and only the names you apply are written.

**Shepit's permissions:** Accessibility lets it send ⌘V, read a selected word (⌘C, for ⌃⌥D) and read window and tab titles and the call's mute button, to suggest a meeting name and leave out what you say while muted (it also asks Teams and Chrome to keep their accessibility information built, which they otherwise do only for assistive apps); Microphone lets it record while you dictate or during a meeting transcript; System Audio Recording lets it record the call, only between Start and Stop. It uses them for nothing else.

## Where things are

| Path | What |
|---|---|
| `~/Applications/Shepit.app` | The app |
| `~/.config/dictation/settings.json` | Your settings |
| `~/.config/dictation/dictionary.json` | Your dictionary |
| `~/.local/share/dictation/dictations.sqlite` | Everything you dictated, with the app (in `databasesFolder`) |
| `~/.local/share/dictation/history.log` | Dictations from older versions; no longer read or written, and can be deleted |
| `~/.local/share/dictation/stats.sqlite` | Usage statistics (in `databasesFolder`) |
| `~/.local/share/dictation/models/` | Model files |
| `~/.local/share/dictation/meetings/` | Meeting notes (default `meetingsFolder`) |
| `~/.local/share/dictation/meetings.sqlite` | The meetings list: names, people, who said each line, and saved voices (in `databasesFolder`) |
| `~/.local/share/dictation/meeting-names.json` | Meeting names you used, for the name dialog |

## Development

```bash
make test                         # all tests: Swift (app/), installer, signing, accuracy tools
scripts/build-app.sh              # build, sign and install Shepit.app
tools/accuracy/record.sh          # record your own test clips (run in a normal terminal window)
tools/accuracy/evaluate.py --engines whispercpp:large-v3-turbo parakeet apple   # compare engines on those clips
```

Releases: a merge into `main` that raises `CFBundleShortVersionString` in `app/Resources/Info.plist` makes the tag `v<version>` and a GitHub release with the notes in `docs/releases/<version>.md` (`.github/workflows/release.yml`).

The code is a SwiftPM package in `app/`: `ShepitCore` (settings, dictionary, controller, statistics — pure logic), `ShepitEngines` (the four speech engines), `Shepit` (the app). A plain `swift build --package-path app` on a fresh clone needs `scripts/build-whisper-lib.sh` first. Design: `docs/features/specs/2026-10-18-native-app/`.

## License

[GNU GPL v3](LICENSE).
