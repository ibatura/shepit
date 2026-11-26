# App icon and name: design

- **Date:** 2026-11-25
- **Status:** approved by the author on 2026-11-26. This part builds the icon (B2, §5) and the menu bar (the rhombus in every state, §6). The name is set aside, with Amergin for now, and SPT's letter logo (§7) with it.
- **Place in the build order:** "Next" item 3 in `docs/future-ideas.md`. The author chose it on 2026-11-25, after the query plans, from the "New ideas" item "App icon and name".
- **Builds on:**
  - the window shell spec, which left the icon out ("The Dock shows the generic icon until the author supplies one");
  - the visual style, `docs/features/specs/2026-11-11-visual-style/`;
  - the version and About Shepit, from the import names branch.
- **Drawings:** `2026-11-25-icon-drawings.html` in this folder, rounds 1 to 4.

## 1. Intent

**The icon.** Shepit has no icon of its own. The Dock and ⌘Tab (while the window is open), Finder and the About panel all show macOS's generic app icon. The menu bar shows text, not an image: 🎙, 🔴, ⏳, 🎙⚠ or ⏺.

**The name.** The name check found "Shepit" already taken by another Mac dictation app (§4). This part gives Shepit a name of its own and an icon that goes with it. The icon comes first; the name is set aside for now.

## 2. Decided by the author

- **This part comes next** (2026-11-25). The author picked it from the two proposed after the query plans; the other was cleaner transcripts.
- **Keep looking for a name** (2026-11-25). The first four candidates were Hovir, Tykho, Vymova and Slukh. The author took none of them and said: "we need to keep looking for a name". The check had shown Shepit taken (§4), so the app is renamed.
- **Look in mythology** (2026-11-25): Ukrainian mythology first, then the Celts'.
- **Amergin is "not bad", but keep looking** (2026-11-25).
- **Amergin for now, as an interim choice** (2026-11-25, after the second look). The question of the name is set aside for later, to think of other options; there is nothing more to settle about it now. Nothing is renamed until the name is final.
- **The icon is drawn now, without waiting for the name** (2026-11-25).
- **The icon: B, the cross-stitch wave** (2026-11-26, recommended), from the four directions of round 1 (§5).
- **Its finish: B2, the rhombus** (2026-11-26, recommended), from the four of round 2 (§5).
- **The menu bar: the rhombus in every state** (2026-11-26, recommended), from the three of round 3 (§6).
- **SPT, proposed by the author** (2026-11-26): "Shepit" without its vowels. With it, a letter logo of SPT made of rhombuses, beside the rhombus icon, which stays. The letter logo is drawn in round 4 (§7); the name is checked in §4.
- **Look further in Ukrainian folklore and tales, and in Kyivan Rus' before and after its baptism** (2026-11-26): the third look, §4.
- **None of these; the name is set aside, and the icon is built now** (2026-11-26). The author: "I like none of these. Let's set the name aside for now and make the icons; I'll read what you wrote about the names." The letter logo is set aside with the name.
- **Version 0.4.2** (2026-11-26), as what Shepit does doesn't change. The spec and the plan are approved.

## 3. Goals, non-goals, anti-goals

**Goals**
- Shepit has an icon of its own, B2, wherever macOS shows an app's icon: Finder, the Dock and ⌘Tab while the window is open, the About panel, Spotlight, and the lists in System Settings → Privacy & Security.
- On macOS 26 the icon fills the system's shape and has its light, dark and tinted looks. macOS 14 and 15 show it as an `.icns`.
- The menu bar shows the rhombus instead of emoji, and still tells every state it tells today: ready, recording, transcribing, a problem, a meeting transcript running.

**Non-goals**
- **The rename.** The name is set aside (§2), so nothing is renamed in this part. The letter logo is drawn now and used once the name is settled.
- **The panels' marks.** The dictation panel's 🔴 Слухаю and ⏳ Розпізнаю…, and the menu's ⚠ and ⏺ lines, stay as they are.
- **A Dock icon while the window is closed.** Shepit stays a menu bar app (`LSUIElement`).

**Anti-goals**
- No new setting: the icon is not a choice.
- Nothing fetched over the network: the icon and the menu bar's rhombus are drawn in the repository.
- No change to the bundle id or the signing certificate, so the Accessibility, Microphone and System Audio Recording grants stay.

## 4. The name

### The name check (2026-11-25)

**How it was checked:**
- Apple's search API, for both the Mac App Store and the iOS App Store;
- a web search for the name as an app or software;
- GitHub repositories, for the shortlisted names.

The check found no trademark record either way. It is "roughly unique", as the idea asked, not a legal search.

**"Shepit" is taken, in our own category:**
- **shepit.app.** "Voice dictation for Mac, in any app", made by Rebbix (Cyprus):
  - hold a hotkey, speak, and the text is pasted at the cursor;
  - about 100 languages, Ukrainian among them;
  - macOS 26 on Apple silicon;
  - plans metered in minutes per month (Free has 30 minutes), downloaded from its own site.
- **"Shepit: Noir Detective Mystery"**, a game in the iOS App Store.

**Also taken:**

| Name | Taken by |
|---|---|
| Holos | Several iOS apps |
| Rozmova | An iOS mental health app |
| Zapys | An iOS app |
| Tysha | Three iOS apps |
| Soroka | Two iOS apps |
| Diak, Shelest | iOS apps unrelated to ours |
| Sotto, Undertone, Earshot | Mac and iOS apps |
| HushScribe | A Mac app on GitHub that transcribes meetings on the Mac, the closest kind of app to ours |

**Free.** None of these has an app of that name in either App Store or in the web search:

| Name | Ukrainian | Meaning | Note |
|---|---|---|---|
| Hovir | говір | speech, dialect | one Linux text-to-speech repo on GitHub, no stars |
| Tykho | тихо | quietly | |
| Vymova | вимова | pronunciation | |
| Slukh | слух | hearing | |
| Pysar | писар | scribe | |
| Litopys | літопис | chronicle | Litopy, an iOS writing app, is one letter off |
| Tykhovir | тихо + говір | quiet speech | a made-up word |
| Slukhach | слухач | listener | |
| Pyshy | пиши | write! | |
| Movnyk | мовник | phrase book | |
| Zvukopys | звукопис | sound writing | |
| Vidlunnia | відлуння | echo | |
| Pivholos | півголос | half voice, an undertone | |
| Nyshkom | нишком | on the quiet | |
| Chuyu | чую | I hear | |
| Vukho | вухо | ear | |

### Names from mythology (2026-11-25)

These were checked the same way. Ukrainian names come first, as the author asked.

| Name | Who or what | Fits because | Check |
|---|---|---|---|
| **Domovyk** (домовик) | The house spirit. Ivan Nechuy-Levytsky describes him as the guardian of the family and the hearth, not an evil spirit. | He lives in the house, hears everything and keeps it at home, as Shepit keeps everything on the Mac. | Free in both App Stores. Domowik, a Polish-spelled offline home organizer for Android, is the nearest. |
| Sheptun, sheptukha (шептун, шептуха) | The village healer who heals by whispering charms. | Keeps the whisper of "Shepit". | Free, but close enough to "Shepit" to be confused with shepit.app. |
| Oberih (оберіг) | A charm that guards against harm. | Privacy. | Free. |
| Chuhaister (чугайстер) | A kind Hutsul forest spirit. | Easy to remember, but nothing to do with speech. | Free. |
| Znakhar (знахар) | "The one who knows", a healer. | | Free. |
| Stryboh (Стрибог) | The god of the winds, which carry words. | | Free. |
| Boyan (Боян) | The bard of The Tale of Igor's Campaign. | | Free in the App Store, but a busy name on GitHub, and "баян" is Russian slang for a stale joke. |
| Mavka (мавка) | The forest nymph of "The Forest Song". | | Taken: two iOS apps, and the 2023 cartoon. |
| Berehynia (берегиня) | The guardian of the home. | | Taken: an iOS app has the name. |
| Veles (Велес) | The god of cattle and wealth, the patron of bards. | | Taken: an iOS game. |
| **Amergin** (Amairgen) | The Irish druid-poet. His song is told as the first poem spoken in Ireland. | Spoken words that are kept. | Free. |
| Ogmios | The Gaulish god of eloquence. Lucian describes his listeners chained by their ears to his tongue. | Speech to ears, as in a meeting. | Taken: a well-known developer tool for the Cardano blockchain. |
| Ogma | The Irish god credited with the Ogham script. | Speech to writing, as in dictation. | Taken: "Ogma AI: Offline AI Chat", an iOS app. |
| Fintan (mac Bóchra) | The Irish sage who lived for ages and remembered all of Ireland's history. | Meetings remembered. | An everyday Irish first name, not distinctive. |
| Taliesin, Awen | The Welsh legendary bard, and the bards' inspiration. | | Taken by several apps. |

### A second look (2026-11-25, after "Amergin is not bad")

Checked the same way:

| Name | Who or what | Fits because | Check |
|---|---|---|---|
| **Lirnyk** (лірник) | The wandering singer with a lira, who kept the dumy and psalms in memory and sang them from village to village. | He kept people's words by heart. | Free. |
| Khovanets (хованець) | A house spirit of Galicia and the Hutsul region that keeps the household's wealth. Its name comes from "ховати", to keep or hide. | Keeping, at home. | Free, but hard to read in English. |
| Zozulia (зозуля) | The cuckoo, whose voice counts out the years left. | A voice. | Free in both App Stores. |
| Niavka, Polisun (нявка, полісун) | The Hutsul forest nymph, and the forest spirit of Polissia. | Nothing to do with speech. | Free. |
| Kobzar (кобзар) | The kobza player. | | Free in the App Store, but the word means Shevchenko to every Ukrainian. |
| **Gwydion** | In the Fourth Branch of the Mabinogi, a Welsh magician and "the best teller of tales in the world". | Stories told and kept. | Free. Gwyddion, with two d's, is a microscopy program. |
| Seanchaí | The Irish keeper of lore and teller of tales. | The one who keeps what was said. | Free, but it is read "SHAN-a-kee", not as it is written. |
| Oisín | The poet of the Fianna, who came back after three hundred years to tell their tales. | Tales kept. | An everyday Irish first name. |
| Cairbre, Senchán, Pwyll, Llefelys | Irish and Welsh poets and sages. | | Free, but hard to read and with no clear meaning. |

### SPT (2026-11-26)

The author's proposal: "Shepit" without its vowels, which also makes a short letter logo.
- **Mac App Store:** no app of that name.
- **iOS App Store (US):** an app named "SPT", and seven more whose names start with it, among them SPT Plus, SPT IntelliView, SPT PADEL and "SPT - Simple Public Transit".
- **The web:** many unrelated products use "SPT": an energy storage app, an asset management system, a hospital triage app. None of them is a dictation app.
- **What it costs:** three letters are hard to find by search, and it is unclear how to say them, "es-pee-tee" or "spit". In Ukrainian, too, it does not read as a word.

### A third look (2026-11-26)

Ukrainian folklore and tales, and Kyivan Rus' before and after its baptism, as the author asked.

**How it was checked:**
- Apple's search API: the Mac App Store, and the iOS App Store of the US and of Ukraine;
- for the first four, a web search and GitHub too.

| Name | Who or what | Fits because | Check |
|---|---|---|---|
| **Viche** (віче) | The assembly of a city of Kyivan Rus', where its people decided their matters aloud. | Meetings, said aloud and kept. | Free in the App Stores and the web search. On GitHub, viche.ai, a protocol for AI agents to talk to each other (28 stars). Moara Veche, a Romanian app, is the other spelling. |
| **Pysalo** (писало) | The bone or metal stylus people of Rus' wrote with on birch bark and wax. | What writes speech down, as dictation does. | Free everywhere. Psallo, a Christian music app, is the nearest. English readers may see "pie-salo". |
| Tsera (цера) | The wax tablet Rus' wrote on, and wiped to write again. | Writing kept close at hand. | Free in the App Stores and the web search. TSERA on GitHub (3 stars). The "ts" is hard to start an English word with. |
| Hramota (грамота) | A written letter; the birch-bark letters of Rus' are its everyday notes. | Speech put in writing. | Free. Two GitHub repositories with no stars. |
| Izbornyk (ізборник) | Sviatoslav's Izbornyk (1073, 1076), a collection of writings copied in Kyiv. | Collected words. | Free, but hard to read in English. |
| Byrych (бирич) | The herald of Kyivan Rus', who called out the prince's word in the marketplace. | Speech, though outward. | Free. |
| Kazkar (казкар) | A teller of tales. | Speech. | Free. |
| Shchedryk (щедрик) | The carol of the swallow that tells of a rich year, sung worldwide as "Carol of the Bells". | A voice that brings news. | Free, but hard to read in English. |
| Lastivka (ластівка) | The swallow, the messenger of "Shchedryk". | A messenger. | Free. |
| Rushnyk (рушник) | The embroidered ritual towel. | Needlework, as the icon. | Free. |
| Rukavychka (рукавичка) | "The Mitten", the tale where animal after animal moves into a lost mitten. | Many voices in one small home. | Free, but long. |
| Volkhv, Vishchun (волхв, віщун) | A pre-Christian priest and seer; a soothsayer ("віщий" is what The Tale of Igor's Campaign calls Boyan). | | Free, but hard to read in English. |
| Kotyhoroshko, Didukh, Lybid, Rarog, Svaroh | The tale's hero born of a pea; the Christmas sheaf; the sister of Kyiv's founders; a fire-bird spirit; the god of the sky and the forge. | Nothing to do with speech. | Free. |
| Beresta (береста) | Birch bark, which Rus' wrote its everyday notes on. | Notes. | Taken: "Beresta: Library & Highlights", a Mac and iOS app for notes from books. |
| Nestor (Нестор) | Nestor the Chronicler, the Kyiv monk of The Tale of Bygone Years. | He wrote down what happened. | Taken: several iOS apps. |
| Mokosh (Мокош) | The goddess of spinning and weaving, the only goddess in Volodymyr's pantheon in Kyiv (980). | Needlework, as the icon. | Taken: Mokosh Studio, an iOS app. |
| Kazka (казка) | A tale. | | Taken: several iOS apps. |

Not checked, as the App Store's search slowed down and they have little to do with speech: Telesyk, Vyrii, Perun, Dazhboh, Khors, Simargl, Lada, Kupalo, Zoria.

### What a new name touches (state today)

"Shepit" appears 871 times, in 181 files.

**Things people see:**
- `CFBundleName` and the executable (`Shepit`);
- `/Applications/Shepit.app`;
- About Shepit, the menu bar menu ("Open Shepit", "Quit Shepit"), and the texts in the window and on the panels;
- the README and the docs;
- the GitHub repository `ibatura/shepit` and its releases `v0.2.0` to `v0.4.1`.

**Things people don't see:**
- **The bundle id `dev.shepit.Shepit`.** macOS keys the Accessibility, Microphone and System Audio Recording grants to it, and Shepit's own preferences live under it: the remembered sections, periods and choices.
- **The certificate "Shepit Local Signing".** macOS ties Accessibility to it, and `CLAUDE.md` forbids making a second one.
- **The Swift modules** `Shepit`, `ShepitCore` and `ShepitEngines`.
- **The labels** of the dispatch queues (`dev.shepit.*`) and the `NSLog` prefixes ("Shepit people: …").

**Not affected:** the data folders `~/.config/dictation` and `~/.local/share/dictation`, which don't carry the name.

**Recommended:** change only what people see, and keep the bundle id, the certificate, the modules and the labels. Then nothing needs granting again and no preference is lost. GitHub redirects a renamed repository. Not decided yet: set aside with the name.

## 5. The icon

**State today:**
- `app/Resources/` holds only `Info.plist`. It has no `.icns`, no asset catalogue and no `CFBundleIconFile`.
- `LSUIElement` is true, so the Dock shows Shepit only while its window is open.
- Shepit runs on macOS 14.2 and later (`LSMinimumSystemVersion`). This Mac has macOS 26.4 and Xcode 26.6, with Icon Composer and `actool`.
- `scripts/build-app.sh` builds with SwiftPM and copies the binary, `Info.plist` and the models' manifests into the bundle. It uses no Xcode tool, and the README asks only for "Xcode or just the Command Line Tools".

**Drawings, round 1** (2026-11-25). The author asked for the drawings while the name is set aside, so none of them draws on the name: no letter, no figure from a myth. Each direction is shown large, at 64, 32 and 16 px on a light and a dark background, and as a menu bar glyph.

- **No microphone.** shepit.app's logo is a gold studio microphone (seen on its site on 2026-11-25), and a microphone is what most dictation apps show.
- **A · Sound to text.** Wave bars that turn into lines of text, white on blue. Says what Shepit does, but many transcription apps look like this.
- **B · Cross-stitch wave** (recommended). A sound wave embroidered in red cross-stitch with black ends, on linen, as on a vyshyvanka. Unlike any app we found, and Ukrainian as the app is. At 16 px it reads as red bars on cream.
- **C · Scribe's quill.** A quill that writes a sound wave, cream and light blue on ink blue: what is said is written down.
- **D · Conversation.** Two speech bubbles: one with a wave, the other with lines of text. Speaks of meetings more than dictation.

**Drawings, round 2** (2026-11-26): four ways to finish B.

- **B1 · As drawn.** Seven bars of an uneven wave, two stitches wide, red with black ends, on linen.
- **B2 · Rhombus** (recommended). The wave rises to the middle and falls again, so the black ends draw a rhombus, with a smaller black rhombus at its heart: the oldest motif of Ukrainian embroidery, made of a sound wave. It is still a wave, and at 16 px it reads as a red rhombus.
- **B3 · Dark linen.** B1 on charcoal linen, with cream ends. It stands out on a light Dock and sinks into a dark one.
- **B4 · Red only.** B1 without the black, on white linen. The plainest, but the least like a vyshyvanka.

**B2, as built.** On a 1024 canvas, the body is the rounded square 824 wide. Seven bars, each two stitches wide (a stitch is 32), 3, 9, 15, 21, 15, 9 and 3 stitches high, centred. Each bar's top and bottom stitches are black, and so is the heart: 7 stitches of the middle bar and 1 of each bar beside it. The ground is linen, a gradient from #f7f2e8 to #e6dcc8 with a fine weave.

**The two ways, tried on this Mac** (2026-11-26, macOS 26.4, Xcode 26.6). B2 was drawn as plain SVG and built both ways into a test app bundle in a temporary folder. Then `NSWorkspace` was asked for the icon macOS shows for each:
- **An Icon Composer file (`.icon`).** It was written by hand: `icon.json` with the linen's gradient as the fill, and two layers, the stitches and the weave. `xcrun actool` compiled it without an Xcode project, into `Assets.car` and an `.icns` for macOS 14 and 15, and gave the `Info.plist` keys (`CFBundleIconFile`, `CFBundleIconName`). macOS 26 shows it in its own shape, filled edge to edge, with a glass rim, and makes its dark and tinted looks from the layers.
- **An `.icns` only**, made with `iconutil` from the same drawing. It needs no Xcode, but macOS 26 shrinks it and sets it on a white rounded square.

**What is built:**
- `app/Resources/AppIcon.icon/`: `icon.json` and two SVG layers, `Assets/stitches.svg` and `Assets/weave.svg`, as tried. It is text, so it can be changed without Icon Composer, and opened in Icon Composer too.
- `build-app.sh` compiles it with `xcrun actool` into the bundle's `Contents/Resources` (`Assets.car` and `AppIcon.icns`).
- `Info.plist` gets `CFBundleIconFile` and `CFBundleIconName`, both `AppIcon`.
- **Without `actool`** (the Command Line Tools only), the build goes on without the icon and says so in one line; the app works as before, with the generic icon. When `actool` is there and fails, the build fails.

## 6. The menu bar

**State today:** `MenuModel.title` gives the status item's text: 🎙 ready; 🔴 recording; ⏳ transcribing; 🎙⚠ when idle with a model that failed to load or a hotkey that is taken; and ⏺ in front while a meeting transcript records, finishes or detects speakers. The tooltip is "Shepit: " and the status line.

**Drawings, round 3** (2026-11-26): the five states on a light and a dark menu bar.
- **1 · Emoji, as today.** 🎙, 🔴, ⏳, 🎙⚠ and ⏺🎙.
- **2 · Rhombus in place of 🎙.** A template image of the rhombus, which macOS tints for the menu bar; the other signs stay emoji.
- **3 · Rhombus in every state** (recommended, chosen). The rhombus alone, as menu bar apps on macOS look.

**What is built (3):**

| State | Today | The rhombus |
|---|---|---|
| Ready | 🎙 | in the menu bar's own colour |
| Recording | 🔴 | red, as the visual style keeps red for recording |
| Transcribing | ⏳ | faded, at 40% |
| A problem | 🎙⚠ | an orange dot at its top right |
| A meeting transcript running | ⏺ in front | a red dot before it, whatever the rhombus shows |

- Each state comes in the same cases as today; only the mark changes.
- **The glyph** is B2's rhombus in 18×18 points: seven bars, with a gap where B2 has its black heart. It has no stitches, which blur at this size.
- **Template when plain.** Ready and transcribing without a meeting are a template image, which macOS tints for any menu bar. Red, the orange dot and the meeting's dot need colour, so those images are drawn with the rhombus in the menu bar's text colour.
- **The tooltip** stays "Shepit: " and the status line, and VoiceOver reads the same text, as the icon has no title now.
- The menu itself doesn't change.

## 7. The letter logo

**Drawings, round 4** (2026-11-26). The author asked for a letter logo of SPT, made of rhombuses like the icon, beside the icon, which stays. Each way is shown on linen and on dark, at 20 px, and next to B2. The letters are a 5×7 alphabet, two stitches thick as B2's bars are, and each stroke ends in black (cream on dark) as B2's bars do. On dark the red is a step lighter, as B2's dark red sinks there.
- **W1 · Cross-stitch letters.** Red cross-stitch, as the icon. At 20 px the crosses blur and the letters turn pale.
- **W2 · Rhombus letters** (recommended). Every stitch is a small rhombus, so the letters are a lattice of rhombuses. It is what the author asked for most directly, and of the four it reads best at 20 px and beside the icon.
- **W3 · Rushnyk band.** W1's letters between two rows of small rhombuses, as on an embroidered towel. The richest, but at 20 px the band turns to dots.
- **W4 · S ◆ P ◆ T.** W1's letters with a small B2 rhombus between each two. The rhombuses say it is read letter by letter, and tie it to the icon; it is the widest.

**Where it goes:** nowhere yet. It is a logo for the name SPT, so it is set aside with the name (§2).

## 8. Structure

**ShepitCore**
- `MenuModel.title(_:) -> String` becomes `MenuModel.icon(_:) -> MenuIcon`.
- `MenuIcon` is a value: the dictation's mark (`ready`, `recording`, `transcribing`, `problem`) and whether a meeting transcript runs. The rules that pick it are today's. It also says whether the icon is plain, drawn as a template (§6).

**The app**
- **`MenuController`** sets the status item's image from `MenuIcon` instead of its title, and draws the rhombus with AppKit (§6). The tooltip is as today.
- **`Shepit menubar-test`**, a debug command beside `panel-test`, shows each icon in the menu bar for a moment, without installing.
- **`app/Resources/AppIcon.icon/`**, compiled by `scripts/build-icon.sh`, which `scripts/build-app.sh` calls (§5).
- **`app/Resources/Info.plist`** gets the two icon keys.

**Docs**
- **README:** the requirements say what Xcode adds (the icon); "the 🎙 menu" becomes "the menu bar menu"; the icon's line lists the rhombus's states.
- **`docs/architecture.md`:** "Version and About" says where the icon is and how it is built; "Debug commands" gets `menubar-test`.
- **The manual checks** of §9.

## 9. Tests and manual checks

**Tests** (`MenuModelTests`): `MenuModel.icon` in each case today's title tests cover, which they replace:
- ready;
- a problem from a model that failed to load, and from a taken hotkey;
- recording;
- transcribing, while a model loads too;
- a meeting that records, finishes or detects speakers adds the meeting's dot, with recording and a problem too;
- a meeting that is idle, done or interrupted doesn't;
- only ready and transcribing without a meeting are plain.

**Also tested** (added after the plan review, 2026-11-26):
- **The drawing** (`MenuControllerTests`): each of the eight images is drawn from a background queue, as AppKit may draw it, and has something in it, at its size.
- **The icon's build** (`tests/icon_test.sh`, in `make test`):
  - `build-icon.sh` compiles the icon;
  - it fails on a broken `icon.json`, and when `actool` writes nothing, also after a good build into the same folder;
  - without `actool` it says so and writes nothing.

**Manual checks**, on the installed app:
1. **Where macOS shows the icon:** Finder, About Shepit, Spotlight, and the Dock and ⌘Tab while the window is open. B2 fills the shape, with no white square.
2. **macOS 26's looks:** in System Settings → Appearance, the icon's dark, clear and tinted looks. The stitches still read.
3. **The grants are kept:** Shepit has the icon in Privacy & Security's lists, and a dictation still pastes after the install.
4. **The menu bar on a light and a dark menu bar:**
   - ready;
   - recording: red;
   - transcribing: faded;
   - a problem, a hotkey another app has: the orange dot;
   - a meeting transcript: the red dot before the rhombus;
   - a dictation during a meeting;
   - with Shepit's theme set against the system's;
   - while its menu is open.
5. **The tooltip** shows the status, and VoiceOver reads it on the icon.
6. **The `.icns` for macOS 14 and 15:** this Mac has only macOS 26, so Quick Look of the built `AppIcon.icns` shows B2. On a Mac with 14 or 15 it moves to "Need to test later".

## My calls (not confirmed one by one)

- **The icon is an `.icon`, compiled by `actool`** (2026-11-26). macOS 26 shows a plain `.icns` on a white square (§5), and `actool` also writes the `.icns` that macOS 14 and 15 use. The `.icon` is kept as text in `app/Resources/`.
- **Without `actool`, the build goes on without the icon**, so the Command Line Tools alone still build Shepit, as the README promises.
- **`Info.plist` carries the icon keys itself**, instead of merging the ones `actool` writes, as the names don't change.
- **The menu bar's rhombus has no stitches**, and is a template image when it has no colour (§6).
- **"The 🎙 menu" becomes "the menu bar menu"** in the README and the new checks. The old checks keep their words.
- **The letter logo is two stitches thick, with a lighter red on dark** (§7).

## 10. Questions still open

1. **The name:** Amergin for now (§2); SPT proposed by the author (§4); the third look (§4). Set aside.
2. **What the rename changes:** what people see only (recommended), or the bundle id and the repository too. Set aside with the name.
3. **The letter logo:** W1 to W4 (round 4, §7), and where it goes. Set aside with the name.
