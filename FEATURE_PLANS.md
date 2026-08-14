# Salty — Feature Designs

Fleshed-out, actionable plans for larger features. Written against the current architecture
(SwiftUI + SQLiteData/GRDB, `RecipeListQueryBuilder`, the `recipeCategory`/`recipeTag`
junction pattern, `RecipeToHtml`/`HTMLExportOptions`, and the shared-DB story with SaltyKMP).

**Status:** Meal Planner, Cookbook, and Smart Lists are *not* implemented — those sections are
plans. **Shopping Lists are built and synced end to end** (Swift client, SaltyKMP client, and Salty
Server). That section is history and rationale, not a plan.

## Cross-cutting concerns (read once, applies to all of them)

These decisions recur in every feature below, so settle them up front.

- **Migrations — a three-tier decision, not a binary.** All three features introduce *new*
  tables. Which migration mechanism to use depends on how far we ever want this data to
  travel. **Decide this per feature up front**, because retrofitting parity later means
  reconciling two independently-authored `CREATE TABLE`s.
  1. **Swift-only, never synced, KMP never touches it** → a plain GRDB migration
     (`"0005: …"` in `saltyMigrator()` in `Schema.swift`) is fine. SaltyKMP only mirrors base
     migrations 0001–0004 and does `SELECT *` on the *shared* recipe tables, so an extra
     table it never queries sits harmlessly in the shared file.
  2. **Schema/database parity with the Compose app (even with *no* KMP UI yet)** → create the
     table through the shared `saltyMigration` ledger (`saltySharedMigrations`) with a
     mirrored `id` in KMP's `SHARED_MIGRATIONS`, so *both* apps run the **same**
     `CREATE TABLE` exactly once per DB, whoever opens it first. This is the case the "at
     least database parity even without UI" goal points to. Doing it via a Swift-only GRDB
     migration instead risks **schema drift** (column order/types/defaults/index names
     differing from KMP's later independent definition), which breaks positional `SELECT *`
     decoding and shared raw-SQL assumptions.
  3. **Actual data sync to Salty Server / cross-device** → everything in tier 2, **plus** the
     sync layer must learn the tables (see the Sync bullet). This is where the real cost is.
  Denormalizing onto `recipe` (adding a column) is a *separate* axis that always requires the
  shared ledger regardless of tier, because it mutates a shared base table.
  **Recommendation:** default these features to **tier 2** — create the tables via the shared
  ledger with mirrored KMP ids from day one, even before KMP surfaces any UI. It's nearly free
  now and preserves the option to sync later; tier 1 only if we're confident the data is
  permanently local-and-Swift-only (arguably none of these three qualify).
- **Sync (tier 3).** `SaltySyncService`/`RecipeSyncReconciler` currently reconcile recipes +
  images + courses/categories/tags, and Salty Server syncs that set. New tables will **not**
  sync until explicitly added to *both* the server's sync protocol and the client reconcilers —
  a real, separate workstream, not a schema tweak. To keep that door open cheaply, give every
  new table a `lastModifiedDate`. Treat turning sync on as an explicit later phase; treat
  *being ready for it* (tier-2 schema + `lastModifiedDate`) as part of each feature's MVP.

  **How deletions actually propagate — no tombstones needed.** An earlier draft of this bullet
  called for tombstones/soft-deletes. That was wrong for this codebase: deletions are already
  handled by **absence-inference against a complete manifest**, disambiguated by a per-device
  `lastSyncDate` watermark. See the Shopping Lists section for the full derivation; the short
  version is:
  - The watermark is **server-authoritative** and advances only on
    `POST /api/recipes/sync/complete`, so a failed sync leaves it untouched.
  - A record whose `lastModified` is newer than the watermark cannot have been deleted by the
    server (the server never saw it) → **upload**. Older than the watermark and now missing on
    one side → it was genuinely deleted → **propagate the delete**.
  - Therefore "delete something nobody else changed, and it stays deleted" already works with
    no extra table.
  The cost is that the effective rule is *"any remote change since my last sync wins"*, not
  *"the newer of the edit and the delete wins"* — a remote edit that predates your delete but
  syncs after it will still resurrect the record. **Accepted.** Recording delete timestamps to
  do better is the only thing a tombstone would buy, and it isn't worth the table plus its
  garbage collection.
- **Referential integrity.** Follow the existing junction pattern: `id` (UUIDV7 text PK),
  FK columns `.notNull().indexed().references("recipe", onDelete: .cascade)`. This means a
  deleted recipe silently drops out of meals/cookbooks/smart-list membership tables — which
  is the desired behavior for saved collections *locally* (smart lists are dynamic anyway).
  Caveat for tier 3: `onDelete: .cascade` handles the *local* consequence of a recipe delete,
  but does **not** by itself propagate a *membership* delete (e.g. removing a recipe from a
  cookbook) across devices. Note the existing `recipeCategory`/`recipeTag` junctions dodge this
  by never syncing as first-class rows at all — they ride along as `categoryIds`/`tagIds` arrays
  on the recipe payload, and the download path deletes and re-inserts them wholesale. A junction
  change only propagates if `recipe.lastModifiedDate` also moved. Any new membership table should
  either follow that embed-in-the-parent pattern or get its own `lastModifiedDate` and its own
  reconciliation — it will not work by itself.
- **Sidebar integration.** The sidebar uses string IDs with a prefix scheme
  (`allRecipesID = "0"`, `cat_`, `course_`, `tag_`) in `RecipeNavigationSplitViewModel`.
  Each feature adds a new prefix (`meal_`, `plan`, `cookbook_`, `smart_`) and must extend
  three spots: the sidebar `List` sections in `RecipeNavigationSplitView`, `currentScope`,
  and `navigationTitle` in the view model. The **Smart Lists** section is already stubbed
  (commented-out `Section { Text("Coming Soon") }`).
- **Conventions to honor** (from `AGENTS.md`): `@Observable @MainActor` view models with
  `@State`/`@Bindable`; new type per file; user-facing strings in `Localizable.xcstrings`
  with manual symbol keys; modern `FormatStyle` for dates/numbers; add unit tests for logic
  (the `RecipeListQueryBuilderTests` pattern is the model for SQL-generation tests).

---

## Feature 1 — Meal Planner

Two distinct-but-related concepts, deliberately kept separate:

1. **Meal (a menu / saved recipe set)** — a reusable named collection of recipes ("Thanksgiving
   Dinner", "Weeknight Taco Night"). Template-like; not tied to a date.
2. **Planned meal (a scheduled instance)** — recipes assigned to a specific day and a meal-type
   slot (breakfast/lunch/dinner/dessert/…). May be built ad-hoc or instantiated from a saved Meal.

Keeping "Meal" (reusable template) and "Planned meal" (calendar instance) separate avoids the
classic trap where editing a scheduled dinner mutates the template you copied it from.

### Data model

```
@Table("meal")                         // reusable menu / recipe set
  id, name, notes, createdDate, lastModifiedDate

@Table("mealRecipe")                    // ordered membership
  id, mealId → meal(cascade), recipeId → recipe(cascade),
  sortOrder Int, servingsOverride Int?, note String?

@Table("plannedMeal")                   // one scheduled slot on one day
  id, date (day, store as start-of-day or a plain yyyy-MM-dd text),
  mealType Int (enum, see below), mealTypeLabel String?,   // label used only for .other
  sortOrder Int,                        // ordering within the same day+type
  sourceMealId String?,                 // provenance if instantiated from a saved meal (nullable, setNull)
  notes String?, createdDate, lastModifiedDate

@Table("plannedMealRecipe")             // recipes actually in that slot (ad-hoc, decoupled from meal)
  id, plannedMealId → plannedMeal(cascade), recipeId → recipe(cascade),
  sortOrder Int, servingsOverride Int?, note String?
```

- **MealType** — model exactly like `Difficulty`/`Rating`: an `Int`-backed
  `enum … CaseIterable, QueryBindable` with a fixed set (`breakfast, lunch, dinner, dessert,
  snack, other`) plus a `stringValue()`. Use `.other` + `mealTypeLabel` for user-specified
  types now; a full user-defined `mealType` table can come later if fixed set proves limiting.
- A planned meal owns its own recipes (`plannedMealRecipe`) rather than pointing at a `meal`,
  so scheduling from a saved meal is a *copy*. "Save this day's meal as a Meal" is the reverse
  copy. `sourceMealId` is provenance only.

### UI / integration

- **Sidebar**: new "Planner" section with a fixed **"Meal Plan"** item (opens the calendar
  view) and, optionally, saved **Meals** listed as items (`meal_<id>` scope showing that meal's
  recipes in the normal content list).
- **Calendar/week view** (new detail pane, strong candidate for a dedicated window on macOS
  like `RecipeDetailWindowView`): columns = days (week or month), each day grouped by meal-type
  slot. Reuse the existing drag-drop infra (`CategoryDropTargetView`/`TagDropTargetView` prove
  the pattern) to drag recipes from the main list onto a day/slot.
- **Recipe → schedule**: context-menu / detail-view action "Add to meal plan…" and "Add to
  meal…".
- Dates via modern `FormatStyle` (`.formatted(date:time:)`); a `WeekPlannerViewModel`
  (`@Observable @MainActor`) computes the visible date range and groups `plannedMeal`s.

### Feature parity ideas (vs. Paprika, Mela, Crouton, AnyList)

- **Generate a shopping list from a date range** — the highest-value integration. Collect all
  recipes across the selected planned meals, scale by `servingsOverride` via the existing
  `IngredientScaler`, aggregate ingredient lines (via `IngredientTextParser`), and write into
  the existing `ShoppingList` (freeform or structured `contentsForList`). This ties three
  existing subsystems together.
- Drag to reschedule / move a slot to another day.
- Per-day and per-slot notes; mark a slot "made" (could set `recipe.lastPrepared`).
- Recurring / repeat a meal across weeks.
- Print/export the week or month plan (reuse the HTML/print stack from Feature 2).
- Optional: EventKit calendar export (macOS/iOS) — later phase, needs a permission prompt.
- Leftovers / "cook once, eat twice" linking — later, niche.

### Phasing

1. Schema + `plannedMeal`/`plannedMealRecipe`; a read-only week view.
2. Drag-to-schedule, add/remove/reorder within a slot, notes.
3. Saved **Meals** (templates) + instantiate-into-a-day.
4. Shopping-list generation from a date range.
5. Print/export, recurrence, calendar export.

### Open questions

- Store `date` as start-of-day `Date` or `yyyy-MM-dd` text? (Text avoids timezone drift for a
  pure calendar day — recommended.)
- Month view in addition to week view for MVP, or week-only first?
- Should saved Meals appear in the sidebar, or only inside the planner UI?

---

## Feature 2 — Cookbook

An ordered, optionally chaptered collection of recipes for viewing / printing / exporting
(PDF), with title/author/TOC and per-recipe formatting options. **This is mostly a
presentation feature layered on the existing HTML/print pipeline** — the heavy lifting
(`RecipeToHtml`, `RecipeHtmlTheme`, `HTMLExportOptions`, `WebViewRepresentable`,
`PrintRecipeView`) already exists.

### Data model

Relational (preferred over a single JSON blob for FK integrity when a member recipe is
deleted, and for clean reordering):

```
@Table("cookbook")
  id, title, subtitle String?, author String?, introduction String?,
  coverImageFilename String?,                 // reuse RecipeImageManager storage convention
  themeId String? / theme settings,           // reuse RecipeHtmlTheme
  @Column(as: CookbookOptions.JSONRepresentation) options,   // formatting toggles (below)
  createdDate, lastModifiedDate

@Table("cookbookChapter")
  id, cookbookId → cookbook(cascade), title, introduction String?, sortOrder Int

@Table("cookbookRecipe")                       // a recipe placed in a chapter
  id, chapterId → cookbookChapter(cascade), recipeId → recipe(cascade),
  sortOrder Int, includeImageOverride Bool?    // nil = inherit cookbook default
```

- A cookbook with no explicit chapters = a single implicit chapter (or allow a
  `chapterId`-less "loose" tier; simpler to always create one default chapter).
- **`CookbookOptions`** (Codable JSON, mirrors the `HTMLExportOptions`/`ShoppingList` JSON
  precedent): `includeImages`, `includeNotes`, `includeNutrition`, `includeSource`,
  `pageBreakBetweenRecipes`, `pageBreakBetweenChapters`, `includeTitlePage`,
  `includeTableOfContents`, `columns`, font/size — most of these likely already exist on
  `HTMLExportOptions` and can be shared or subclassed.

### Rendering / export (the big reuse win)

- A cookbook renders as: **title page** → **TOC** → for each chapter: chapter header →
  concatenated per-recipe HTML from `RecipeToHtml` (honoring per-recipe image overrides).
- **Print/PDF**: on macOS, existing print-to-PDF via the print path is sufficient (the user
  already noted macOS can do PDF via print — agreed, don't build a separate PDF engine first).
  Feed the assembled HTML through `WebViewRepresentable` + the existing print flow.
- **Page breaks**: CSS `page-break-before: always` / `break-before: page` between
  recipes/chapters driven by the options.
- **TOC with page numbers**: hard in plain HTML (no page model). Start with an anchor-link
  TOC (works on screen + keeps structure); real printed page numbers need CSS Paged Media
  (`@page`, target-counter) — table as a refinement, or lean on the OS print dialog.
- **Theme**: reuse `RecipeHtmlTheme` selection per cookbook.

### UI / integration

- **Sidebar**: "Cookbooks" section; `cookbook_<id>` selection opens a **cookbook editor**:
  chapter list + recipe ordering (drag to reorder, `.onMove`), drag recipes in from the main
  list, per-recipe include-image toggle, and title/author/intro fields.
- **Preview + Export**: a `WebView` live preview (reuse `WebViewRepresentable`) and
  Print / Export-to-PDF / Export-to-HTML actions (reuse `RecipeExportMenu` patterns).
- `CookbookEditorViewModel` (`@Observable @MainActor`).

### Feature parity ideas

- Reorder chapters and recipes; move a recipe between chapters.
- Include/exclude images per recipe (already in schema above).
- Cover image + custom title page.
- Export whole cookbook as a single `.saltyRecipe` bundle / share.
- Later: custom fonts, multi-column layout, per-recipe page-break control, scaling recipes
  to a target servings baked into the printed copy.

### Phasing

1. Schema + editor (create cookbook, chapters, add/reorder recipes).
2. HTML assembly + live WebView preview.
3. Title page + anchor-link TOC + print/PDF/HTML export with the core options.
4. Theming, cover image, refined pagination/TOC-with-page-numbers.

### Open questions

- Always-one-default-chapter vs. supporting chapter-less "loose" recipes?
- Should a cookbook be exportable/importable as a portable bundle (recipes + structure)?
- Reuse `HTMLExportOptions` directly, or a dedicated `CookbookOptions` that composes it?

---

## Feature 3 — Smart Lists + Advanced Search

A saved search/filter that resolves to a **dynamic** list of recipes (iTunes Smart Playlist
model): "everything with 'burger' in the title", "contains 'flour' as an ingredient", "tag =
vegan AND course = Main". The rule-builder UI doubles as an **Advanced Search** panel — same
engine, one transient, one saved. This is the most technically involved feature but has the
strongest existing foundation: `RecipeListQueryBuilder` already contains per-field SQL
fragments (name/introduction LIKE, ingredient/notes/variations JSON `json_each`, tag/category/
course `EXISTS` joins). The work is generalizing those into an operator-driven predicate
compiler.

### Data model

```
@Table("smartList")
  id, name, iconName String?, position Int,
  matchType Int,                              // 0 = all (AND), 1 = any (OR)
  @Column(as: [SmartListRule].JSONRepresentation) rules,
  sortOrderOverride String?, sortDirectionOverride String?,   // optional per-list sort
  createdDate, lastModifiedDate
```

Rules live as a Codable JSON array on the row (no separate table needed; they're always
read/written as a set). Define a portable rule model:

```
struct SmartListRule: Codable, Hashable, Identifiable {
  id: String
  field: SmartListField           // enum, see below
  op: SmartListOperator           // enum
  value: SmartListValue           // string / number / bool / date / relativeDays
}

enum SmartListField {             // maps 1:1 to a SQL clause builder
  name, introduction, source, sourceDetails,
  ingredientText, directionText, noteText, variationText,
  tag, category, course,
  rating, difficulty, servings,
  isFavorite, wantToMake, hasImage,
  createdDate, lastModifiedDate, lastPrepared,
  // later: nutrition.calories, nutrition.protein, …
}

enum SmartListOperator {
  contains, notContains, beginsWith, endsWith,      // text
  is, isNot,                                        // equality (enums, tag/category/course, bools)
  greaterThan, lessThan, between,                   // numeric / date
  inLastDays, notInLastDays,                        // relative date
  isSet, isNotSet                                   // null / empty
}
```

### Query generation — extend `RecipeListQueryBuilder`

This is the core. Today `searchCondition(pattern:options:)` OR's a fixed set of per-field
fragments. Refactor so each **field** exposes a `clause(op:value:) -> QueryFragment` and the
builder composes them:

- Reuse the existing fragments almost verbatim:
  - `ingredientText`/`noteText`/`variationText` → the existing `json_each` +
    `json_extract(value,'$.text')` subqueries (already handle the JSON-array shape).
  - `tag`/`category`/`course` → the existing `EXISTS (… JOIN …)` fragments (extend `is`/`isNot`
    to match by **id** as well as by name-LIKE).
  - `name`/`introduction`/`source` → `COLLATE NOCASE LIKE` with wildcard placement varying by
    operator (`%x%`, `x%`, `%x`).
  - `rating`/`difficulty` → integer compare against the enum `rawValue` (both are
    `QueryBindable`).
  - `isFavorite`/`wantToMake` → boolean `= \(bind:)`.
  - `hasImage` → `imageFilename IS [NOT] NULL`.
  - dates → SQLite `datetime()` math; `inLastDays(n)` → `createdDate >= datetime('now', '-n days')`.
- Combine rules with `AND`/`OR` per `matchType`, all through `\(bind:)` (never string
  interpolation of user values — keep the parameterized-binding discipline the builder already
  follows).
- Add a `RecipeListScope` case (e.g. `.smartList(rules:matchType:)`, or `.smartList(id)` with
  the VM resolving the row) so smart-list selection flows through the same `statement(...)`
  path and stays live-reactive via `@FetchAll`.
- **Unit tests**: extend `RecipeListQueryBuilderTests` — assert generated SQL per operator/
  field and per AND/OR, exactly as the existing tests snapshot `fragment(...).sql`.

### Advanced Search UI (shared with Smart Lists)

- A SwiftUI rule-builder (the spiritual successor to `NSPredicateEditor`): rows of
  `[field] [operator] [value]` with +/– buttons and an **All / Any** toggle. Value editor
  switches on field type (text field, tag/category/course picker, rating/difficulty stepper,
  date picker, relative-days field).
- **Advanced Search** = run the rules transiently (results in the normal content list) with a
  **"Save as Smart List…"** button that persists the exact same `[SmartListRule]` + matchType.
  One builder view, two entry points — maximal reuse.
- **Sidebar**: fill in the already-stubbed "Smart Lists" section; each `smart_<id>` selection
  sets the scope, loads rules, generates SQL. Add edit/delete/reorder.

### Nesting / grouping

Start with a single top-level `matchType` (all rules AND'd or OR'd). Support **one level of
nested groups** (e.g. `A AND (B OR C)`) as a fast-follow by making the rules model a small
tree (`SmartListGroup { matchType, children: [Rule | Group] }`) — the SQL compiler recurses
naturally. Ship flat first; the JSON shape should be forward-compatible with nesting.

### Feature parity ideas

- "Live" auto-updating counts in the sidebar.
- Live-updating (free via `@FetchAll` reactivity).
- Limit / "top N" and a sort override per list (schema has the columns).
- Duplicate a smart list; convert an Advanced Search to a smart list and back.
- Later: full-text search via SQLite **FTS5** for large libraries (the LIKE/json_each scans
  are fine for personal-scale libraries but an FTS index would scale text search) — a bigger,
  separate perf project.

### Phasing

1. `SmartListRule`/field/operator model + generalize `RecipeListQueryBuilder` into a
   clause-per-field compiler; unit tests.
2. Advanced Search panel (transient) driving the compiler.
3. `smartList` table + save/load + sidebar section (fill the stub) + `.smartList` scope.
4. Nested groups; per-list sort/limit; polish.
5. (Optional, later) FTS5 text index.

### Open questions

- Flat rules for v1 with nesting as a fast-follow — confirm that's acceptable UX.
- Which fields matter most for v1 (title/ingredient/tag/course/rating/favorite likely cover
  90%)? Trim the field enum accordingly to reduce surface area.
- Should a smart list optionally compose with the free-text search box, or fully own the scope?

---

## Shopping Lists — BUILT (sync not yet enabled)

Unlike the three features above, this one exists. Recorded here because the sync decisions were
non-obvious and are otherwise invisible in the code.

### What shipped

Two list kinds, fixed at creation, on the pre-existing `shoppingList` table:

- **Checklist** (`isFreeform = false`) — `contentsForList`, a JSON array of
  `ShoppingListListContents { id, isCompleted?, isImportant?, isHeading?, text }`. Reminders-style
  rows, inline editing, heading rows for grouping by store/aisle.
- **Freeform** (`isFreeform = true`) — `contentsForFreeform`, a Markdown text blob, with an
  Edit/Preview toggle. Preview renders via Apple's `swift-markdown` (`HTMLFormatter`) into a
  themed HTML document shown in a `WebView` (`MarkdownToHtml`), so macOS and iOS are identical.

Sidebar has a single **All Lists** row; the list-of-lists is the content column and the selected
list is the detail column, mirroring the All Recipes → list → detail flow.

There is **no automatic conversion between kinds**, by design. A one-way *checklist → freeform*
action exists (`ShoppingListFreeformConverter.text(from:)`); freeform → checklist is deliberately
not offered, though `items(from:)` exists as its round-trip partner if that changes.

`MarkdownToHtml` carries a locked-down CSP (`default-src 'none'`). This is **required, not
belt-and-braces**: swift-markdown 0.8.0's `HTMLFormatter` does not escape *anything* — `visitText`
appends `text.string` verbatim, and `htmlEscaped()` doesn't exist in that release. Neither
sanitizing the parsed tree nor pre-escaping the source works (the parser decodes HTML entities, so
`&lt;b&gt;` becomes a live `<b>` again, and pre-escaping corrupts real Markdown). See the comments
in `MarkdownToHtml.swift`.

### Sync design — decided, not yet implemented

**Status: DONE across all three** — Swift client, SaltyKMP client, and Salty Server.

Decisions taken:

1. **No graveyard / tombstone table.** The watermark scheme in the Sync bullet above already
   guarantees "deleted, nothing else changed → stays deleted," which is the requirement. Accepted
   consequence: a remote edit arriving after your delete resurrects the list.
2. **Lists sync as whole rows. No item-level identity.** `contentsForList` stays a single JSON
   column; most-recently-modified list wins. **Known and accepted consequence:** two devices
   editing the same list concurrently means one side's changes are lost wholesale — tick "Milk"
   on the phone while the iPad adds "Bread", and whichever saves second overwrites the other.
   Promoting items to a `shoppingListItem` table with per-row timestamps is the fix *if* this
   ever proves painful in practice; it was judged not worth it up front.
3. **KMP adopts Swift's conflict behavior** (see next section).

**NULL backfill — DONE (`coalesceNullShoppingListColumns`).** This was the data-loss-critical
prerequisite. `lastModifiedDate` is `Date?`; rows predating `SHARED-V0002`, and anything KMP writes
until it mirrors that migration, are NULL. The reconciler maps a missing timestamp to
`Date.distantPast`, which is *always* `<= lastSyncDate` — so a NULL-stamped list would take the
`toDeleteLocally` branch and be **destroyed instead of uploaded** on its first sync.

The pass runs on every open, next to `coalesceNullRecipeColumns`, and repairs two separate hazards:

- **Decodability** — `name`, `isFreeform`, and `contentsForList` are non-optional on the Swift model
  but nullable in SQL (migration 0001, and KMP's `Schema.sq` likewise). A NULL in any of them fails
  to decode, which takes down the whole list-of-lists fetch, not just the offending row. Coalesced
  to `''` / `0` / `'[]'`.
- **Sync safety** — `lastModifiedDate` coalesces to `CURRENT_TIMESTAMP`. "Now" is deliberate: it
  biases toward *upload* (looks recently modified) rather than *delete*, i.e. the non-destructive
  direction.

`isFreeform` is **derived, not defaulted**: `contentsForFreeform` non-empty → `1`, else `0`.
Defaulting a NULL flag to `0` would open a row that carries freeform text as an empty checklist,
hiding content the user wrote. Covered by `coalescingRepairsNullShoppingListColumns`,
`coalescingInfersFreeformFromExistingText`, and `coalescingLeavesGoodRowsAloneAndIsIdempotent`.

This pass repairs existing rows but does not *prevent* future NULL writes — it stays as the
cross-platform safety net until KMP mirrors `SHARED-V0002` and starts writing the column itself.

**What was built (SaltyKMP repo).**

- **Schema parity** — `lastModifiedDate` added to KMP's `shoppingList` in `Schema.sq` (last column, so
  the order matches what the Swift `SHARED-V0002` ALTER produces on older DBs), plus `SHARED-V0002`
  mirrored into `SHARED_MIGRATIONS` with the same guarded-ALTER shape. `ShoppingListListContents`
  gained `isHeading` to match Swift. `DatabaseMigrationTest` now pins the shared-migration id list
  against the Swift side, so the two can't silently drift.
- **Server** — `ShoppingLists` table (`shopping_list`), `ServerShoppingList` DTO,
  `ShoppingListRepository`, and `/api/shoppingLists` routes shaped exactly like the vocab endpoints:
  a GET returning the **complete** list plus `X-Total-Count`, and per-id GET/HEAD/POST/PUT/DELETE.
  The complete-list guarantee is load-bearing — deletions are detected by absence, so that endpoint
  must never paginate or accept `modifiedSince`.
- **CMP client** — `syncShoppingLists` in `SyncService`, routed through the existing generic
  `SyncReconciler` (no fifth clone), wired into `syncNow` **and both** force-resync paths, with
  `clearAll()` extended so a server-wins reset doesn't strand stale lists.

`contentsForList` is stored server-side as JSON text rather than normalized, matching how the recipe
list columns work — consistent with the whole-row LWW decision above.

- **Swift client** — `syncShoppingListsWithDeletions` in `SaltySyncService`, routed through
  `RecipeSyncReconciler` rather than cloning the ~100-line hand-rolled diff each vocab path carries.
  Wired into `syncNow()` (step 4b) and **both** force-resync paths. Note `forceFullResyncFromServer`
  previously wiped recipes/courses/categories/tags and images but *not* `shoppingList`, which would
  have made a server-wins reset silently asymmetric — it now clears and restores lists too.
  `ServerShoppingList` keeps its conversions in an extension so the memberwise init survives, which
  is what makes a sparse older-peer payload representable in tests.

**A nil `lastModifiedDate` on the wire decodes to "now", never `distantPast`.** Same reasoning as the
local backfill: `distantPast` is always `<=` the watermark, so the list would be deleted rather than
kept. Pinned by `ShoppingListSyncTests.missingTimestampDecodesToNowNotDistantPast`.

**The vocab paths are still duplicated.** `syncCoursesWithDeletions`/`syncCategories…`/`syncTags…` are ~100
lines of near-identical copy-paste each, and they reimplement the reconciliation rules inline
rather than calling `RecipeSyncReconciler` — so that logic lives in four places and only one is
unit-tested. `RecipeSyncReconciler` is already structurally entity-agnostic (it operates on
`Entry(id, lastModified)`); it is only *named* for recipes. Route shopping lists — and ideally the
vocab tables — through it instead.

**Minor, pre-existing:** `AutoSyncCoordinator` observes `.fullDatabase`, so every checklist
checkbox toggle already schedules a debounced 90s sync that does nothing for lists. Harmless, but
worth scoping if list write traffic grows.

**Update (2026-08): per-row revisions + three-way merge superseded whole-row LWW.** Decision 2
above no longer holds: shopping lists now sync on a server-owned per-row `revision`, with a stored
`syncedSnapshot` of the last server agreement as the merge base (`SHARED-V0003` appends both
columns; view models and edit paths are untouched — dirtiness is derived as row-vs-snapshot).
Concurrent edits three-way merge item-by-item (`ShoppingListMerge`, vectors mirrored 1:1 from KMP
in `ShoppingListMergeTests`); unmergeable freeform conflicts survive as "(conflicted copy …)"
lists; uploads carry `baseRevision` so a race 409s into a merge instead of clobbering; server-side
deletes send `If-Match` so an edit beats a delete. `syncShoppingListsWithDeletions` no longer
routes through `RecipeSyncReconciler` (recipes and the vocab tables still do). Full design:
salty_kmp/SHOPPING_LIST_REVISIONS_PLAN.md.

---

## Cross-app deletion parity (Swift ⇄ SaltyKMP)

The two apps currently implement **opposite conflict policies on the same shared database file**,
which is a live inconsistency independent of shopping lists.

- **SaltyKMP has tombstones.** `deletedRecipe (id, deletedDate)` — `Schema.sq`, migration `1.sqm`,
  also `CREATE TABLE IF NOT EXISTS`'d on open in `Database.kt`. `LocalStore.deleteRecipe` writes a
  tombstone; `deleteRecipeLocalOnly` (used when applying a server-driven delete) deliberately does
  not. On sync, `SyncService` pushes tombstoned ids to `/sync/delete`, clears them, and then
  **filters the manifest**: `api.fetchManifest().filter { it.id !in tombstones }`. That filter is
  what makes **delete always win** in KMP.
- **The Swift app has none** — no reference to `deletedRecipe` anywhere, in source or git history —
  so it relies purely on absence-inference, which makes **the edit win**.
- **The server has no tombstones either.** `Tables.kt` has no such table, and
  `SyncDeleteRequest.deviceId` is received and *ignored* (`RecipeRoutes.kt` passes only
  `recipeIds` to a hard `deleteMany`).

Net effect: the outcome of "deleted here, edited there" depends on which app you deleted from.

**Decision: standardize on the Swift behavior (edit-wins).** Cheaper than adding tombstones to
Swift, and it matches the chosen policy above. The change is in SaltyKMP:

- drop the `.filter { it.id !in tombstones }` on the manifest, so a remote edit can resurrect;
- keep pushing tombstoned ids to `/sync/delete` (that part is just an explicit, more reliable
  version of what Swift infers), or drop the table entirely and let absence-inference do it;
- if the table is dropped, remove `1.sqm`'s consumers carefully — it is in the **shared** DB file.

Not yet done. This is data-loss-critical logic in a second repo; do it deliberately, with the
`SyncIntegrationTest` tombstone assertions updated to match the new policy.

**Update (2026-08):** shopping lists have since left the absence-inference scheme entirely —
per-row revisions plus `If-Match` deletes give them real conflict detection on both apps (see the
Shopping Lists update above and salty_kmp/SHOPPING_LIST_REVISIONS_PLAN.md). The parity question in
this section now applies only to recipes and the vocab tables.

### Known residual risks (accepted, both apps)

- **Lost device registration.** `isFirstSync`, and a nil `lastSyncDate`, both short-circuit to
  download and never delete. A delete that hasn't been pushed yet, followed by anything that
  resets the device row, resurrects. Plausible via "reinstall over a DB that lives in a synced
  folder", which yields a new `deviceId`.
- **Clock skew.** `lastModified` comes from the client's clock, `lastSyncDate` from the server's.
  A record stamped in the future stays `> lastSyncDate` for a while, so deleting it resurrects it
  until the watermark catches up.
- **Partial manifests read as mass deletion.** Absence *is* the delete signal, so a truncated
  server response looks like everything was deleted. Guarded by `X-Total-Count` and by
  `serverResponseAllowsLocalDeletions` — but that only catches a *fully empty* response, as its
  own comment concedes.

---

## Suggested build order across all three

1. **Smart Lists / Advanced Search** first — it deepens the query engine that everything else
   benefits from, has the strongest existing foundation, and the sidebar slot is already stubbed.
2. **Cookbook** second — mostly presentation over the existing HTML/print stack; low schema risk.
3. **Meal Planner** third — the most new UI surface (calendar), and its best feature
   (shopping-list generation) reuses `IngredientScaler`/`ShoppingList` which are stable.
