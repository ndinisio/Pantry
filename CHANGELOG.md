# Changelog

All meaningful changes to Pantry, newest first. Versions match commit labels.

---

## v1.8 — One project, and a widget that actually ships

**Fixed**

- There were two Pantry Xcode projects. The second was an untouched copy of the Xcode
  SwiftData template (`ContentView.swift`, `Item.swift`) sitting in
  `~/Desktop/pantry-template-backup`, which is why Xcode's Open Recent and DerivedData
  both listed "Pantry" twice. It has been moved to the Trash — nothing in it came from
  this app. A third ghost was still cached: DerivedData for
  `Pantry/Pantry.xcodeproj`, the nested project removed back in v1.3. That cache is
  gone too, so one project now maps to one build folder.

- `PantryWidgets/` was not in the project at all. No target referenced it, so the widget
  never compiled and never shipped — the folder was documentation, not code. It is now a
  real widget extension target: `PantryWidgets.appex`, embedded in the app under
  `PlugIns/`, with the app depending on it so a plain build produces both.

**Changed**

- `WidgetSnapshotStore` moved to a new top-level `Shared/` folder, which is compiled into
  both the app and the widget. Previously it lived inside the app target, where the
  widget could not have reached it. Sharing is now visible in the directory layout rather
  than hidden in a target membership checkbox. `WidgetSnapshotBuilder` stays in the app —
  it reads SwiftData, which the extension has no business doing.

- The App Group is declared in checked-in entitlements files for both targets rather than
  being a manual Signing & Capabilities step. `Pantry/Pantry.entitlements` and
  `PantryWidgets/PantryWidgets.entitlements` both carry `group.com.ndinisio.Pantry`, and
  `WidgetSnapshotStore.appGroupIdentifier` matches. The README's four-step "create the
  widget target yourself" instructions are gone, because there is nothing left to do.

- Bundle identifiers are consistent. The app had been changed to `com.ndinisio.Pantry`
  but the two test targets were still on the old `com.pantryapp.` prefix; they now match
  the app, and the widget is `com.ndinisio.Pantry.PantryWidgets`.

**Added**

- `Pantry/Resources/PrivacyInfo.xcprivacy`. Apple has required a privacy manifest for App
  Store submission since 2024 and the project had none. It declares no tracking and no
  collected data, and gives the required reason for the one covered API the app touches —
  `UserDefaults`, reason `CA92.1`, access confined to the app and its own group.

- `Pantry/Resources/Localizable.xcstrings`, an empty string catalog. The code already
  routes user-facing text through `String(localized:)` and the project already sets
  `SWIFT_EMIT_LOC_STRINGS`, but there was nowhere for those strings to land.

**Notes**

- `Info.plist` inside a synchronized folder needs an explicit
  `PBXFileSystemSynchronizedBuildFileExceptionSet`, otherwise the folder copies it as a
  resource while Info.plist processing writes the same path — the "Multiple commands
  produce" failure the README already documents, in a new place. The exception set is on
  the `PantryWidgets` group.

---

## v1.7 — Choose which nutrients to show

**Added**

- A `Nutrient` type covering the eight figures on a UK/EU label plus fibre, and three
  new fields on `NutritionFacts` — sugars, saturates and salt. Every field is optional
  and older stored nutrition decodes unchanged.
- **More → Nutrition**, where you choose which nutrients appear in recipe and pantry
  panels. Turning all of them off hides nutrition entirely, which is a legitimate choice
  in an app that is not about nutrition. There is a one-tap return to the standard set.
- Generated recipes are now asked for all eight figures, and the seed loader accepts
  them, so anything the AI layer produces can fill the wider set.

**Changed**

- `NutritionSection` moved out of `PantryItemDetailView` into its own component and
  became preference-aware. It omits a nutrient with no figure rather than rendering it
  as zero — "no data" and "none of it" are different claims — and says so in the footer
  when a chosen nutrient is missing, rather than leaving the reader to wonder whether
  the app is broken.

**Note**

- The 18 bundled recipes carry the standard five figures only. Switching on sugars,
  saturates or salt will show nothing for them, which the footer explains; inventing
  fifty-four figures to fill the gap would have made the panel look complete while being
  no more truthful.

---

## v1.4 — Document the subproject-reference trap

**Changed**

- Troubleshooting now covers what happens after the nested template project is removed.
  If Xcode was opened while the nested `.xcodeproj` existed, it may have registered it as
  a subproject — a `PBXFileReference` with `lastKnownFileType = "wrapper.pb-project"`, an
  empty `Products` group and a `projectReferences` block. That survives deleting the
  folder and leaves the project pointing at a file that is gone. Includes the grep to
  detect it, the instruction to quit Xcode first so it cannot write the change back out,
  and the restore command. Also warns against mistaking it for the recommended-settings
  update, which it resembles in the diff but which changes build settings rather than
  adding project references.

---

## v1.3 — Cover the nested-Xcode-project case

**Changed**

- Troubleshooting now covers the most severe variant of the duplicate-file failure: an
  entire second Xcode project created inside `Pantry/`, which leaves a nested
  `.xcodeproj`, sources, and test folders that all get compiled into this app's target.
  Notes that this project's own test folders live at the repository root, so
  `Pantry/PantryTests` is always a leftover while `./PantryTests` is real, and that these
  files are typically untracked — so `git rm` fails and they have to be moved or deleted
  directly. Recommends moving them aside rather than deleting, so the step stays
  reversible until the build is green.

---

## v1.2 — Name the nested-folder case in troubleshooting

**Changed**

- The troubleshooting section now states exactly what `Pantry/` should contain — eight
  folders and no loose files — and names the nested `Pantry/Pantry/` case, which is what
  you get when an Xcode-generated source folder is copied in one level too deep. That
  variant is committed rather than untracked, so `git status` comes back clean and the
  duplicate looks like it must be in the repository when it is not.

---

## v1.1 — Document the synchronized-group build failure

**Added**

- A troubleshooting section in the README for "Multiple commands produce
  PantryApp.stringsdata", which is the most likely first-build failure for this project
  and is caused by the project structure rather than by any file in the repository.
  `Pantry/` is a file-system-synchronized group, so Xcode compiles everything in that
  folder — including files that are not in git, such as leftovers from an Xcode "App"
  template created in the same directory before the repository arrived. Includes the
  read-only commands to find the duplicates, which files are safe to delete, and the two
  further errors (duplicate `@main`, duplicate `Assets.car`) waiting behind it.
- A note that "Update to recommended settings" should be done with Xcode's own button
  rather than by hand-editing the project file.

---

## v1.0 — Consistency pass and housekeeping

**Fixed**

- Every screen that ranks recipes now uses the same definition of "the library".
  Home, item detail, What Can I Make, insights, reminders and the widget were each
  filtering (or not filtering) unsaved generated suggestions differently, so a recipe
  the user never saved could appear on Home as though it had always been there. One
  `browsable` filter, used everywhere.

**Added**

- Generated recipes the user never saved are swept after a week on launch, so the
  store does not quietly fill up with suggestions nobody wanted. They can still be
  cleared on demand from More → Data.

---

## v0.9 — Ingredient matching, quantity parsing and unit guessing

**Fixed**

- Ingredient matching used plain substring containment, so "egg" matched "eggplant",
  "corn" matched "cornflour" and "lime" matched "limeade". Matching is on whole words
  now, which keeps the case that matters — pantry "chicken" satisfying a recipe's
  "chicken breast" — and drops the ones that never should have matched.
- "a dozen eggs" parsed as one egg: the first number word was consumed and the second
  ignored. A second number word now multiplies the first.
- A trailing full stop from a sentence ended up in the item name — "six eggs." became
  "Eggs." — because the parser keeps dots for decimals.
- Unit guessing matched liquid names as substrings, so "boiled eggs" was measured in
  millilitres because "boiled" contains "oil".
- Added the descriptive words the normaliser was missing (finely, roughly, thinly,
  coarsely, freshly), which were being treated as part of the food's name.

---

## v0.8 — Design review pass

**Fixed**

- An alert announced "Added to Shopping" after adding missing ingredients. Using an
  alert for a success message teaches people to dismiss alerts without reading them.
  The action confirms in place now, where the button was.
- Ticking items off the shopping list threw a confirmation dialog per item asking
  whether to move it to the pantry — exactly wrong for someone holding a basket.
  Ticking off is uninterrupted, and moving what you bought into the pantry is one
  deliberate action afterwards.
- Recipes had both "For You" and "Ready Now", which overlapped almost completely.
- Start Cooking sat inside the section describing the recipe; an action is not a fact
  about the recipe, so it has its own section.
- The "use soon" badge was yellow — poor contrast at caption size, and it made an item
  three days out shout as loudly as one past its date.
- The unit picker put thirteen options in a menu; a list that long belongs behind a
  disclosure row.
- The More tab used a bare ellipsis rather than the conventional overflow symbol.

---

## v0.7 — Cross-file audit, actor isolation, documentation

**Fixed**

- Removed `@MainActor` from the non-UI helpers (`InventoryService`, `SampleData`,
  `RecipeLibrary.installIfNeeded`, `PantryModelContainer.preferences`,
  `WidgetSnapshotBuilder`, `AppEnvironment`, `NetworkMonitor`, `NotificationService`).
  They were being called from non-isolated view helpers and from `.task`, which would
  not have compiled. Nothing here touches UIKit — isolation is now inherited from the
  caller, which is main in every case.
- `RecipeDetailView` took its recipe as `@Bindable` while assigning it in a custom
  initialiser, which is not valid. It is a plain `let` now; SwiftData observation is
  unaffected.
- Deep-linking to a recipe (from a widget, an App Intent, or a suggestion the user has
  just materialised) now actually opens it. `RecipesView` drives a `NavigationPath`
  instead of only clearing its search field.
- Removed nested duplicate `navigationDestination(for: Recipe.self)` registrations.
  Each tab's stack registers its own destinations once; "Find More Ideas" on an item is
  a sheet now, which also suits a focused task better than a push.
- Added the explicit `UIKit` and `OSLog` imports the files using `UIImage`,
  `UIApplication` and privacy-annotated logging need.
- Shopping's purchased section no longer switches the list to `.sidebar` style, which
  made one tab look unlike the other four.

**Changed**

- Offline is now visible where it matters: the AI sections in What Can I Make and
  Shopping say plainly that there is no connection, while still allowing the attempt,
  because the on-device model works offline.
- Preference edits are written back and the services' snapshot refreshed when leaving
  the screen, rather than only when a toggle happens to stamp `lastUpdated`.

**Added**

- `README.md` documenting what the app does, setup, the manual Xcode steps that would
  be reckless to generate (signing, app icon, the widget target and its App Group),
  architecture, the AI layer, secrets and privacy, offline behaviour, accessibility,
  testing, design decisions and implementation notes.
- This changelog.

---

## v0.6 — App Intents, widget, and the test suite

**Added**

- Four App Intents with App Shortcuts phrases: what can I make, what needs using, add
  to pantry, add to shopping list. The first two answer out loud from the local
  matcher, so a voice shortcut works with no network. Adding by voice reuses the same
  parser as typing.
- One widget in three sizes (small, medium, accessory rectangular), reading a small
  snapshot the app writes whenever the pantry changes.
- Unit tests: ingredient normalisation and matching, quantity formatting, unit
  conversion including refused conversions, expiry classification, recipe matching
  across coverage / expiring-first ranking / allergies / equipment / diet / time /
  use-up constraints, shopping suggestions, natural-language parsing, inventory writes
  and consumption, sample-data separability, library idempotence.
- AI layer tests with stub providers: provider order, skipping unavailable providers,
  fallback on failure, exactly one stricter retry on a bad shape, rejection of
  malformed and unusable payloads, offline reported as offline, sample output flagged.
- UI tests for the core loop plus the states easiest to ship broken.

---

## v0.5 — Shopping, meal plan, reminders and settings

**Added**

- Shopping grouped by why something is on the list, with the reason on every row.
  Ticking an item off offers to move it into the pantry.
- An optional weekly meal plan whose planned meals feed the shopping list.
- Two opt-in daily reminders, with permission requested when a switch is turned on
  rather than at launch, and the schedule rebuilt from current inventory.
- Cooking preferences: diet, allergies, dislikes, cuisines, servings, confidence, time,
  budget and the equipment actually in the kitchen. Allergies are a hard filter in the
  matcher; dislikes are a strong preference.
- Intelligence settings listing the provider chain in the order it is tried, with what
  each costs in privacy; the Groq key field writes to the Keychain.
- Data settings with opt-in, marked, separately removable sample content; an About
  screen stating what stays on device and that dates are reminders, not food-safety
  advice.

---

## v0.4 — Home, What Can I Make, recipes, cooking mode and substitutions

**Added**

- A contextual Home screen: sections appear only when they have something to say, the
  greeting is the navigation title, and an empty pantry shows exactly one thing to do.
- What Can I Make?, answering instantly from the local matcher and re-answering as
  filters change. Asking a model is a deliberate step below the answer.
- A recipe library grouped the way a cook thinks, with search across titles, summaries,
  cuisines and ingredients.
- Recipe detail read against the pantry: per-ingredient ownership, servings that
  rescale quantities in place, missing items to the shopping list in one action, save,
  share and mark as cooked.
- Cooking mode: the app's one full-screen presentation. One step in large type, screen
  kept awake, ingredients a tap away, confirmation before abandoning a cook. Respects
  Reduce Motion.
- Finishing a cook records the session, optionally subtracts what was used, and can
  suggest uses for leftovers.
- Substitutions, showing what the recipe already lists first and offline, marking
  anything already in the pantry.

---

## v0.3 — App shell, shared components and the Pantry tab

**Added**

- Native `TabView` with five areas and `.sidebarAdaptable`, so iPad gets a sidebar
  rather than a stretched phone layout.
- `AppEnvironment` for dependency injection; `DeepLink` mapping `pantry://` URLs from
  widgets, notifications and App Intents onto one route type.
- Shared components: quantity controls on the native `Stepper`, a freshness badge that
  always pairs colour with a symbol and a word, category glyphs, and rows that read as
  one VoiceOver stop with adjustment exposed as custom actions.
- Shared AI state views: loading with cancel, actionable errors, and a provenance
  footer that always says which provider answered and whether it stayed on device.
- The Pantry tab: list with sections, search, swipe actions, context menus, three
  groupings, four sort orders, category and location filters, and distinct empty states
  for an empty pantry, no filter matches and no search results.
- Adding food: a form whose first section is name and quantity and nothing else; a
  quick-add sheet parsing either a list or a sentence with every parsed row shown for
  review before saving; barcode scanning via VisionKit; on-device photo recognition via
  Vision. Both capture features handle every failure explicitly and neither is a
  dependency for the core experience.

---

## v0.2 — Inventory intelligence and the AI abstraction layer

**Added**

- `RecipeMatcher`, scoring recipes against what the user owns, weighting coverage first
  and using up soon-to-expire food second, honouring time, difficulty, diet, equipment
  and shopping-appetite constraints. Works with no network.
- `InventoryService` owning every write, including decrementing what a cook used, with
  unit conversion where meaningful and no guessing where not.
- `ShoppingSuggestionEngine` reasoning from the actual pantry: needed for planned
  meals, useful because it unblocks near-miss recipes, optional because something is
  running low.
- `NaturalLanguageItemParser`, turning "2 litres of milk and six eggs" into items
  deterministically and offline.
- `CategoryGuesser` and `UnitConverter`, keeping the add flow down to name and quantity.
- The AI layer: `AIProvider` as the only thing the UI knows about; `AIService` picking a
  provider, decoding, validating, retrying once with a stricter prompt on a bad shape,
  falling through, and throwing if all fail. Providers in priority order: Apple
  on-device Foundation Models, a proxy backend the user controls, then Groq. A sample
  provider for development only, never a silent fallback, always labelled.
- Structured Codable payloads with usability validation, and a JSON extractor that
  recovers an object from a fenced or chatty reply without repairing its contents.
- `AIContextBuilder`, sending a capped, relevance-ordered summary of the kitchen rather
  than the database.
- `SecretStore`, keeping credentials in the Keychain with a scheme environment variable
  for development only. No key in source, Info.plist or this repository.

---

## v0.1 — Project foundation

**Added**

- Xcode project targeting iOS 26 with app, unit test and UI test targets, using
  file-system-synchronized groups and generated Info.plist keys.
- SwiftData models: `PantryItem`, `Recipe`, `RecipeIngredient`, `ShoppingItem`,
  `MealPlanEntry`, `CookingSession`, `UserPreferences`. Enum-backed fields persist as
  raw strings and every stored property has a default, so new cases and new fields do
  not force a migration.
- Domain value types, and utilities for ingredient normalisation, quantity formatting
  and expiry calculation with calm, non-alarming language.
- An 18-recipe bundled library plus a loader, so recipe suggestions work with no
  network and no AI, and realistic sample pantry data.
