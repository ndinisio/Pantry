# Pantry

**Know what you have. Know what to cook. Know what to buy.**

Pantry is a native iOS 26 app for keeping track of the food in your kitchen and turning
that inventory into meals. You add what you own; Pantry works out what to cook, what
needs using, and what is worth buying.

The loop the whole app is built around:

```
Add what I have → Pantry understands my inventory → recipes, ideas and warnings
→ cook something → inventory updates → what am I missing? → shopping suggestions
```

---

## Contents

- [What it does](#what-it-does)
- [Getting started](#getting-started)
- [Steps you need to do in Xcode](#steps-you-need-to-do-in-xcode)
- [Architecture](#architecture)
- [The AI layer](#the-ai-layer)
- [Secrets and privacy](#secrets-and-privacy)
- [Working offline](#working-offline)
- [Accessibility](#accessibility)
- [Testing](#testing)
- [Design notes](#design-notes)
- [Implementation notes](#implementation-notes)
- [Troubleshooting the first build](#troubleshooting-the-first-build)

---

## What it does

**Home** is a dashboard that only shows what is useful right now. The greeting is the
navigation title, "What can I make?" is the primary action, and sections — use soon,
cook tonight, pantry counts, recently added — appear only when they have something to
say.

**Pantry** is the full inventory: a native list with search, swipe actions, context
menus, grouping by category, location or use-by date, four sort orders, and filters.
Adding food is deliberately fast — name and quantity are all that is ever required, and
the category, unit and use-by date are inferred from the name as you type. You can also
paste a list or a sentence, scan a barcode, or recognise food from a photo.

**Recipes** groups the library the way a cook thinks: ready now, quick, one ingredient
short, uses something near its date, saved, recently cooked. Every recipe is read
against your pantry — each ingredient says whether you have it, servings rescale the
quantities, and missing items go to the shopping list in one action. Cooking mode is a
focused full-screen step-by-step view that keeps the screen awake.

**Shopping** is grouped by *why* something is on the list — needed, useful, optional —
and every row carries its reason ("unlocks 4 more recipes from your pantry"). Ticking
something off offers to move it into the pantry.

**More** holds the optional weekly meal plan, pantry insights, cooking preferences,
nutrition, reminders, intelligence settings and data management.

**Nutrition** is present but never the point. Recipes carry per-serving figures and
pantry items can carry their own, and you choose which of the eight nutrients — calories,
protein, carbohydrate, sugars, fat, saturates, fibre, salt — actually appear. Turning them
all off hides nutrition panels entirely. A nutrient with no figure is omitted rather than
shown as zero, and anything a model produced is labelled an estimate wherever it appears.

Beyond the app itself: four App Intents with Siri phrases, a widget in three sizes, and
two opt-in daily reminders.

---

## Getting started

Requirements: **Xcode 26** or later, iOS 26 SDK.

```bash
git clone https://github.com/ndinisio/Pantry.git
cd Pantry
open Pantry.xcodeproj
```

Select the **Pantry** scheme and run. There is no account, no onboarding and no network
requirement — the bundled recipe library installs itself on first launch, so recipe
suggestions work immediately.

To see the app with realistic content, go to **More → Data & Sample Content → Add
Sample Content**. Every sample item is marked, so removing it later never touches
anything you added yourself.

The project uses **file-system-synchronized groups** (Xcode 16+), so adding a Swift file
under `Pantry/` puts it in the target automatically — no project-file edit needed.

---

## Steps you need to do in Xcode

The project builds, runs, and embeds its widget as it stands — there is no manual target
setup left to do. Two things are tied to a specific Apple Developer account rather than
to the source, so change them if you are not using the account this was set up with.

### 1. Signing and identifiers

Signing is configured for team `GJ249953UM`, with:

| | |
|---|---|
| App | `com.ndinisio.Pantry` |
| Widget extension | `com.ndinisio.Pantry.PantryWidgets` |
| App Group | `group.com.ndinisio.Pantry` |

To use your own account, change **Team** on all four targets and replace the prefix in
each of these three places:

1. `PRODUCT_BUNDLE_IDENTIFIER` for **Pantry**, **PantryWidgets**, **PantryTests** and
   **PantryUITests**
2. `Pantry/Pantry.entitlements` and `PantryWidgets/PantryWidgets.entitlements`
3. `WidgetSnapshotStore.appGroupIdentifier` in `Shared/WidgetSnapshotStore.swift`

The App Group has to match across all three. If it does not, nothing crashes —
`WidgetSnapshotStore` falls back to standard defaults, so the app behaves normally and
the widget simply shows its placeholder.

### 2. App icon

`Pantry/Resources/Assets.xcassets/AppIcon.appiconset` is an empty single-size slot. Drop
a 1024×1024 image in via Xcode's asset catalog editor. No icon has been generated or
fetched from anywhere.

### 3. Notifications and camera

Both permission strings are already generated into Info.plist by the build settings
(`INFOPLIST_KEY_NSCameraUsageDescription`, `INFOPLIST_KEY_NSPhotoLibraryUsageDescription`).
Nothing to add. Permission itself is requested in context — the camera when you tap
Scan, notifications when you switch a reminder on — never at launch.

---

## Architecture

Four targets, and one folder per target at the repository root. Each of those folders is
a **synchronized group**: Xcode compiles whatever is inside it, so adding a file is a
matter of saving it in the right directory — there is no membership to maintain.

```
Pantry.xcodeproj
├── Pantry/          → Pantry.app
├── PantryWidgets/   → PantryWidgets.appex, embedded in the app
├── Shared/          → compiled into BOTH of the above
├── PantryTests/     → PantryTests.xctest
└── PantryUITests/   → PantryUITests.xctest
```

`Shared/` holds the one type the app and the widget both need: `WidgetSnapshot` and the
`WidgetSnapshotStore` that reads and writes it in the App Group container. The app writes
after any change worth showing; the widget only ever reads. Keeping it in its own folder
means the sharing is visible in the directory layout rather than hidden in a target
membership checkbox.

Inside the app target:

```
Pantry/
├── App/            App entry, DI container, root TabView, deep links
├── Models/         SwiftData models, value types, container, seed data
├── Views/
│   ├── Home/       Dashboard
│   ├── Pantry/     Inventory, add/edit, quick add, barcode, photo
│   ├── Recipes/    Library, detail, cooking mode, what can I make, substitutions
│   ├── Shopping/   List and suggestions
│   ├── Planner/    Weekly meal plan
│   └── Settings/   More, preferences, reminders, intelligence, data, about
├── Services/
│   ├── AI/         Provider protocol, service, prompts, context, providers
│   ├── Networking/ HTTP client, reachability
│   ├── Inventory/  Matching, writes, suggestions, natural-language parsing
│   ├── Notifications/
│   ├── Recognition/ Barcode and on-device food recognition
│   ├── Security/   Keychain-backed secret storage
│   └── Widget/     Builds the snapshot the widget reads
├── Components/     Reusable rows, controls, AI states, tips
├── Utilities/      Normalisation, formatting, expiry, conversion, logging
├── Intents/        App Intents and App Shortcuts
├── Resources/      Asset catalog, seed recipes, string catalog, privacy manifest
└── Pantry.entitlements
```

Two rules hold throughout:

**Business logic stays out of views.** `RecipeMatcher`, `ShoppingSuggestionEngine`,
`NaturalLanguageItemParser`, `ExpirationCalculator` and `IngredientNormaliser` are pure
and synchronous — no storage, no network, no `ModelContext` — which is why they are
directly testable. `InventoryService` owns every write.

**Dependencies are injected.** `AppEnvironment` holds the `AIService`, the network
monitor and the notification service, and is passed through the SwiftUI environment. A
preview or a test substitutes any of them without touching a view.

### Data model

`PantryItem`, `Recipe`, `RecipeIngredient`, `ShoppingItem`, `MealPlanEntry`,
`CookingSession`, `UserPreferences`, with real SwiftData relationships rather than JSON
blobs.

Two decisions make the schema resilient: **every stored property has a default value**,
and **enum-backed fields persist as raw `String`** with typed computed accessors. Adding
a category, renaming a unit or adding a field does not force a migration, and an unknown
raw value decodes to a sensible case instead of failing.

---

## The AI layer

The UI knows nothing about which provider serves a request. It calls `AIService`, which:

1. picks the first **available** provider in order,
2. sends the request and decodes the reply,
3. **validates** the decoded payload (an empty title or no steps is a failure, not a result),
4. on a bad shape, retries **once** with a stricter prompt,
5. otherwise falls through to the next provider,
6. and **throws** if every provider fails.

```
                       AIService
                          │
   ┌──────────────────────┼──────────────────────┐
   │                      │                      │
On-device            Your backend              Groq
(Foundation Models)    (proxy)              (direct API)
```

The order is deliberate. The on-device model is preferred because nothing leaves the
device, there is no key and it works offline. A proxy you control is next, because it
keeps the credential off the phone. Groq direct is last, for personal use.

Everything is a **structured Codable payload** — recipes, substitutions, meal plans,
shopping advice, inventory analysis, leftover ideas — never free prose where the app
needs data. `JSONExtractor` recovers an object from a fenced or chatty reply (correctly
ignoring braces and escaped quotes inside strings) but never repairs the *contents*, so
a genuinely malformed answer still fails loudly.

**Nothing is ever fabricated.** There is no silent fallback to canned content. A sample
provider exists for development, is only used when explicitly switched on in a debug
build, and everything it produces is labelled as a sample in the interface.

`AIContextBuilder` sends a compact, capped, relevance-ordered summary of the kitchen —
never the database. Items are ordered by what needs using first, the list is capped and
the omission is stated, and no identifiers, photos or purchase dates are included.

---

## Secrets and privacy

**No API key is in this repository, in Swift source, or in Info.plist.** There are
exactly two ways a key reaches the app:

- **Keychain.** You type it into More → Intelligence → Groq. `SecretStore` writes it to
  the device Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
- **A scheme environment variable**, for development only: set `GROQ_API_KEY` (or
  `PANTRY_AI_PROXY_URL` / `PANTRY_AI_PROXY_TOKEN`) under Product → Scheme → Edit Scheme
  → Run → Arguments → Environment Variables. Scheme environment variables are stored in
  `xcuserdata/`, which `.gitignore` excludes.

For anything you would distribute, use the proxy instead:

```
iOS app  →  your backend  (holds the credential)  →  model provider
```

The proxy is expected to accept `{"system": …, "prompt": …, "json": true}` and return
`{"text": …}`. HTTPS is enforced — a plain-HTTP endpoint is refused rather than putting
the prompt and token on the wire in the clear.

What leaves the device, and when:

| | Leaves the device |
|---|---|
| Pantry, recipes, shopping list, plan | Never — all local |
| Photo recognition | Never — Vision, on device |
| Barcode scanning | Never — no product lookup is performed |
| AI requests via the on-device model | Never |
| AI requests via a proxy or Groq | A short text summary of your kitchen only |

---

## Working offline

The core app has no network dependency at all. Offline you can still view and edit the
inventory, add items by hand or from a list, search and filter, browse and read every
recipe, **get ranked recipe suggestions**, see what needs using, and use the shopping
list. Recipe matching runs against the 18-recipe bundled library plus anything saved, so
"what can I make?" is answered instantly and locally.

AI features naturally need either the on-device model or a connection. When there is
neither, the screen says so and points out what still works — it never presents the
whole app as broken.

---

## Accessibility

Built in from the first draft rather than added afterwards:

- Rows are a **single sensible VoiceOver stop** ("Greek Yogurt, 500 grams, use by
  tomorrow, opened") with quantity adjustment exposed as **custom actions** rather than
  fragmenting the row into separate elements.
- **Colour is never the only signal.** Every freshness state pairs a colour with a
  symbol and a word.
- Quantity controls are built on the native `Stepper`, so repeat-on-hold, hit targets
  and VoiceOver behaviour come from the system.
- **Dynamic Type** throughout — semantic text styles only, no fixed font sizes, no
  fixed-height text containers.
- **Reduce Motion** is respected; cooking mode's step change carries no information the
  text does not.
- Semantic system colours only, so Dark Mode and Increase Contrast are handled by the
  system.
- Spoken quantities differ from displayed ones where it matters ("500 grams", not "500 g").

---

## Testing

```bash
xcodebuild test -scheme Pantry -destination 'platform=iOS Simulator,name=iPhone 17'
```

**Unit tests** (Swift Testing) cover ingredient normalisation and matching, quantity
formatting, unit conversion including the conversions it deliberately refuses, expiry
classification, recipe matching (coverage, expiring-first ranking, allergies, equipment,
diet, time and use-up constraints), shopping suggestion generation and ordering,
natural-language parsing, inventory writes including consumption and unit conversion on
cook, sample-data separability, and library idempotence.

The AI layer is tested with **stub providers**: provider order, skipping unavailable
providers, falling through on failure, exactly one stricter retry on a bad shape,
rejection of malformed *and* well-formed-but-unusable payloads, offline surfaced as
offline, and sample output flagged for labelling.

**UI tests** walk the core loop — add, see, suggest, save, shop — plus the states that
are easy to ship broken: every tab, every settings screen, and the intelligence screen
with no provider configured.

---

## Design notes

The app follows the Apple Human Interface Guidelines rather than inventing a design
system. Concretely:

- **Native components throughout.** `TabView`, `NavigationStack`, `List`, `Form`,
  `Stepper`, `Picker`, `Toggle`, `DatePicker`, `Menu`, `ContentUnavailableView`,
  `ShareLink`, `PhotosPicker`, `.searchable`, `.swipeActions`, `.contextMenu`,
  `.confirmationDialog`. No custom tab bar, no floating action button, no fake nav bars.
- **Liquid Glass is left to the system.** Tab bars and toolbars get it automatically
  from the iOS 26 SDK. It is a UI-layer material, not a decoration to apply to content,
  so no card, row or button in this app hand-applies a glass effect.
- **Cards are not the default container.** Hierarchy comes from lists, grouped sections,
  typography and spacing.
- **iPad is not a stretched iPhone.** `.tabViewStyle(.sidebarAdaptable)` turns the same
  five areas into a sidebar, so the structure learned on iPhone is the structure seen on
  a larger screen.
- **Modality is used sparingly.** Sheets are for focused, temporary tasks. There is
  exactly one full-screen presentation in the app — cooking mode — because that is the
  one place total focus is the point.
- **Alerts are rare.** Destructive actions use confirmation dialogs; everything else is
  inline.
- **Expiry language is calm.** Nothing in the app says "expired", "spoiled" or "unsafe".
  Dates are treated as reminders to use something up, and the UI says so.
- **AI is a capability woven into existing flows, not a new interface bolted on top.**
  Local answers appear first, everywhere; asking a model is always a deliberate extra
  step underneath them.

No images, icons, vectors or logos were fetched from the internet. Every glyph is an
SF Symbol; every colour is a system colour or the accent colour defined in the asset
catalog.

---

## Implementation notes

**Swift 5 language mode.** `SWIFT_VERSION = 5.0` is set deliberately. Adopting Swift 6
strict concurrency is a separate, worthwhile piece of work; doing it at the same time as
building the app would have obscured both.

**Ingredient matching is deliberately conservative.** `IngredientNormaliser` lowercases,
strips diacritics and punctuation, removes descriptive words and singularises common
plurals — and nothing cleverer. A wrong merge ("chicken" and "chickpea") is worse than a
miss. Matching does allow containment in both directions, so pantry "chicken" satisfies
a recipe's "chicken breast", which is what a cook expects.

**Unit conversion refuses to guess.** Mass converts to mass and volume to volume. 200 g
of rice against a "pack" of rice returns nothing rather than inventing a factor, and
cooking simply leaves that item alone rather than corrupting the quantity.

**Cooking is forgiving.** Deducting ingredients skips what it cannot match and empties
an item rather than letting it go negative. Pantry quantities are approximate by nature;
a cook should never fail because the arithmetic did not line up.

**Generated recipes stay out of the library** until they are saved. They are
materialised as real `Recipe` objects so cooking mode, servings, sharing and shopping
all work on them without a parallel implementation, and unsaved ones can be cleared from
More → Data.

**The widget reads a snapshot, not the database.** The app writes a handful of values
whenever the pantry changes; standing up SwiftData inside an extension for three numbers
is not worth the memory budget.

**Foundation Models is isolated.** The entire framework surface lives in one file behind
`#if canImport(FoundationModels)`. A build against an SDK without it still compiles —
the provider simply reports itself unavailable and `AIService` moves on.

---

## Troubleshooting the first build

### "Multiple commands produce … PantryApp.stringsdata"

The full error looks like:

```
Multiple commands produce '…/Objects-normal/arm64/PantryApp.stringsdata'
duplicate output file '…/PantryApp.stringsdata' on task:
SwiftDriver Compilation Pantry normal arm64
```

**Cause.** `Pantry/` is a *file-system-synchronized group* (see the pbxproj section
`PBXFileSystemSynchronizedRootGroup`). That is what lets you add a Swift file without
editing the project file — but it also means **Xcode compiles every file in that folder,
including files that are not in this repository**. Two Swift files with the same
basename in one target produce the same `.stringsdata` output path, and the build fails.

Almost always this is a leftover from an Xcode "App" template: `File → New → Project`
generates `Pantry/PantryApp.swift`, `Pantry/ContentView.swift`, `Pantry/Item.swift`,
`Pantry/Assets.xcassets` and `Pantry/Preview Content/`. If those were created before the
repository was brought into the same folder, they are still sitting there, invisible to
git but very visible to Xcode.

**Find it.** All three commands are read-only:

```bash
cd ~/Documents/Projects/Pantry

# Anything in the working tree that is not in the repository
git status --short

# Any duplicate Swift basename inside the compiled folder
find Pantry -name '*.swift' -exec basename {} \; | sort | uniq -d

# Where the copies actually are
find Pantry -name 'PantryApp.swift'
```

A clean checkout returns nothing from the second command, and exactly
`Pantry/App/PantryApp.swift` from the third.

**Fix.** Delete the template leftovers — not the versioned files. In this repository
`Pantry/` contains **exactly eight folders and no loose files**:

```
Pantry/App  Pantry/Components  Pantry/Intents  Pantry/Models
Pantry/Resources  Pantry/Services  Pantry/Utilities  Pantry/Views
```

Anything else at that level is a leftover. The most severe version is an **entire
second Xcode project created inside the source folder**, which leaves four items:

```
Pantry/Pantry.xcodeproj/     a second .xcodeproj
Pantry/Pantry/               its sources — PantryApp.swift, ContentView.swift, Item.swift, Assets.xcassets
Pantry/PantryTests/          its unit tests
Pantry/PantryUITests/        its UI tests
```

All four get compiled into this app's target. Note that **this project's own test folders
live at the repository root**, not inside `Pantry/` — so `Pantry/PantryTests` is always a
leftover, while `./PantryTests` is real.

These are usually untracked, so `git rm` will fail with "pathspec did not match any
files". Move them out rather than deleting outright, so the step is reversible until the
build is green:

```bash
mkdir -p ~/Desktop/pantry-template-backup
mv Pantry/Pantry.xcodeproj Pantry/Pantry Pantry/PantryTests Pantry/PantryUITests \
   ~/Desktop/pantry-template-backup/
```

**Then check whether Xcode wired the nested project in before you removed it.** If it
was ever opened while the nested `.xcodeproj` existed, Xcode may have registered it as a
*subproject*, which survives deleting the folder and leaves a reference to a file that is
no longer there:

```bash
git diff Pantry.xcodeproj/project.pbxproj | grep -E 'projectReferences|wrapper.pb-project'
```

Any output means the reference was added. Quit Xcode first — it holds the project in
memory and will write it back out — then restore the project file:

```bash
git fetch origin
git checkout origin/main -- Pantry.xcodeproj
git commit -m 'Remove the subproject reference to the nested template project'
```

Do not mistake this change for the recommended-settings update: a subproject reference
adds a `PBXFileReference` with `lastKnownFileType = "wrapper.pb-project"`, an empty
`Products` group and a `projectReferences` block, and changes no build settings at all.

If the leftovers are loose files rather than a nested project, the usual set is:

```
Pantry/PantryApp.swift          ← delete (the real one is Pantry/App/PantryApp.swift)
Pantry/ContentView.swift        ← delete
Pantry/Item.swift               ← delete
Pantry/Assets.xcassets          ← delete (the real one is Pantry/Resources/Assets.xcassets)
Pantry/Preview Content/         ← delete
```

Check each against `git status` before removing it, then clean the build folder
(`Product → Clean Build Folder`, ⇧⌘K) and build again.

Two further errors are waiting behind this one if the leftovers stay: a template
`PantryApp.swift` also declares `@main struct PantryApp: App`, so you get
"'main' attribute cannot be used in a module that contains top-level code" or a duplicate
`@main`; and a second `Assets.xcassets` produces the same duplicate-output error for
`Assets.car`.

### "Update to recommended settings"

Click it. Xcode knows the correct values for the exact version you are running, and the
changes it makes are ordinary build settings — this is one to let Xcode do rather than
to hand-edit the project file. Review the diff it shows before accepting, as you would
any change.

---

## Licence

No licence has been chosen yet. Add one before publishing.
