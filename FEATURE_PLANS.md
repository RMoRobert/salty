# Salty — Feature Designs

Fleshed-out, actionable plans for larger features. Written against the current architecture
(SwiftUI + SQLiteData/GRDB, `RecipeListQueryBuilder`, the `recipeCategory`/`recipeTag`
junction pattern, `RecipeToHtml`/`HTMLExportOptions`, and the shared-DB story with SaltyKMP).

**Status:** Meal Planner, Cookbook, and Smart Lists are *not* implemented — those sections are
plans. **Chef View v1 is built** (all three phases); its section is now history plus the v2
backlog. **Shopping Lists are built and synced end to end** (Swift client, SaltyKMP client, and
Salty Server). That section is history and rationale, not a plan.

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

## Feature 4 — Chef View — BUILT (v1, all three phases)

**As built, and where it differs from the plan below:**

- Files: `SaltyCore/ChefStep.swift` + `ChefViewDisplayStyle.swift`; `Salty/Views/ChefView/`
  (`ChefView`, `ChefViewHeaderBar`, `ChefViewIngredientsPane`, `ChefViewDirectionsList`,
  `ChefViewFocusStepView`, `ChefViewControlsBar`, `ChefViewTextSize`, `ChefViewWindowView`);
  `ChefViewModel` + `ChefViewSessionStore`; `ChefSessionState` + `ChefViewLaunch`;
  `ScreenSleepBlocker`, `ChefViewOpenAction`, `RecipeLastPreparedWriter`. Tests:
  `ChefStepTests`, `ChefViewModelTests`.
- **Menu command uses a focused scene value** (`ChefViewOpenAction`, mirroring
  `SearchFieldFocusAction`), *not* the NotificationCenter pattern the plan named: a notification
  fires in every open window at once, and this command has to mean "the recipe in front of me".
  ⇧⌘C, in the View menu next to Sort By.
- **No string catalog.** The plan called for manual symbol keys in `Localizable.xcstrings`; the
  app has no catalog and every user-facing string is a literal, so Chef View matches. Adding one
  is a separate, app-wide job.
- **Toolbar icon:** `rectangle.stack.badge.play`, from Rob's finalists. One-line swap in
  `RecipeDetailView` if `play` / `frying.pan` reads better in practice.
- **Step identity is the index into `recipe.directions`**, not `Direction.id` — imported ids
  aren't guaranteed unique within a recipe. Blank direction rows are dropped rather than rendered
  as an empty giant step.
- **"Next" completes the step it leaves; "Previous" un-completes the one it lands on** — so
  working through with the bottom bar alone leaves the check-offs right, and stepping back and
  forth doesn't mark the whole recipe done. Next never moves or swaps out: it stays in place and
  disables once the last step is checked off (`ChefViewModel.canAdvance`), because buttons
  shouldn't relocate under hands that have learned where they are.
- **"Made It!" is a quiet link, not a prominent button** ("Mark as Prepared Today", `.link` style
  on macOS as the detail view's "Scale…" does). Always available — you may not check off every
  step — but never competing with Next.
- **Text size is a discrete slider in a popover**, not the inline A−/A+ pair first built: one drag
  crosses the whole range (six taps to reach TV sizes was too many), `step: 1` keeps it on the
  fixed ladder of sizes, and the flanking A's stay tappable for single steps. The popover exists
  because an iPhone header bar has no room for a draggable slider inline.
- At compact width the bottom bar's chevrons drop their titles; everything in both bars is
  `fixedSize`, or a tight bar compresses button titles until they wrap one letter per line.
- Chef View is reachable from `RecipeDetailView` only, so the `webPreviews` alternate detail view
  (`RecipeDetailWebView`) has no entry point.
- `RecipeNavigationSplitViewModel.setLastMade` now delegates to the shared
  `RecipeLastPreparedWriter`, which "Made It!" also uses.

The original plan follows.

A full-screen, large-print view for actually cooking from a recipe: legible from across the
kitchen (and, via AirPlay mirroring, from a TV — this is the "Chef View + AirPlay first" step
of the Apple TV direction). **Pure presentation — no new tables, no migrations, no sync**, so
the cross-cutting migration/sync concerns above don't apply. Session state is in-memory only.

Naming: **Chef View** (decided 2026-08, over "Cook Mode"/"Cook View"). Three reasons:
MacGourmet called this exact feature "Chef View" and Salty ships a MacGourmet importer, so
migrating users already know the name; "view" is truthful ("this recipe, shown differently")
where "mode" implies app-wide state; and it stays clear of the `Cook*` prefix the Cookbook
feature already owns (`ChefView` vs `CookbookView` — unambiguous in menus and code). For
context, competitors converge on the generic term: Mela "Cook Mode", Crouton "Step by Step
Mode", plus "Cook(ing) Mode" in Paprika/NYT/Samsung Food — another point for a distinctive name.

### Decisions taken (2026-08)

1. **Default display: continuous list with a current-step highlight.** All steps stay visible
   in one large-print list; the *current* step is full-contrast and slightly larger, completed
   steps dim, upcoming steps remain fully readable. Tap any step to make it current;
   auto-scroll keeps it comfortably placed. Rationale: strict one-step-at-a-time views get in
   the way more than they help ("what did step 4 say?"), but a current-step concept preserves
   most of the focus benefit.
2. **Focus mode (one giant step at a time) is a toggle *inside* Chef View**, not a
   Settings item: huge left/right tap zones + swipe for prev/next, "Step 3 of 9" progress.
   Best for TV mirroring and messy hands. Last-used mode persists via
   `@AppStorage("chefViewDisplayStyle")` (a `RawRepresentable` enum in SaltyCore, per the
   `RecipeHtmlTheme` pattern).
3. **Progress survives within the app session, not across relaunch.** Checked ingredients,
   completed steps, and current step live in an in-memory, app-level store keyed by recipe id
   — you can leave Chef View, glance at another recipe, and come back. No DB writes, no
   staleness/expiry questions. Persist-across-relaunch can be revisited if interrupted cooks
   prove common.
4. **Timers are v2**, not v1 (see below).
5. **macOS presents as a dedicated window** (new `WindowGroup` scene, like
   `recipe-detail-window`), so the Chef View window can go full-screen on an external display/TV
   while the main app stays usable. iOS/iPadOS uses `fullScreenCover` (the
   `CreateRecipeFromWebView` precedent, `#if !os(macOS)`) — presented locally from
   `RecipeDetailView` rather than `RootPresentationsModifier`, because the detail view owns
   the live ingredient-scale state the cover needs, and local presentation makes Chef View
   available from every context that hosts a detail view (split-view column, macOS
   recipe-detail window) for free. `RootPresentationsModifier` stays reserved for
   root-launched sheets.

### Layout (adaptive, wide-screen first)

- **Regular width / landscape:** two panes — ingredients pinned left (~1/3, scrollable,
  checkable), directions right. This is the iPad-landscape / TV composition.
- **Compact width:** directions full-screen; ingredients one gesture away (bottom drawer or
  segmented flip — ingredients matter early, directions dominate mid-cook).
- Visual language matches `RecipeDetailView`: `.fontDesign(.rounded)`, high contrast, works
  in light/dark. Headings (`isHeading`) render as section headers in both panes; step numbers
  reuse the existing prefix-count-of-non-headings convention.

### v1 features

- **Entry points:** prominent "Chef View" toolbar button on the recipe detail view; macOS
  menu command + shortcut via the existing `NotificationCenter` pattern
  (`RecipeNavigationSplitViewModel` notification names + `Menus.swift`).
  **Icon:** the button always carries its text label (per AGENTS.md), so the icon is
  reinforcement, not the sole signal. Rob's preference: `play` (outline) or
  `rectangle.stack.badge.play` ("stack of steps, play" — a nice semantic fit); other
  candidates `frying.pan` (unambiguous cooking, best for icon-only contexts) and
  `play.fill`/`play.circle`. SF Symbols has **no chef's hat** — that would need a custom
  symbol asset (possible later refinement, and the best identity match for the name).
  Try the finalists rendered in the actual toolbar during phase 1 and pick visually.
- **Keep screen awake** while Chef View is open — new capability for the app.
  `UIApplication.shared.isIdleTimerDisabled` on iOS (set on appear, *always* cleared on
  disappear; the one justified UIKit touch), `ProcessInfo.beginActivity(.idleDisplaySleepDisabled)`
  on macOS.
- **Check-off** for ingredients *and* steps — large tap targets, `checkmark.circle.fill`
  convention from `ShoppingListDetailView`.
- **Text-size stepper (A / A)** in-view: overrides `\.dynamicTypeSize` on the Cook subtree
  (stepping into the accessibility sizes) rather than hard-coding point sizes — default
  Dynamic Type tops out below 10-foot legibility. Persisted as `chefViewTextSize`. This is
  the app's first deliberate text-size override; it stays inside the semantic-font system,
  which is the escape hatch AGENTS.md's "prefer Dynamic Type" rule intends.
- **Scaling passthrough:** entering Chef View with ingredient scaling active carries
  `ingredientScalePercent` in; quantities render via the existing
  `IngredientScaler.displayParts(for:scaleFactor:)` with the same footnote treatment. (The
  macOS window receives `recipeId` + scale percent as its Codable window value.)
- **"Made it!"** on completion (last step / finish screen) → existing
  `setLastMade(_:forRecipeIds:)`.

### Architecture

- `Salty/Views/ChefView/`: `ChefView` (adaptive shell), `ChefViewIngredientsPane`,
  `ChefViewDirectionsList` (continuous), `ChefViewFocusStepView`, `ChefViewControlsBar`.
- `ChefViewModel` (`@Observable @MainActor`, in ViewModels — follows the
  `RecipeDetailView` → `RecipeDetailViewModel` convention): current step, next/prev that
  skip `isHeading` rows, "Step X of Y" counting, check-off sets, display mode, completion.
  **Unit tests in SaltyTests** for step navigation/numbering around headings — this logic is
  exactly the kind that regresses silently.
- `ChefViewSessionStore` (`@Observable @MainActor`, app-level `@State` in `SaltyApp`,
  injected via `.environment`): `recipeId → session state` map implementing decision 3; also
  what lets the macOS window and a re-entered iOS cover share progress.
- User-facing strings as manual symbol keys in `Localizable.xcstrings`.

### v2 candidates (deliberately out of v1)

- **Tappable step timers** — detect durations in step text (regex precedents:
  `RecipeFromTextParser.swift`, `SchemaOrgRecipeJSONLDExporter.swift`), render as chips that
  start countdowns with local notifications. Own chunk of work: timer state, notification
  permission, multiple concurrent timers.
- **True external-display scene** — non-mirrored AirPlay where the TV shows Chef View while
  the phone shows something else. Plain mirroring works free in v1; this is also the bridge
  toward the phone-driven tvOS app direction.
- Voice / hands-free step advance.

### Phasing

1. Shell + presentation (iOS cover, macOS window, entry points), continuous layout with
   current-step highlight, keep-awake, session store.
2. Focus mode + in-view mode toggle; text-size stepper.
3. Check-off, scaling passthrough, "Made it!", polish (auto-scroll behavior, compact
   ingredients drawer).

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

## Browser hand-off — URL scheme and share extension BUILT (v1)

Goal: send a recipe page from a browser into Web Import with one tap or click. Decided 2026-10-13
after weighing the options: a web-page "Open with" handler and Universal Links are out (only the
default browser handles http(s); Universal Links need a domain we own), and command-line arguments
don't reach a running app — so everything funnels through one `salty://` entry point.

### What shipped (2026-10-16)
- `SaltyURL` (`Salty/Helpers`) parses and builds the links; `SaltyURLTests` pin the grammar. The host
  is the verb: `salty://import?url=<page>` and `salty://recipe/<id>`. Imports accept http(s) only
  (https assumed when the scheme is missing, as the address bar does); a recipe link is only ever an
  id to look up.
- `MainView.onOpenURL` dispatches. Import → `RecipeNavigationSplitViewModel.webImportRequest`, which
  the root presentation modifier turns into the full-screen cover (iOS) or the
  `create-recipe-from-web-window` (macOS; now `WindowGroup(for: URL.self)`, one window per page).
  Recipe → `showRecipe(id:)` (All Recipes, filters cleared, selected, scrolled), with an alert when
  the id isn't in the library. Pre-26 systems get an alert for import links.
- `CreateRecipeFromWebViewModel.importPage` loads the page and runs the existing scan once the
  navigation finishes. Nothing is saved automatically: the scan fills the import exactly as the Scan
  button does, and the "no recipe data" alert still shows when there's nothing to find.
- `ImportRecipeFromWebIntent` (`Salty/Intents`): the Shortcuts action takes a URL, validates it through
  `SaltyURL.importLink(for:)`, and returns `OpenURLIntent` on the salty:// link, so there is exactly
  one code path. A one-action shortcut with "Show in Share Sheet" is the iOS share-sheet route.
- Docs: README "Sending a Recipe Page to Salty"; the Web Import start page has the bookmarklet.
- **Share extension `SaltyShareExtension`** (added 2026-10-16, one target for both platforms; the project file
  was edited by hand -- `D4A5E0…` object ids). Activation: one web URL. macOS: `NSWorkspace.open` on
  the `salty://import` link and done, so Safari's Share button and Chrome's/Firefox's File ▸ Share all
  land in Web Import. iOS: a share extension can't open its app, so the URL goes into `ImportInbox`
  (App Group `UserDefaults`, `SaltyShareImport/`) and the sheet says "Sent to Salty"; `MainView` takes pages
  out one at a time on `scenePhase == .active` and whenever the Web Import cover closes
  (`RecipeNavigationSplitViewModel.isWebImporterPresented`). `SaltyShareImport/` (also `SaltyURL`) is a
  synchronized folder in both targets. The App Group is iOS-only: `Salty/Salty-iOS.entitlements` via
  `CODE_SIGN_ENTITLEMENTS[sdk=iphone*]`, with the id from the `SALTY_APP_GROUP` build setting on both
  targets (`group.com.inuvro.salty-dev` / `group.com.inuvro.salty`) and surfaced to code through the
  `SaltyAppGroup` Info.plist key. **Version and build number live in one place: the project-level
  user-defined settings `SALTY_VERSION` / `SALTY_BUILD`** (Project ▸ Build Settings ▸ User-Defined, or
  the two `SALTY_*` lines in each project-level configuration of the pbxproj). The app and the extension
  set `MARKETING_VERSION = $(SALTY_VERSION)` and `CURRENT_PROJECT_VERSION = $(SALTY_BUILD)`. Note that
  a target's General tab *resolves* these and shows plain numbers, with nothing to say they are
  inherited -- bump at the project level, never by typing into a target's General tab (that writes a
  per-target literal and forks them again; the Build Settings tab is where the `$(…)` is visible). A
  "Check Version Settings" run-script phase on both targets fails the build with directions the moment a
  target's resolved `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` differs from `SALTY_VERSION`/`SALTY_BUILD`,
  so a slip in the General tab is caught at the next build rather than at upload. The point:
  an appex carries its app's version by convention; a mismatch isn't a rejection, App Store Connect
  only sends an ITMS-90473 warning email after the upload. The display name uses the same trick:
  project-level `SALTY_DISPLAY_NAME` ("Salty Dev" in Debug, `Salty` in Release) is what every
  `INFOPLIST_KEY_CFBundleDisplayName` line in the app and the extension points at, so the Info tab's
  habit of rewriting that key into both configurations can no longer turn the Release app into
  "Salty Dev" (it had, for the fourth time, right before this change).

### Known limits
- Web Import reloads the page in its own WebView: no shared cookies with the browser, so paywalled or
  signed-in pages show their login wall. Only reading the live page (a share extension's JS
  preprocessing, or a browser toolbar extension) avoids that.
- Debug and Release builds both register `salty://`; LaunchServices picks one. Use
  `open -b com.inuvro.salty-dev 'salty://…'` to target the dev build.
- The scan runs on `.finished`; pages that inject their JSON-LD late may need a manual Scan.
- iOS inbox pages open when the app *becomes* active. In iPad Split View next to Safari the app may
  already be active, so the page waits until the next foreground transition; a Darwin notification
  from the extension would close that gap.
- The responder-chain `UIApplication.open` trick that would let the iOS extension open the app is
  unsupported and may break or be rejected; deliberately not used.

### Recipe links -- Copy Private Link and Open Recipe (2026-10-17)
Earlier (2026-10-16) "Copy Link" was held back: a `salty://recipe/<id>` link only resolves in the
user's own library, so next to Share it would read as a sharing feature. Built once the name says so
and Shortcuts consumes it -- 1Password's "Copy Private Link" vs. "Share" is the model.
- **Copy Private Link** (`RecipeLinkPasteboard`): in the recipe context menu with Get Info (not with
  Share/Export), and Edit ▸ Copy Private Link after the pasteboard group (OmniFocus keeps "Copy as
  Link" there), enabled for exactly one selected, saved recipe via `RecipeSelectionCommands`. Writes
  the link as both URL and plain text. No keyboard shortcut yet.
- **Open Recipe** (`OpenRecipeIntent`, an `OpenIntent`) over **`RecipeEntity`** (`Salty/Intents/`):
  properties Name, Private Link, Favorite, Want to Make; the picker shows the thumbnail and the first
  line of the summary. `RecipeEntityQuery` (an `EntityStringQuery`) reads through `RecipeEntityLookup`:
  ids in the order asked, name search with `localizedStandardContains` (case- and
  diacritic-insensitive, unlike the list's `LIKE`), suggestions = favorites by name then most recently
  modified, 50 at most. `perform()` (in the app's process, after the system has brought it forward)
  leaves `.recipe(id:)` in `SaltyLinkInbox`; the frontmost `MainView` takes it and runs the same
  `open(_:)` as `onOpenURL`, so a pasted link and the action share one handler and one "isn't in this
  library" alert. Returning `OpenURLIntent` on the link does NOT work: Shortcuts fails the action with
  "The provided URL scheme `salty` is unsupported; launch is prohibited" (LNURLLaunchRequestErrorDomain
  1, iOS 27 simulator, 2026-10-17). `URLRepresentableIntent` would need no `perform()`, but it takes
  universal links only. Verified end to end in Shortcuts on the iOS simulator (picker lists library
  recipes with thumbnails; running it shows the recipe).
- **Import Recipe from Web had the same bug, fixed the same way.** `ImportRecipeFromWebIntent`
  returned `OpenURLIntent` on its `salty://import` link and failed with the same error. That is the
  route the README gives for a one-tap iOS share-sheet shortcut, so it was broken since it shipped.
  It now opens the app (`openAppWhenRun`, plus `supportedModes = .foreground` on OS 26, where
  `openAppWhenRun` is deprecated) and leaves the link in `SaltyLinkInbox`. Verified in Shortcuts on the
  iOS simulator: Web Import opened on the page and ran its scan. Not tried from Safari's share sheet
  itself, nor on the Mac.
- Not done: Spotlight (`IndexedEntity` + `CSSearchableIndex`; the `OpenIntent` is already the piece it
  needs), an `EntityPropertyQuery` for Shortcuts' "Find Recipes where…", App Shortcuts phrases.

### Considered and not planned
- Importing inside the share extension (Safari's JS preprocessing reads the live page's JSON-LD, so
  paywalled/signed-in pages import without a login wall). Judged overkill on 2026-10-17: the current
  reload-in-Web-Import behavior is fine. If it comes back, send the JSON-LD through the App Group inbox
  and let the app scan it with `SchemaOrgRecipeJSONLDImporter`, rather than putting SaltyCore (and its
  database rules) in the extension.
- Universal Links only if a public domain appears. Registering the same `salty://` grammar in the KMP
  and Uno clients (Android intent filter, Windows protocol registration) is set aside for now.

---

## Suggested build order

**Chef View is orthogonal** — no schema, no sync, no query-engine dependency — so it can ship
before, between, or in parallel with any of the three below. Among the schema-bearing features:

1. **Smart Lists / Advanced Search** first — it deepens the query engine that everything else
   benefits from, has the strongest existing foundation, and the sidebar slot is already stubbed.
2. **Cookbook** second — mostly presentation over the existing HTML/print stack; low schema risk.
3. **Meal Planner** third — the most new UI surface (calendar), and its best feature
   (shopping-list generation) reuses `IngredientScaler`/`ShoppingList` which are stable.
