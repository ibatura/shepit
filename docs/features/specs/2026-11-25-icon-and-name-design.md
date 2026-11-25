# App icon and name: design

- **Date:** 2026-11-25
- **Status:** first draft. It has the name check and Amergin as the interim name (§2); the final name and the icon are still to be decided with the author.
- **Place in the build order:** "Next" item 3 in `docs/future-ideas.md`. The author chose it on 2026-11-25, after the query plans, from the "New ideas" item "App icon and name".
- **Builds on:**
  - the window shell spec, which left the icon out ("The Dock shows the generic icon until the author supplies one");
  - the visual style, `docs/features/specs/2026-11-11-visual-style/`;
  - the version and About Shepit, from the import names branch.

## 1. Intent

**The icon.** Shepit has no icon of its own. The Dock and ⌘Tab (while the window is open), Finder and the About panel all show macOS's generic app icon. The menu bar shows text, not an image: 🎙, 🔴, ⏳, 🎙⚠ or ⏺.

**The name.** The name check found "Shepit" already taken by another Mac dictation app (§3). This part gives Shepit a name of its own and an icon that goes with it.

## 2. Decided by the author

- **This part comes next** (2026-11-25). The author picked it from the two proposed after the query plans; the other was cleaner transcripts.
- **Keep looking for a name** (2026-11-25). The first four candidates were Hovir, Tykho, Vymova and Slukh. The author took none of them and said: "we need to keep looking for a name". The check had shown Shepit taken (§3), so the app is renamed.
- **Look in mythology** (2026-11-25): Ukrainian mythology first, then the Celts'.
- **Amergin is "not bad", but keep looking** (2026-11-25).
- **Amergin for now, as an interim choice** (2026-11-25, after the second look). The question of the name is set aside for later, to think of other options; there is nothing more to settle about it now. Nothing is renamed until the name is final.

## 3. The name check (2026-11-25)

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

**Names from mythology.** These were checked the same way, on 2026-11-25. Ukrainian names come first, as the author asked.

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

**A second look** (2026-11-25, after "Amergin is not bad"). Checked the same way:

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

## 4. What a new name touches (state today)

"Shepit" appears 871 times, in 181 files.

**Things people see:**
- `CFBundleName` and the executable (`Shepit`);
- `/Applications/Shepit.app`;
- About Shepit, the 🎙 menu ("Open Shepit", "Quit Shepit"), and the texts in the window and on the panels;
- the README and the docs;
- the GitHub repository `ibatura/shepit` and its releases `v0.2.0` to `v0.4.1`.

**Things people don't see:**
- **The bundle id `dev.shepit.Shepit`.** macOS keys the Accessibility, Microphone and System Audio Recording grants to it, and Shepit's own preferences live under it: the remembered sections, periods and choices.
- **The certificate "Shepit Local Signing".** macOS ties Accessibility to it, and `CLAUDE.md` forbids making a second one.
- **The Swift modules** `Shepit`, `ShepitCore` and `ShepitEngines`.
- **The labels** of the dispatch queues (`dev.shepit.*`) and the `NSLog` prefixes ("Shepit people: …").

**Not affected:** the data folders `~/.config/dictation` and `~/.local/share/dictation`, which don't carry the name.

**Recommended:** change only what people see, and keep the bundle id, the certificate, the modules and the labels. Then nothing needs granting again and no preference is lost. GitHub redirects a renamed repository. Not decided yet: the author didn't answer this question on 2026-11-25.

## 5. The icon (state today)

- `app/Resources/` holds only `Info.plist`. It has no `.icns`, no asset catalogue and no `CFBundleIconFile`.
- `LSUIElement` is true, so the Dock shows Shepit only while its window is open.
- Shepit runs on macOS 14.2 and later (`LSMinimumSystemVersion`). This Mac has macOS 26.4 and Xcode 26.6, with Icon Composer and `actool`.

**Two ways to make it, to choose in the next round:**

1. **An Icon Composer file (`.icon`).** Its layers get macOS 26's Liquid Glass look (light, dark and tinted). `actool` compiles it into `Assets.car` and also writes an `.icns` for macOS 14 and 15. `build-app.sh` would then need Xcode's `actool`, which it doesn't use today.
2. **An `.icns` only**, drawn as layered images and put together with `iconutil`. It needs no Xcode. macOS 26 shows it as drawn, without Liquid Glass. It has been reported that an icon that doesn't fill the rounded square is set on a grey square.

**The menu bar** could keep its emoji, or get a template image that macOS tints for light and dark menu bars. The states (recording, transcribing, a problem, a transcript running) would then need a sign of their own.

**Drawings come next.** The icon's look is shown in drawings once the name is chosen, since the icon may draw on it.

## 6. Questions still open

1. The new name: Amergin for now (§2); set aside to think of other options.
2. What the rename changes: what people see only (recommended), or the bundle id and the repository too.
3. The icon's look, in drawings, and how it is made (`.icon` or `.icns`).
4. The menu bar: keep the emoji, or a template image.
