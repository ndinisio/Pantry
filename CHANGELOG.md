# Changelog

All meaningful changes to Pantry, newest first. Versions match commit labels.

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
