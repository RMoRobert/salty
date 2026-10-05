# Salty code review — 1 October 2026

**Scope.** `Salty/` (SwiftUI app), `Packages/SaltyCore` (portable core and `SaltyCoreApple`), `SaltyTests/`. HEAD `c940862`, clean tree. Reviewed against `AGENTS.md`, Apple HIG and accessibility guidance, standard SwiftUI usage, and the stated goal of reusing SaltyCore from Uno, WinUI, Compose or SwiftCrossUI front ends.

**Method.** A mechanical sweep (grep) over every Swift source; a from-scratch macOS build into a scratch DerivedData to harvest compiler warnings (`BUILD SUCCEEDED`, 15 distinct warnings in project sources); eight parallel read-through passes by area, each reading every assigned file in full; every High finding and most Medium findings below were re-checked by me against the source. Nothing was run on a device or simulator, so "repro" steps are derived from reading, not execution. No files were modified. SwiftLint is not installed on this machine, so the `AGENTS.md` lint rule could not be checked.

**Paths.** `CORE` = `Packages/SaltyCore/Sources/SaltyCore`, `ENGINE` = `CORE/Sync/ServerSyncEngine.swift`, `RNSV` = `Salty/Views/RecipeNavigationSplitView.swift`, `NAVVM` = `Salty/ViewModels/RecipeNavigationSplitViewModel.swift`, `EDITVM` = `Salty/ViewModels/RecipeDetailEditViewModel.swift`.

---

## 1. Verdict

The split into `SaltyCore` / `SaltyCoreApple` / app has landed well. The portable core imports only Foundation, GRDB, SQLiteData, UUIDV7, swift-markdown, SwiftSoup and SwiftHtml; `URLSession` is guarded for `FoundationNetworking`; logging goes through `SaltyLogger`; and the things that most often leak (CoreGraphics, ImageIO, UIKit) stay in the app or `SaltyCoreApple`. The `Writes/` layer, the sync reconciler, the JSON-LD pipeline, the shopping-list merge and the list editor are the strongest code in the project: pure, documented, and tested. Every `@Observable` class is `@MainActor`, there is no `ObservableObject`, no `foregroundColor`, no `tabItem`, no force `try`, and the 734 Swift Testing cases are mostly pure and well explained.

The debt is concentrated, not diffuse:

- **The recipe editor** has three real correctness defects (view model recreated mid-edit, nutrition values ≥ 1000 dropped, stale snapshot written over synced fields) and still bypasses the core writers for categories and tags.
- **The text-recipe parser** classifies any line containing the letter "g" as an ingredient, and three `Int(Double)` conversions on untrusted input can trap the app. None of this has tests.
- **The macOS multi-window story** is broken by design: menu commands are broadcast over `NotificationCenter` to every window, and selection and sheet state are last-writer-wins singletons.
- **Six places** still assign sync stamps by hand or insert rows directly, bypassing the `Writes/` rules that were introduced to prevent exactly that.
- **Views carry logic** that belongs in view models or the core: nutrition parsing, ~200 lines of duplicated text parsing in a scan view, direct `database.write` calls, file I/O, camera controllers, and timing hacks (`Task.sleep` polling, `DispatchQueue.asyncAfter`).
- **Accessibility** is excellent where it was designed in (`StarRatingEditView`, the merge sheet, `RecipeChip`) and absent elsewhere: only 28 of 73 view files carry any accessibility modifier, Chef mode announces nothing, and several labels are wrong (unscaled quantities, replaced menu values).
- **AGENTS.md mechanical compliance** is weak on two rules and strong on the rest: ~200 computed `some View` properties and ~250 hard-coded padding/spacing values, plus seven `ScrollViewReader`s, ten `DispatchQueue` calls, and a dozen `replacingOccurrences` / legacy `Formatter` uses in the core.

Fixing the "Fix first" list below is roughly two to three days of focused work and removes all user-visible data-loss and crash risks. The structural items (command plumbing, generic row editor, decomposition of the three 800–1600-line views) are larger but each pays for itself quickly.

---

## 2. Fix first (ranked)

| # | Where | What | Why it matters |
|---|---|---|---|
| 1 | `RecipeDetailEditDesktopView.swift:19-25`, `RecipeDetailEditMobileView.swift:16-23` | Editor view model is a plain `@Bindable var` created in `init`, not `@State`, so any host re-evaluation replaces it. `RecipeDetailWindowView.swift:39-45` builds the sheet from a `@FetchOne` row that the editor's own `addTag` touches; `RNSV:1288-1298` from `draftRecipe` plus a DB row a sync tick rewrites. | A whole editing session can be silently discarded. `RecipeDetailView.swift:14,30` already shows the right `@State` + `State(initialValue:)` pattern. |
| 2 | `NutritionEditView.swift:244-260, 265-281` | Values load with `Double.formatted()` (grouping on, "1,500") and save with `Double(text)`, which is nil for "1,500" and for "1,5" in comma-decimal locales. | Any nutrient ≥ 1000 (sodium, potassium, calories) is dropped on the next Save even if untouched. Use `.number.grouping(.never)` to load and `Double(text, format: .number)` to parse; move the codec to SaltyCore (§5). |
| 3 | `CORE/RecipeFromTextParser.swift:477-481, 195-199` | Units matched with `lowercased.contains(unit)` over a list including `"g"`, `"c."`, `"oz"`, `"can"`, `"head"`, `"half"`. | Any line with a "g" is an ingredient: `extractRecipeName` (`:62-66`) skips "Grandma's Lasagna", directions with "g" are swept into ingredients. This is the fallback for every iOS 18 / macOS 15 device and every non-Apple client. No `RecipeFromTextParserTests` exists. Match whole words anchored to a quantity. |
| 4 | `CORE/ImportExport/SchemaOrgDuration.swift:27`; `CORE/IngredientScaler.swift:189` (via `CroutonImportRecipe.swift:182,186`); `CORE/ImportExport/SchemaOrgRecipeJSONLDExporter.swift:165` | Unguarded `Int(Double)` on values parsed from unbounded digit runs. | A web page with `"prepTime": "PT99999999999999999999M"`, a `.crumb` with `"amount": 1e19`, or a stored nutrition value ≥ 2^63 traps the app. Guard `isFinite && < 1e15` (or `Int(exactly:)`) at each site and in `mixedFractionString`. |
| 5 | `SettingsView.swift:303` | `.disabled(syncService.isSyncing)` on the row that contains Cancel, which is shown only while `isCancellable` (= `currentSyncTask != nil`, set after `isSyncing = true`). | Cancel is disabled every moment it is visible; `cancelSync()` has no other UI caller. Delete line 303 (Sync Now already has its own guard at 283). |
| 6 | `Menus.swift:203-301`, `RNSV:273-304, 992-1018`; trackers at `Menus.swift:15-71` | 14 `NotificationCenter.post(object: nil)` and 15 `onReceive` handlers broadcast menu commands to every window; `SheetStateTracker` / `SelectionStateTracker` are last-writer-wins across windows. | With two windows, ⌘N opens an editor in both; Print/Export act on each window's selection; a sheet in window B greys out New Recipe in A. Replace with one `@FocusedValue` struct published via `focusedSceneValue`, as `SearchFieldFocusAction` / `ChefViewOpenAction` already do. |
| 7 | `EDITVM:150` | `saveRecipe` calls `RecipeWriter.save`, which writes the editor's stale `imageFilename` / `imageThumbnailData` / `lastPrepared` / `courseId` back over the row; `RecipeWriter.saveBody` (`CORE/Writes/RecipeWriter.swift:117`) exists for this and its doc names the consequence. | A photo or "made it" that arrived by sync or another window while the editor was open is reverted and re-stamped to every device; a recipe deleted elsewhere is resurrected. Use `saveBody` unless `pendingImage.isChange`. |
| 8 | `CORE/Writes/RecipeWriter.swift:140-151` with `CORE/Schema.swift:637` | `insertImported` is documented "Throws if the id is already taken", but the `recipe` PK is `onConflict: .replace`, so a plain `Recipe.insert` silently replaces. Same for `ShoppingListWriter.insert`. | `SaltyId.swift:31-34` anticipates an id-preserving import; that path would overwrite a user's recipe. Check existence first or use a statement-level `insert(or: .abort)`. |
| 9 | Six writer bypasses (details in §4.2) | `AddToShoppingListViewModel.swift:163-171`, `CreateRecipeFromImageView.swift:395-404`, `RecipeDuplicator.swift:63-104`, `CORE/LibraryClassifierEditor.swift:86,104` + `LibraryClassifierResolver.swift:55`, `RecipeImageAccess.swift:46-49,58-61`, `EDITVM:218` + `CategoryEditView.swift:214`. | Unrounded `Date()` stamps and direct inserts are the "one forgotten line from an edit that never leaves the device" that `Writes/` was created to end. |
| 10 | `CreateRecipeFromImageView.swift:260` and `:299` | Two `.sheet(isPresented: $showingRecipeEditor)` on one binding on iOS (one inside `#if !os(macOS)`, one unconditional). | SwiftUI presents one and ignores the other; dismissal desyncs. Delete 260-270. |
| 11 | `ShoppingListFreeformViewModel.swift:139`; both list VMs `181-204` / `135-157`; `SaltyApp.swift:100-105` | `storedText` is set before the write, so a failed write is never retried; the in-flight write `Task` cannot be cancelled by `reloadAfterExternalChange`; nothing flushes editors on `.background`. | Silent loss of shopping-list keystrokes on error, on a sync landing mid-write, or on iOS kill inside the 0.4 s debounce. |
| 12 | `CreateRecipeFromImageView.swift:755-770` = `RecipeImageEditView.swift:485-500` | `startRunning` / `stopRunning` dispatched to a *concurrent* global queue with `nonisolated(unsafe)`, in two verbatim AppKit camera controllers. | A quick appear/disappear can run stop before start and leave the camera on. One `actor CameraSession` shared by both. Camera permission is never requested either (`:653-656`). |
| 13 | `ScreenSleepBlocker.swift:29-40` with `ChefView.swift:100-113` | Hold is reference-counted on `onAppear` / `onDisappear`; the codebase documents double `onAppear` elsewhere. | One extra appear leaves the idle timer disabled for the rest of the session. Use a token or tie to `.task` cancellation. |
| 14 | `ENGINE:124-132`; `ENGINE:2289-2301`; `ENGINE` ×11 `URL(string: "\(serverUrl)/…")` | `deviceId` regenerates a UUID on every access when the keychain write fails and ignores `setDeviceId`'s Bool; per-recipe image failures are only logged and "Sync Complete" is shown; hand-built URLs beside `makeURL` with no scheme check. | Phantom devices and a watermark that never advances; missing images with no counter; the shared engine will POST a password over `http://` on hosts without ATS. |
| 15 | `RecipeImageManager.swift:303-324` | `determineImageFormat` slices `prefix(8)` so the `>= 12` HEIC branch never runs. | iPhone HEIC photos are stored as `<id>.jpg` with HEIF bytes; the filename is the cross-client contract. Use `CGImageSourceGetType` or `prefix(12)`; add a test. |
| 16 | Build warnings (§3) | `Transferable` on `SaltyRecipeExport` forces a retroactive `Sendable`; 10 unused-result warnings. | The project should build warning-free; declare `Sendable` on the five export structs in the core. |

### Progress (same day, uncommitted)

All sixteen fix-first items were implemented and verified by a clean macOS build (zero warnings in project sources), an iOS Simulator build, and the full `SaltyTests` suite on the macOS host (737 tests passing, two new suites). Decisions worth knowing:

- **1** Editor view model now `@State`, seeded in `init` like `RecipeDetailView`.
- **2** New `NutritionValueText` in SaltyCore: shows without grouping, reads strictly by locale then as a plain number, refuses letters. A locale-aware reader was chosen over character filtering because the filter would have to know every locale's separators anyway and the decimal pad already constrains input.
- **3** `RecipeFromTextParser` matches vocabulary as whole words, treats headings as short lines that open with a heading word, stops the title scan at the first section heading, and exposes `parseIngredientLines` / `parseDirectionSteps`; `ScanTextForRecipeView` lost its 200-line copy. Seven tests.
- **4** Duration over a year is shown raw; the scaler and the JSON-LD exporter guard `Int` conversion.
- **5** Cancel is live. A regular sync is genuinely cancellable: the engine checks cancellation between recipes and never stamps completion after a cancel, so the next sync finishes the rest. A force re-sync is deliberately not cancellable.
- **6** Menu commands are scene-scoped focused values (`MainWindowCommands`, `RecipeSelectionCommands`); the two tracker singletons and sixteen notification names are gone. Commands are disabled while a non-main window is frontmost. Compiled and unit-tested, not yet exercised with two windows open.
- **7** `saveBody(_:image:in:)` gained `.keepStored` / `.useEdited`; the editor inserts new recipes and body-saves existing ones, so a deleted recipe surfaces as an error instead of coming back.
- **8** `insertImported` and `ShoppingListWriter.insert` throw `idAlreadyInUse` on a taken id. Imports always mint fresh ids (`SaltyRecipeExport.swift:406`), so importing an updated copy of a recipe you already have still creates a second recipe, exactly as before; an "update existing on import" flow would be a feature on top, going through `saveBody`.
- **9** All six bypasses go through the writers; `LibraryClassifierEditor.create/rename` and the resolver take `now:` and round.
- **11** Freeform editor records `storedText` only after the write succeeds; both list editors keep the write task so a reload can cancel it, and flush when the scene leaves `.active`.
- **12** One `MacCameraCaptureView` in `Helpers/Camera/` with an actor ordering start/stop, camera permission requested, and a message for a denied or missing camera.
- **14** `deviceIdentifier()` resolves once and throws `deviceIdUnavailable` if the store refuses; every request builds its URL through `makeURL`, which trims, strips trailing slashes and requires a scheme and host; plain http is logged, not refused, since ATS already blocks it on Apple and a LAN server may legitimately use it elsewhere; `SyncProgress.imagesFailed` appears in the summary.
- **16** Export structs are `Sendable`; deprecated `contains` → `in`; unused results discarded explicitly.

### Progress, 2026-10-02 (§13 step 4, uncommitted)

Step 4 is complete: pending classification, the generic row editor, and `NutritionEditModel`.

- **`NutritionEditModel` (SaltyCore).** One value holding the serving-size text and a text per amount (`Field`, with `unit` and `section` enums so a front end labels them), read and written through `NutritionValueText` in the editor's locale. `isValid(_:)` / `invalidFields` drive the warning and the Save button; `nutrition` is nil when every field is blank and otherwise the amounts under the *original's id* (the view used to mint a new id on every save, so an untouched nutrition sheet registered as an unsaved change); `hasChanges` compares stored values, so "12.50" for 12.5 is not a change. `NutritionEditView` keeps only layout and the English labels; its thirty-five `@State`s and the hand-rolled save are gone. Six tests in `NutritionEditModelTests` (US and German locales).

- **Categories and tags are held until Save.** `RecipeClassificationDraft` (app `Models/`) carries the selected category ids, selected tag ids, and the names of tags the library doesn't have yet; `RecipeDetailEditViewModel` loads it in `.task` (`loadClassification()`), shows names from it, and `saveRecipe` resolves new tag names through `LibraryClassifierResolver` and applies everything with `RecipeClassificationWriter.set` in the same transaction as the body save (the stamped row is read back so the editor holds the bumped clock). Cancel now cancels tags and categories; a cancelled edit leaves no stray tag; `hasUnsavedChanges` sees classification and, for new recipes, every field. The `@FetchAll`s over the whole `recipeCategory` / `recipeTag` tables are gone from the editor VM. Six tests in `RecipeClassificationDraftTests`.
- **`CategoryEditView` is a pure picker** over a copy (`CategoryEditViewModel`), handed back on Save; the recipe binding, the direct junction writes and the "only write when non-empty" guard are gone. Creating a category is still an immediate library write (through `LibraryClassifierEditor`), the same as the library editor. `CreateRecipeFromWebViewModel.saveRecipe` uses the classification writer too.
- **One generic row editor.** `RecipeRowListEditor<Item, Row>` owns the drop indicators and end zone, the width measurement, move/delete, the focus-after-add and the standalone `ScrollView` + `ScrollPosition` (so a long list in a sheet scrolls instead of clipping, and `ScrollViewReader` is gone). `RecipeRowContext` is what rows get; `RecipeRowDragHandle` adds Move Up / Move Down / Delete as a context menu and as accessibility actions; `RecipeRowActionButtons` is the shared add/delete/handle group; `RecipeRowEditorShell` is the standalone-vs-embedded chrome. The five editors are ~60–110 lines each (were 270–470); `ComboButtonRepresentable` (NSComboButton) stays, by request, as the "New Ingredient" split button (a `ControlGroup` of Button + Menu was tried and looked wrong); the preparation-times `Grid` became an HStack with equal-width fields.
- **Verified in the running app** (real mouse and key events, AX reads): a new row takes focus; ⌘⌥↑ / ⌘⌥↓ reorder with focus following; ⌘N adds a row; the category popover opens with Cancel and a Save disabled until a change. Not verified visually: the tag chip after Add Tag (below the fold in the capture).
- **Two findings while verifying.** (1) Focus-after-add needs a short wait on macOS: `task(id:)` runs before the row's `NSTextField` exists, and a focus request with nothing to receive it is dropped (probe showed "row appeared" after the task started). One 100 ms wait lives in `revealNewRow()` instead of five. (2) `onKeyPress` on a row's *container* never sees the key when a text field inside it has focus (the system beeps), so `RecipeRowKeyboardReordering` stays on each text field, via `context.keyboardReordering`. Also: a `Menu` can't own a `keyboardShortcut`.
- **Known, pre-existing:** ⌘N is bound by all five sections of the embedded editor; whichever SwiftUI registers first (Directions, today) wins. Scoping it to the section whose row has focus would be a small follow-up in `RecipeRowEditorShell`.

### Progress, 2026-10-02 (§13 step 5, uncommitted)

- **`MainSheet`** (`Views/MainSheet.swift`): one optional replaces the nine sheet Bools threaded through `RecipeNavigationSplitView` → `SidebarColumnView` / `RecipeListColumnView` → `RootPresentationsModifier`; `isAnySheetShown` is `activeSheet != nil`; the sheet bodies live in `MainSheetContent`, the iOS web importer keeps its full-screen cover through a derived binding. The root file is 1452 lines (was 1527) with the presentations and the three sidebar/library/duplicate sheets collapsed; the full split into files listed in §9 is still open.
- **Selection follows the rows.** `RecipeNavigationSplitViewModel.reconcileSelection()` intersects `selectedRecipeIDs` with the loaded rows whenever `recipes` changes (scope switch, un-favouriting, a sync delete, a search), except while a just-saved or imported recipe is on its way: `pendingRecipeID` replaces `shouldScrollToNewRecipe`, and the view scrolls when `reconcileSelection()` reports that row has arrived -- which retires the 50 ms / 5 s `waitForSettledRecipeRow` poll (the three catch-up `scrollTo`s stay). A multi-selection shows "N Recipes Selected" in the detail column instead of an arbitrary member.
- **`RecipeListSettings`** (`Models/`): the one `@Observable` owner of sort order, sort direction and search fields, persisted under the same `UserDefaults` keys. The menu bar, the iOS More menu and every main window's view model read and write this instance, so a change in one place reaches the others by observation. Gone: `SearchOptionsTracker`, the `UserDefaults.didChangeNotification` block observers in `Menus` and the view model (with their `assumeIsolated` wrappers and the `removeObserver(self)` that never removed them), the `@AppStorage` sort properties in `Menus`, and the view's hand-built query id (`viewModel.recipeQueryKey` now). Verified with two windows open: Sort By from the menu bar reorders both lists. Four tests.
- **Sync prompt and banner in one window.** `MainView` shows the enrolment prompt and the auto-sync failure banner only in the key window (`controlActiveState` on macOS, `scenePhase` elsewhere); the shared runners are unchanged.
- **One delete transaction.** `deleteRecipes(ids:)` is the single path for a row's Delete, a swipe across rows (which ran one transaction per row inside `withAnimation`) and the selection; deleted ids leave the selection.
- Small: `SampleData` dates are days again (`60*60*24`); unreferenced `RecipeDirectionView.swift` deleted.
- **Not done from §4.6:** `OpenDBView` synchronous database open; `RecipeFullImageView`'s dead notifications and `NSEvent` monitor.
- **On `@AppStorage` keys in SaltyCore (§5).** Chosen: the core keeps the enums and the key *names* (`RecipeListSearchOptions.userDefaultsKey`, `ChefViewDisplayStyle.storageKey`), because other clients store the same values under the same names, and each front end owns an observable settings object over its own store -- `RecipeListSettings` over `UserDefaults` here; Compose would wrap DataStore, WinUI `ApplicationData`. The core never reads a store. If a non-Apple client ever wants core code to read settings itself (print options, say), the pattern already in the core is the one to copy: a small protocol like `SyncSettingsStore` injected by the host, not a key-value store the core opens. The SF Symbol names (`ChefViewDisplayStyle.symbolName`, `LibraryClassifier.systemImage`) are still in the core; moving them is a mechanical app-side extension when next touched.

---

### Progress, 2026-10-02 (§13 step 6, uncommitted)

Shopping lists, plus the Chef items and the delete-path inconsistency from §4.4. Verified by a
warning-free macOS build, an iOS Simulator build, the full SaltyTests suite on the macOS host (771
tests, 91 suites), and a two-window run of the dev app driven by real events: an item typed in a
standalone list window appeared in the main window's checklist of the same list, and the reverse;
the window being typed in kept focus and cursor while its own save landed; deletions propagated the
same way. Chef View reopened on step 9 after being closed there (continuous style).

- **Guarded update.** `ShoppingListWriter.update(id:in:now:expecting:_:)` takes a `ShoppingListStamp`
  (new core type: the loaded `lastModifiedDate`, nullable so a never-stamped legacy row is a state an
  editor can expect) and throws `ShoppingListWriterError.modifiedElsewhere` when the stored row's stamp
  differs. The parameter is defaulted, so existing callers — and the FFI checkout — compile unchanged.
  `AddToShoppingListViewModel` and the rename path stay unguarded: they only add to what is stored.
  Four writer tests cover match, mismatch (row left alone), the nil stamp, and the unguarded path.
- **Notifier retired.** `ShoppingListChangeNotifier`, the two `editorToken`s, the `shoppingListChanged`
  hook in `ServerSyncEngine.init` (and its three call sites plus the now-unused list-id read in the
  force re-sync) and the `SaltySyncService` wiring are gone. Nothing outside the app passed the hook
  (checked the SaltyXP share: only its copy of the app file). Each editor view model now holds
  `@FetchOne var storedRow` on its own row; the view's one `onChange(of: viewModel.storedRow)` hands
  changes to `storedRowDidChange(to:)`, which keeps the row's stamp, ignores a repeat, recognises its own
  write by contents (`writtenItems` / `writtenText`, or contents equal to what is shown), and otherwise
  takes the outside row, dropping any pending save as before. `reloadAfterExternalChange()` is gone.
- **Writes queue instead of cancelling.** `persistNow()` chains each write behind the previous one
  (`await previous?.value`) and reads the stamp to expect only once that write has recorded its own;
  cancelling an in-flight write that had already committed would have left the next save expecting the
  old stamp and refused. Only an outside change cancels. A refused save is logged at info and dropped —
  the observation delivers the newer row. The debounce interval is injectable (`debounce:`), and
  `settle()` awaits the pending save and its write, for tests.
- **Editor view-model tests.** `ShoppingListDetailViewModelTests` (11) and
  `ShoppingListFreeformViewModelTests` (8): load, debounce, flush, flush-with-nothing-pending writes
  nothing, outside write replaces and drops the pending save, deleted row, own write coming back leaves
  later keystrokes alone, repeat delivery ignored, stale save refused, legacy unstamped row, conversion
  to freeform, typing back to the stored text schedules no save. They drive `storedRowDidChange(to:)`
  with rows read back by raw SQL (a StructuredQueries builder instantiated from the test bundle crashes
  the whole suite — see the note in RecipeWriterTests). The notifier's six unit tests were deleted and
  the one server-edit test that counted announcements now checks the rows instead.
- **Chef.** `ChefViewDirectionsList` scrolls `onChange(initial: true)`, without animation on the first
  pass. `ChefViewModel.steps` / `cookableSteps` are stored, re-derived when the recipe snapshot is set.
  `ChefSessionState.recipeLastModifiedDate` records which revision of the recipe the progress belongs to;
  `ChefViewModel` resets the session when the stamp no longer matches (test added). Observed, not
  changed: on macOS the continuous list scrolls the current step only into view, not to centre, same as
  at HEAD.
- **Delete paths.** iOS swipe-to-delete on recipes and on shopping lists now goes through the same
  confirmation as the toolbar, context menu and ⌘⌫ (`confirmDelete(ids:)` + `deleteCandidateIDs` in
  the recipe list column, the existing `confirmDelete` in `ShoppingListsListView`). There is no trash to
  recover from, which is the Reminders behaviour for lists. `deleteSelectedRecipes()` had no callers
  left and was removed.
- Noticed, not done: `appDatabase()` in `.test` context leaves one sqlite per test in the dev app's
  container `tmp` (1,600+ files by now) — a §11 hygiene item to add to the sleeps/UserDefaults list.

### Progress, 2026-10-02 (§13 step 7, engine test suites, uncommitted)

Seven of the ten §11 suites (1–6 and 9), 32 tests, all passing with the rest of the suite (803 in
total). Not done from the ten: 7 was already landed with fix-first item 3, 8 (`RecipeDuplicator`) and
10 (`AutoSyncCoordinator`, which still needs its injection seams first). The §11 hygiene list is
untouched except where the new harness sidesteps it.

- **Harness.** `SyncEngineTestSupport.swift` drives `ServerSyncEngine` directly instead of through
  `SaltySyncService`: an in-memory `DatabaseQueue` with every shared migration, `InMemorySyncSettings`
  and `InMemorySyncImageStore` beside the existing in-memory credential store, and
  `SyncEngineStubURLProtocol`, which routes on method + path (+ query substring), serves a route's
  responses in sequence (409 then 200), and records each request *with its body* (read from
  `httpBodyStream`). No `UserDefaults`, keychain or filesystem; `syncBaseRoutes(lastSync:)` covers
  token check, device registration and completion. Wire types without public initialisers
  (`ServerRecipe`, `ServerRecipeManifestEntry`) are built via `ServerRecipe.from` and a local encodable
  manifest shape.
- **`ServerSyncEngineUploadTests` (5).** Newer local → one PUT, no POST, no force header, agreement
  stamped at the uploaded date; absent on server → one POST; equal stamps → no recipe request and the
  row still marked agreed; a 101-recipe first sync consumed over two pages; a delta short of
  `X-Total-Count` throws before any row is written or the sync completed.
- **`ServerSyncEngineBodyDownloadTests` (3).** A newer server body keeps the local image columns and
  the newer local prepared pair; a dangling `courseId` is nulled while a known one is kept; category
  and tag links follow the body only to classifiers that exist locally.
- **`ServerSyncEngineImageSyncTests` (8).** Every branch: equal stamps + server file only → one GET;
  local filename with the file missing → re-download; local newer without bytes → DELETE carrying the
  stamp; local newer with bytes → multipart POST carrying the stamp; server newer removal → local
  cleared and the file deleted; unchanged → no image request; all failed → `SyncError` and no
  completion, `imagesFailed` tallied; one failure beside a success → completes with both counted.
- **`ServerSyncEnginePreparedDateTests` (3).** Newer local stamp piggybacks exactly one PUT carrying
  the pair with the body stamp unchanged; newer server stamp lands by targeted UPDATE with
  `lastModifiedDate` byte-identical and no PUT; a nil stamp never wins.
- **`ShoppingListSyncConflictTests` (2).** Dirty + server moved → merge, POST with `baseRevision` 2,
  409 → re-merge against the carried row, POST with `baseRevision` 3, accepted row lands clean at
  revision 4; two 409s → row left dirty at revision 1 and the sync still completes.
- **`AgreementStoreTests` (6)** and **`RecipeLastPreparedWriterTests` (5)**, including the
  wire-millisecond rounding and `localNoon` on both 2026 DST days in whatever zone the host runs.
- Learned, for the §11 hygiene pass: the base migrator seeds 16 default courses and categories, which a
  fresh library uploads on every engine test (so `itemsUploaded` is not "recipes uploaded"), and the
  base schema predates the prepared stamp, so a pre-shared-migration library can't take
  `RecipeWriter.save`.

### Progress, 2026-10-02 (§4.5 sync hardening, uncommitted)

- Own-writes verdict now taken on GRDB's writer queue at commit time (`SyncActivity`, a lock-guarded mirror of `isSyncing`); `markAgreed` / `markAllAgreed` (recipe and classifier) skip rows already stamped at their current `lastModifiedDate`, so a quiet sync writes nothing.
- Delta pagination bounded by the first page's `X-Total-Count` (`total/size + 1` pages), or 10,000 pages without one. Not unit-tested: the no-total cap is too large to reach in a test.
- Body uploads take PUT/POST from the manifest (no HEAD); `checkExists` rethrows network errors instead of guessing "absent".
- Recipe tombstones whose id exists locally again are dropped, not pushed. A recipe the server lacks gets no image upload.
- Auto-sync backs off after failures (1, 2, 4, 8, 16, then 30 min), retries pending edits when the backoff ends; Retry ignores it.
- `enroll` / `signOut` cancel a running sync (or wait for a force re-sync) before touching credentials.
- Keychain `save` is `SecItemUpdate` with add fallback; the protection upgrade flag is only set when every rewrite succeeded.
- Thumbnails come from `CGImageSourceCreateThumbnailAtIndex` (one ImageIO path for both platforms, 900 px square JPEG, as before on iOS).
- Every engine response is capped at 64 MB; server messages are one line, at most 300 characters; `friendlySyncMessage` caps unknown error text and words an oversized response.
- New `SyncHardeningTests.swift` (13 tests). Suite: 816 passing. macOS and iOS builds clean.
- `ManualSyncRunner` now uses `friendlySyncMessage` like every other surface.

### Progress, 2026-10-02 (§4.6 full-image view and open-database screen, uncommitted)

- Full-image view: zoom and pan state moved into `ImageZoomState` (tested); ⌘= / ⌘− / ⌘0 are hidden keyboard-shortcut buttons and Esc is the close button's cancel action, replacing the `NSEvent` monitor and the notifications (three of which were never posted). `MagnifyGesture`, `dismiss`, `.plain`, `onGeometryChange` replace the deprecated spellings and the `GeometryReader`. Not exercised in the running app yet.
- Open-database screen: `DatabaseLocationViewModel` runs the new-folder check (`checkLibrary(atPath:)`, a `DatabaseQueue` that migrates and then closes) off the main actor, so "Opening database…" draws; Revert now uses `clearCustomLocationBookmarks` like Settings and updates the shown location.
- Thumbnails kept at 3x (900 px), as before on iOS.
- Suite: 824 passing. macOS and iOS builds clean.
- Decided: the sync failure banner in every window is fine; the password prompt in every window is rare enough to leave.

### Progress, 2026-10-02 (review of the two batches above, uncommitted)

- Choosing or resetting the library folder no longer releases the running library's security scope or redirects image paths mid-session; the location is pinned at launch (also when it is the default) and a change is saved for the next launch only, after the off-main check passes. Settings and the open-database screen say a restart is pending. (Pre-existing; the earlier batch had made Revert do it too.)
- `enroll` / `signOut` block new syncs while they run, not just the one already running.
- Auto-sync: a backoff skip reschedules pending edits (backgrounding had cancelled the retry); one second of slack for early wakeups.
- Engine: revived tombstones found with a join (no bound-variable limit); a manifest-based PUT that is refused for a recipe deleted since falls back to POST after a HEAD.
- `friendlySyncMessage` words GRDB `DatabaseError`s without their SQL.
- Full-image view: close button's padded area is tappable again; VoiceOver zoom via `accessibilityZoomAction`; corrected a comment.
- Measured the size-capped download path: about 60 MB/s release, 20 MB/s debug against `data(for:)`'s near-instant read. Fine for JSON and photos.
- Suite: 828 passing. macOS and iOS builds clean. The image sheet and the location screens have not been exercised in the running app.

### Progress, 2026-10-02 (library relaunch on macOS, uncommitted)

- `AppRelauncher` opens a fresh instance and quits this one; "Relaunch Now" in the open-database success alert and under Settings → Database when a change is pending. iOS wording asks the user to close and reopen. Verified in the dev app: reset, relaunch, new process on the default location; the dev app's custom location was restored afterwards.
- Decided: one library per user is the norm, so no recent-libraries list, no per-library sync state, and no live switching for now. `prepareDependencies` allows `defaultDatabase` to be set only once per process, so live switching would mean a proxy `DatabaseWriter` or passing the database explicitly to every view model and query.

### Progress, 2026-10-02 (step numbering, export service, dead CSS, uncommitted)

- Step numbering: the detail view, printout/HTML and plain-text export now number through `ChefStep.steps(from:)` like Chef View, so headings and blank rows never take a number anywhere. The editor keeps its own rule (it shows blank rows).
- Export: `RecipeExporter` in SaltyCore (`.saltyFile`, `.jsonLD`, `.html(options)`; one recipe as an object, several as an array; "Name.ext" / "N_recipes.ext"); photos come in through two closures. The navigation view model's five export methods are one-liners over a shared `presentExport`, built off the main actor; the 18 `MainActor.run` hops are gone (view model 870 → 729 lines). Multi-recipe `.saltyRecipe` files now use `SaltyRecipeFile.encode` (pretty, sorted keys) like single ones. Verified in the app: empty selection alert, save panel with the recipe's name.
- CSS (revised at the user's request): the normalize/reset baseline is kept whole, including rules for elements not emitted today. Only the custom section changed: duplicated `main`, `body`, `#recipe-name`, `#recipe-source(Details)`, ingredient and direction rules merged into one rule each, and the never-emitted `.recipe-ingredients-container` / `.recipe-directions-step-with-name` removed. `body` now takes font, size, weight, line height, background and colour from `:root` tokens (`--salty-font-size`, `--salty-font-weight`, `--salty-line-height` added; `--salty-font-body` and `--salty-text` defaults set to what rendered), so Retro no longer needs `!important` for its font. Computed styles compared on screen and with print rules forced on: Modern identical everywhere, Retro identical on screen; Retro's printed body text now uses its text colour (#33414f) instead of its heading colour (#5f7180), as on screen.
- Suite: 836 passing. macOS and iOS builds clean.

### Progress, 2026-10-02 (sync steps and plurals out of the core, uncommitted)

- `SyncProgress.Step` (stable raw values) replaces the engine's 26 English step strings; the Apple app labels steps and formats counts in `SyncProgressText.swift`. `currentStep` and `summary` remain on `SyncProgress` as deprecated English for SaltyCoreFFI only; remove them once the C# client labels `step` (its payload should add `step.rawValue`, and its contract tests assert the English today).
- `ShoppingList.contentsCount` and `LastSyncedDescription.phrase(for:)` return values; the app words them (`ShoppingListContentsText.swift`, `LastSyncedText.swift`). Neither is used by the FFI.
- App plurals use Foundation grammar agreement: SwiftUI `Text("^[\(n) recipe](inflect: true)")`, and `String(inflected:)` (via `AttributedString(localized:)`; `String(localized:)` leaves the markup in) where a `String` is needed. Wording that deliberately differs for one ("Print Recipe" / "Print 3 Recipes", classifier singular/plural labels, "is/are") is unchanged. `LastPreparedSummary` moved from SaltyCore to the app (menu wording; nothing else used it). Still English in the core, by decision: the exported HTML title "N Recipes" and schema.org duration text (recipe content).
- Suite: 839 passing. macOS and iOS builds clean.

### Progress, 2026-10-02 (UI labels out of the core, uncommitted)

- Picker and menu names moved from SaltyCore enums to app extensions in `Salty/Models/CoreDisplayNames/`: recipe list sort field, direction and search options; duplicate match level (and its description line); classifier list sort; Chef View display style; print paper size, orientation and colour mode. Call sites unchanged (same property names).
- `LibraryClassifier`: the app uses `singularName` / `pluralName`; the core keeps `singularLabel` deprecated for SaltyCoreFFI (two uses) and no longer has `pluralLabel`.
- Kept in the core by decision: theme names, difficulty/rating words (shared with HTML), error text. Import file kind names stay: they are product names, used by a core error.
- Suite: 839 passing. macOS and iOS builds clean.

### Progress, 2026-10-02 (SaltyXP / .NET app brought up to date, uncommitted; SaltyXP isn't in git)

- Core synced to the share (`sync-core.sh`); SaltyCoreFFI fixed for `SyncError.deviceIdUnavailable` (new `SyncFailureKind`).
- Sync progress: the FFI payload sends `step` (raw value) and `imagesFailed` instead of English; C# `SyncStep` enum (unknown values read as `Unknown`), wording in SaltyUno `SyncText.cs`; failed photos lift the existing warning. Contract tests assert steps, not English. The deprecated `SyncProgress.currentStep` / `.summary` and `LibraryClassifier.singularLabel` are gone from SaltyCore.
- Shopping lists: the FFI update takes an optional expected stamp and reports `conflict: "modifiedElsewhere"` (C# `SaltyConflictException`); the .NET editor carries the stamp it read/wrote, saves one at a time, and re-reads the list on a conflict. `ShoppingListStamp` now compares at wire milliseconds (a JSON round trip could shift the Double).
- Direction numbering in the .NET detail pane follows ChefStep (blank rows dropped).
- New for .NET: Export as HTML / JSON-LD through `salty_recipes_export_file` → `RecipeExporter`; the recipe list's sort order is remembered (`SearchSettings.Sort`).
- Tests: contract 59, Salty.Core 313 (+33 skipped), SaltyUno 178; Swift 840. FFI builds for macOS and Android; .NET desktop head 0 warnings; HTML export checked by hand in the running app. Windows not rebuilt.

### Progress, 2026-10-03 (.NET Organize: merge, ⌘ shortcuts; SaltyXP, uncommitted)

- `salty_classifier_merge` (LibraryDuplicateMerger) + rename results now carry `conflictId`. Organize rows get **Merge…** (MergeDialog: pick the survivor, live consequence sentence, Cancel default); renaming onto an existing name offers the merge.
- `MacShortcuts.UseCommandKey` (moved out of RecipeLibraryPage) now also gives Organize ⌘N and ⌘F. WinUI has no platform modifier, so this existing helper stays the mechanism. ⌘F/⌘N on the library and Organize, merge, and the rename-collision offer all verified by hand on a Mac.
- Organize rework: one ⋯ / right-click menu per row instead of three buttons; selectable list (Extended) with a bar acting on the selection (Rename for one, Merge/Delete for any number; multi-merge picks the survivor among the selection); F2, Delete/Backspace and double-click. Mac caveat: ⌘-click doesn't add to the selection (Uno maps ⌘ to the Windows key); Control-click does. All verified by hand on a Mac.
- Platform keys centralised: `PlatformKeys` (Uno's own `DeviceTargetHelper.PlatformCommandModifier` is internal), `{local:PrimaryModifier}` and `{local:ShortcutHint}` markup extensions in XAML, and `PlatformListSelection` attached to every ListView by an implicit style in App.xaml (⌘-click adds/removes; applied on release because Uno replaces a selection in steps). `MacShortcuts` and its per-page calls removed. Organize rows now full width.
- Tests: contract 61, Salty.Core 315 (+33 skipped), SaltyUno 182.

### Progress, 2026-10-03 (.NET: multi-select, command bar, settings cards; SaltyXP, uncommitted)

- Recipe list: Extended selection; two or more selected show a bulk panel (export in three formats, add to category/tag, favourite/unfavourite, set last prepared today, delete). The page processes selection once a click has settled (`ProcessListSelection`) and `PlatformListSelection.IsAdjusting` covers ⌘-clicks.
- Detail header is now a WinUI CommandBar (Edit, Favourite, Last Prepared, Export; Get Info, Copy, Delete in the overflow); Uno 6.7 renders it correctly on the Mac head, which earlier Skia builds didn't. Labels collapse in narrow layouts, with tooltips.
- Settings rebuilt from a local `SettingsCard` (Windows 11 Settings shape, plain XAML, no package); cards stack their control below the text under 520px.
- Not done: content in the title bar. Uno's Mac head accepts `ExtendsContentIntoTitleBar` but ignores it; Windows would need the native WinUI head, so skipped per the user.
- Tests: SaltyUno 184, Salty.Core 315 (+33 skipped).

## 3. Build warnings (clean macOS build, 15 distinct)

| File | Warning | Fix |
|---|---|---|
| `Salty/Helpers/ImportExport/SaltyRecipeTransfer.swift:21` | `Transferable` requires `Sendable`; conformance synthesised retroactively across modules (plus 4 "stored property contains non-Sendable type" warnings). | Add `Sendable` to `SaltyRecipeExport` and its four item structs in `CORE/ImportExport/SaltyRecipeExport.swift:18,37,59,78,100`. |
| `CORE/ImportExport/SaltyRecipeExport.swift:215,229`, `CORE/RecipeLibraryNames.swift:38,41` | StructuredQueries `contains` deprecated. | `$0.id.in(recipeCategoryIds)`. |
| `AddToShoppingListViewModel.swift:196`, `NAVVM:839`, `ShoppingListDetailViewModel.swift:190,219`, `ShoppingListFreeformViewModel.swift:145` | Result of `database.write` unused (the generic wrapper forwards `ShoppingListWriter.update`'s result; `@discardableResult` does not propagate). | `_ = try await database.write { … }`. |
| `DirectionsEditView.swift:174`, `IngredientsEditView.swift:231`, `NotesEditView.swift:147`, `PreparationTimesEditView.swift:173`, `VariationsEditView.swift:146` | Result of `withAnimation` unused (forwards `RecipeItemListEditor.delete`'s Bool). | `_ = withAnimation { … }` or end the closure with a statement. |

---

## 4. Correctness and data integrity

### 4.1 Editor and detail

- `EDITVM:153-169` + `CategoryEditView.swift:26,113-126,154-193` — medium — categories have two write paths: the sheet writes diffs straight to the DB (touching `lastModifiedDate` even if the editor is then cancelled; on iOS Cancel is cosmetic because toggles mutate the shared binding), and the editor deletes-and-reinserts every link with fresh UUIDs on Save, but only when the set is non-empty. `RecipeClassificationWriter.set(categoryIds:tagIds:forRecipe:in:)` already does the pair-wise replace. Make the sheet a pure picker over a local copy committed on its Save, and call the writer unconditionally in the save transaction.
- `EDITVM:200-267` — medium — tags are written immediately (not cancellable); the returned stamp is assigned at 232/255 so `hasUnsavedChanges` goes spuriously true; for a new unsaved recipe `RecipeTag.insertIfAbsent` violates the FK and the error is only logged. Hold a pending `selectedTagIDs` set and apply via the classification writer in the same write.
- `EDITVM:207-221`, `CategoryEditView.swift:200-218` — medium — tags/categories are created inline with a `collate(.nocase).eq` lookup (no whitespace collapsing) and a hand-stamped `Date()`, bypassing `LibraryClassifierEditor.existingRow/create` and `LibraryClassifierResolver`. The app and the core disagree on what a duplicate name is.
- `NAVVM:141-142` (rendered at `RNSV:1204-1205`) — medium — `selectedRecipeIDs` is never intersected with the loaded rows; after a scope switch, un-favouriting, or a sync delete, the detail column shows a recipe not in the list and menu Print/Export/Delete act on it. `DuplicateRecipesViewModel.swift:69-70` already does `formIntersection`.
- `RecipeImageView.swift:15,17,45-48` — medium — `@State var recipe` / `imageFrameSize` take only the initial value and `.id("\(imageURL)-\(retryCount)")` never changes when a photo is replaced (filename is `<id>.<ext>`), so the header keeps the stale photo; `let _ = Task { retryCount += 1 }` spawns a task from `body`. Key on `lastModifiedImageDate`, render `imageThumbnailData` directly.
- `RecipeDetailWebView.swift:15,20-25` — medium — `@State var recipe` ignores updates; `libraryNames(database:)` (sync read) and `imageAsBase64` (disk read + decode + re-encode) run in `body` on every render. Compute HTML in `.task(id:)` keyed on the stamps.
- `RecipeImageEditView.swift:117` — medium — `pendingImage.previewData(for:)` reads and decodes the full-resolution photo inside `body`, re-run on every keystroke in the editor. Use `imageThumbnailData` and a `.task(id:)`.
- `RecipeImageEditView.swift:59-60` — medium — `UIPasteboard.general.image` is read in `PasteImageButton.body`, so iOS shows the "pasted from…" banner on render; re-encodes to PNG. Check `hasImages` in `body`, read bytes in the action.
- `RecipeImageManager.swift:107-110` and `CORE/Writes/RecipeImageWriter.swift:42-43` — medium — a same-extension replacement overwrites the file in place *before* the row is written, so a rolled-back transaction has already destroyed the old photo; the documented "rolled-back write never costs the photo" only holds for a different extension. Write to a temp name and rename after commit, or document the limitation.
- `IngredientsEditView.swift:115-121`, `DirectionsEditView.swift:74-75,114`, `NotesEditView.swift:67-68,100`, `VariationsEditView.swift:67,100`, `PreparationTimesEditView.swift:67,100` — medium — in standalone mode (`showToolbar == true`, used at `CreateRecipeFromWebView.swift:940,943`) the content is `ScrollViewReader { VStack }` with no `ScrollView`, so long lists clip and `scrollTo` is inert.
- `RecipeDetailEditDesktopView.swift:43-66,98-104` — low — Cancel/Save are not `.cancellationAction` / `.confirmationAction` and carry no `.keyboardShortcut(.cancelAction / .defaultAction)`, so Esc with no changes does nothing.
- `EDITVM:86-89` — low — new-recipe `hasUnsavedChanges` ignores rating, difficulty, prep times, nutrition, servings, yield, course and categories.
- `MarkdownPreviewView.swift:21` — low — `.id(text.hashValue)` can collide; use `.id(text)`.

### 4.2 Write rules and sync stamps (the six bypasses)

- `AddToShoppingListViewModel.swift:163-171` — high — `createList` builds a `ShoppingList` with unrounded `Date()` and `ShoppingList.insert { }.execute(db)`; `NAVVM:824` does it correctly through `ShoppingListWriter.insert`.
- `CreateRecipeFromImageView.swift:395-404` — high — multi-recipe PDF path does `Recipe.insert { recipe }.execute(db)` from the view with `RecipeFromTextParser`'s raw `Date()`; on failure it logs and still dismisses. Use `RecipeWriter.insertImported` in a view model and surface the error.
- `RecipeDuplicator.swift:63-104` — medium — hand-assigns `lastModifiedDate`, inserts with `Recipe.insert`, inserts junction rows by hand, no tests. This is pure recipe logic every client needs; move it to `CORE/Writes/RecipeDuplicator.swift` taking an `imageCopy` closure and use `RecipeWriter.save` + `RecipeClassificationWriter.set`.
- `CORE/LibraryClassifierEditor.swift:86,104`, `CORE/LibraryClassifierResolver.swift:55` — medium — category/course/tag `lastModifiedDate` is a hand-assigned `Date()`: not rounded, not injectable, outside `Writes/`. Sync compares these stamps. Add `now:` parameters and move into a `Writes/LibraryClassifierWriter`. (This also removes the four `Task.sleep(20ms)` in `LibraryClassifierEditorTests.swift:123,156,180,240`.)
- `RecipeImageAccess.swift:46-49,58-61` — medium — `setImage` / `removeImage` hand-stamp `lastModifiedImageDate = Date()` unrounded, duplicating `RecipeImageWriter`.
- `CORE/Schema.swift:189-196` — medium — the multi-id `touchLastModified` returns the *unrounded* `now` while the single-id overload rounds; the "returns the stamp it wrote" contract is false by up to 0.5 ms. Round once at the top.
- `CORE/Writes/RecipeLastPreparedWriter.swift:37` — low — `lastPrepared` is stored unrounded while its stamp is rounded; FFI clients comparing with `==` will see a difference. `date?.roundedToWireMillis`.
- `CORE/Writes/RecipeWriter.swift:76-82` — low — the insert path keeps `lastModifiedImageDate` nil even when `imageFilename` is set, and `ENGINE:2249-2250` maps nil to `.distantPast` on both sides, so such a photo never uploads.
- `CORE/LibraryClassifierEditor.swift:132-143` — medium — course deletion relies on the FK's `ON DELETE SET NULL`, while `RecipeDeleter.swift:37-41` deliberately does not trust FK enforcement. Null `courseId` explicitly before the `DELETE`.

### 4.3 Parsers and import

- `CORE/ImportExport/MacGourmetImportRecipe.swift:78-82,172-173,201` — medium — `MGPrepTime`, `MGNote`, `MGCategory` use non-optional stored properties with defaults; the synthesised decoder still *requires* the keys, so one prep-time dictionary lacking `AMOUNT_2` fails the whole file, and `RecipeImportFile.swift:42-46` discards the `DecodingError` as "not a MacGourmet file". Make nested fields optional and attach the underlying error.
- `CORE/ImportExport/SaltyRecipeExport+Decoding.swift:60` — medium — notes decode as `[Note]`, whose decoder requires `id`, while every other list uses id-less export structs; a note without `id` fails the whole recipe despite "only `name` is required". Add `SaltyNoteExport`.
- `CORE/Search/RecipeSearchQuery.swift:60-71` — medium — `.equals`, `.contains`, `.beginsWith`, `.endsWith` pass `value` into `LIKE` unescaped, so `.equals` "100%" matches "100 things". The "always been this way" note only justifies `.likePattern`. These will be persisted in saved smart lists; escape `%`, `_`, `\` and render `LIKE ? ESCAPE '\'` in `RecipeListQueryBuilder.textCondition` (`:204-240`).
- `ScanTextForRecipeView.swift:287-488` — high — ~200 lines of parsing copied from the *private* helpers in `CORE/RecipeFromTextParser.swift:484-575`, untestable in a view, with the same substring-header bug (`:378,401`: "cooking oil", "preserves", "steps" lines are dropped; core `:427-433` has it too). Expose `parseIngredientLines` / `parseDirectionSteps` publicly with whole-word header detection, add tests, and have the view call a view-model method.
- `CreateRecipeFromWebViewModel.swift:325-340` — medium — `navigateToURL` only prepends `https://`; "chicken soup" becomes an invalid URL and `WebViewRepresentable` silently does nothing, so the address bar appears dead. Validate and surface an error. This VM has no tests.
- `CreateRecipeFromWebViewModel.swift:293` — low — `Int(cleanText.filter { $0.isNumber })` turns "4–6 servings" into 46.
- `CreateRecipeFromWebViewModel.swift:121-133` — low — category links written by a hand loop; `RecipeClassificationWriter.set` and `RecipeWriter.insertImported` (documented as the web-page path) exist.
- `ImportRecipesFromFileView.swift:49-94, 204-207` — medium — import orchestration and DB work live in the view; Cancel stays enabled while importing and the task is never cancelled; `await MainActor.run` at `:73,76` is redundant inside a view's `Task`.
- `DuplicateRecipesViewModel.swift:90-105` and `NAVVM:299-336` — medium — both re-implement `RecipeDeleter.delete(ids:in:)` by hand.
- `LibraryClassifiersEditViewModel.swift:330-338, 359-367` — medium — conflict lookup in a `read` then insert/rename in a separate `write` (TOCTOU with sync or a second window). Do `existingRow` inside the write.
- `CORE/ImportExport/SchemaOrgRecipeJSONLDImporter.swift:142` — low — `String(data:encoding:.utf8)` returns nil for one invalid byte, silently yielding `[]`; use `String(decoding:as:)`.
- `CORE/ImportExport/NutritionAmount.swift:34` — low — "1,5 g" (EU decimal comma) parses as "1".
- `CORE/ImportExport/SchemaOrgRecipeJSONLDImporter.swift:26` — low — stale TODO: the app exports JSON-LD (`NAVVM:551,583`) but `RecipeImportFileKind` has no json/jsonld case, so Salty writes a file it cannot open.

### 4.4 Shopping lists and Chef mode

- `ShoppingListDetailViewModel.swift:181-204`, `ShoppingListFreeformViewModel.swift:135-157` — medium — once `persistNow()` has spawned its write, nothing can cancel it; a sync download landing between `persistNow` and the write is overwritten by the whole-array save. Carry the loaded `lastModifiedDate` and have `ShoppingListWriter.update(id:in:expecting:)` refuse on mismatch (the guarded last-writer-wins already planned for the web editor), or keep the write in `saveTask` so reload can cancel it.
- `ShoppingListChangeNotifier.swift:31-79` (+ `ShoppingListDetailView.swift:117-123`, `ShoppingListFreeformView.swift:70-76`, `SaltySyncService.swift:168`) — medium — a hand-rolled main-actor invalidation bus with editor tokens exists because the editor VMs snapshot rows instead of observing them. A `@FetchOne` on the row plus "reload when the fetched row differs from my last-saved snapshot" removes the singleton, the token plumbing and the sync-engine hook.
- `ChefViewDirectionsList.swift:57` — medium — scroll-to-current-step runs only `onChange`, not on appear, so re-entering mid-recipe opens at the top. Use `onChange(…, initial: true)`.
- `ChefViewModel.swift:83-85` with `ChefViewDirectionsList.swift:20,32-33` — medium — `steps` re-parses `ChefStep.steps(from:)` on every access and the list calls `isCurrent` / `isCompleted` per row, so each render is O(n²) parses (the VM's own comment warns against this). Store `steps` once.
- `ChefSessionState.swift:13-17` — low — progress keyed by direction *index* survives edits between visits; store `recipe.lastModifiedDate` and reset on mismatch.
- `ShoppingListsListView.swift:61-64` vs `140-150`, `RNSV:1111-1116` vs `903-908` — low — swipe/⌘⌫ delete immediately while every other path confirms. Pick one behaviour.

### 4.5 Sync (no high-severity defects found)

- `ENGINE:124-132` — medium — `deviceId` regenerates a UUID on every access when `credentials.deviceId()` is empty and ignores `setDeviceId`'s Bool; on a keychain failure one sync enrols, registers, completes and deletes under four ids. Resolve once per engine and throw if the store refuses.
- `AutoSyncCoordinator.swift:79-89,152-158` + `ENGINE:1946-1959,2015-2023` — medium — the "ignore sync's own writes" check reads `isSyncing` on the main actor after an unstructured hop from GRDB's writer queue; on a busy main actor the hop lands after `isSyncing` flips, a sync fires 90 s later, stamps again, and the cycle repeats. Capture the verdict on the writer queue and make `markAgreed` a no-op write when unchanged.
- `ENGINE:2289-2301` — medium — image failures are only logged; the sync throws only if *zero* images moved, so "Sync Complete" (`SettingsView.swift:449-451`) hides N missing images. Add `imagesFailed` to `SyncProgress`.
- `ENGINE` (11 sites) — medium — `URL(string: "\(serverUrl)/…")` beside `makeURL(endpoint:)` (`:2540`); no scheme/host validation, a trailing `/` yields `//api/…`, and non-Apple hosts have no ATS. Normalise once and require `https` unless loopback.
- `ENGINE:2495-2523` — medium-low — offset pagination over a table other devices write to; a server that keeps answering full pages loops without bound. Bound by `total/size + 1`; keyset pagination when the server is next touched.
- `ENGINE:2071-2098` — medium-low — a HEAD per uploaded recipe although the plan already knows existence; `checkExists` maps a network error to `false`.
- `ENGINE:1788-1810` vs `:1278,1469,1615` — low — the recipe tombstone push does not drop tombstones whose id is present locally again, unlike the classifier passes.
- `ENGINE:2254-2262` — low — a local-only recipe with an image tries `uploadImage` for a row the server lacks, failing every sync.
- `AutoSyncCoordinator.swift:160-203` — medium-low — no backoff while the server is unreachable.
- `SaltySyncService.swift:153-213` — medium-low — `enroll` / `signOut` are not guarded by `isSyncing`; a sign-out during a sync replaces `currentEngine` under the running task.
- `KeychainHelper.swift:73-94` — low — `save` is delete-then-add; a kill between the two loses the token; `:264-277` sets the upgrade-done flag even when `save` returned false. Use `SecItemUpdate` with add fallback.
- `ENGINE:2371-2372` + `RecipeImageManager.swift:135` — medium-low — the 250 MB download cap is honoured, but the thumbnail then decodes the whole image synchronously; a hostile PNG jetsams the iOS app. Downsample with `CGImageSourceCreateThumbnailAtIndex`.
- `ENGINE:2553` — medium-low — JSON fetches use unbounded `session.data(for:)`; only images use the capped variant.
- `ManualSyncRunner.swift:55` — low — raw `localizedDescription` where every other surface uses `friendlySyncMessage`.
- `CORE/Sync/SyncError.swift:126-128, 157` — low — server-supplied `message` surfaced verbatim with no length cap; `default:` can leak GRDB SQL text to the UI.

### 4.6 App shell

- `OpenDBView.swift:117-157` — medium — `appDatabase()` (opens a pool, runs migrations) runs synchronously on the main actor from a button handler so `isOpening` never paints; the probe pool is never closed; "Revert" differs from `DatabaseSettingsView.resetToDefaultDatabaseLocation`. Move to a `DatabaseLocationViewModel`.
- `MainView.swift:36-51`, `RNSV:1267-1275,1383-1387` — medium — `ManualSyncRunner.shared` / `AutoSyncCoordinator.shared` state is bound in every `MainView`, so the password prompt and failure banner appear in every window at once.
- `Menus.swift:19-35,50-70`, `NAVVM:65-92` — medium — `removeObserver(self)` in `deinit` is a no-op for block observers; the `Menus` closures capture `self` strongly, so the trackers live for the process. Use `for await … in NotificationCenter.notifications(named:)` in a task cancelled in `deinit` (also removes the `assumeIsolated` wrappers).
- `RNSV:669-678` — medium — `withAnimation` wraps a loop spawning one `Task` per deleted row (N transactions, N tombstone writes); swiped-away rows stay selected. A single `deleteRecipes(ids:)`.
- `RNSV:590-631` (+ timed hacks at `179,197,603,627,946`) — medium — `waitForSettledRecipeRow` polls every 50 ms for up to 5 s then retries `scrollTo` three times. Have the VM expose `pendingScrollTargetID` and scroll in `onChange` of the ids.
- `SampleData.swift:41,43` — low — `-60*24*30` is 12 hours, not 30 days (missing `*60`).
- `RecipeFullImageView.swift:112-120,180-215` — low — `CmdPlusPressed` / `CmdMinusPressed` / `CmdZeroPressed` notifications are never posted anywhere (dead); `NSEvent.addLocalMonitorForEvents` reimplements `.onKeyPress` / `.keyboardShortcut`; `presentationMode`, `MagnificationGesture`, `PlainButtonStyle()` are deprecated spellings.
- `RecipeDirectionView.swift` — low — unreferenced file; its `ForEach(Array(…enumerated()), id: \.element.hashValue)` uses a hash as identity. Delete.

---

## 5. Separation of view from logic (and what belongs in SaltyCore)

The cross-platform goal makes this the most valuable structural theme: anything a Compose or WinUI client would have to re-implement should sit in `SaltyCore`, and anything a test would want to exercise should sit outside a `View`.

**Logic currently in views that belongs in a view model or the core**

- `NutritionEditView.swift:70-120,239-333` — 35 `@State` strings and all parse/validate/serialise logic (which is how §2 #2 survived). A `NutritionEditModel` (fields + `FormatStyle` codec) in SaltyCore with unit tests.
- `ScanTextForRecipeView.swift:287-488` — duplicated text parsing (§4.3).
- `CategoryEditView.swift:24,128-228` — direct `database.read/write` and category creation inside the view; `onAppear { Task }` instead of `.task`.
- `CreateRecipeFromImageView.swift:26-47,185-222,327-406` — the view owns all import state plus a 40-line platform-branched "Extract Text" action; `CreateRecipeFromImageViewModel` with `enum Source { image, pages, pdf }`.
- `CreateRecipeFromWebView.swift:660-695,202-208` — `scanWebpageForRecipeData` builds the importer, scans, populates the VM, downloads the image and flips sheet flags from the view via closure-based `getPageHTML(completion:)`; `evaluateJavaScript` has an async form.
- `MainView.swift:19-21,53-63` — `handleIncomingURL` does synchronous file I/O (`peekRecipeNames`) in the view and drives an alert with three pieces of state. `struct PendingImport: Identifiable` + `.alert(item:)`.
- `SettingsView.swift:709-750` — `deleteAllBackups` deletes files from the view; `createBackupNow` sniffs `backupMessage.hasPrefix("Backup created")` to decide state. An `enum BackupStatus` in a small view model.
- `SettingsView.swift:142-144,374-378,445-484` — three near-identical `perform*` functions and a three-field alert; `ServerSettingsViewModel` would make `friendlySyncMessage` mapping testable.
- `SettingsView.swift:14-15,26,51,101,131` — `@Dependency(\.defaultDatabase)` is never used; `diagnosticsInfo: [String: Any]` is non-Sendable and threaded through a `@Binding` into a view that re-fetches it anyway.
- `RNSV:633-640`, `Menus.swift:77-158` (×2 instances), `NAVVM:222-231` — search options read from `UserDefaults.standard` in four places with three app-wide `didChangeNotification` observers. One `@Observable RecipeSearchOptions` owned by the VM with an injected `UserDefaults`.
- `SaltyApp.swift:37-90` — launch orchestration (keychain migration, bookmark validation, DB open, backup kick-off) in `App.init`; an `AppLaunch.run()` helper is testable and reusable by the external-display scene.
- `ChefIngredientsScrollSync.swift:100-110` — the anchor derivation is pure logic inside a view modifier that also reads a singleton; `ChefIngredientsAnchor.init(topVisibleIndex:isAtEnd:)` with a test.
- `AddToShoppingListView.swift:153-155` — `refreshDuplicates()` triggered from the view's `onChange`; the VM should own it via `didSet`.
- `ChefViewTextSize.swift:27-31,78-92,156-170` — the UIKit/AppKit font resolver is justified and explained, but the pure parts (`levels`, `clamped`, `externalDisplayScale`) sit in `Views/`, and the two `TextStyle` tables are byte-identical.

**View models holding what a non-Apple client would need (move to SaltyCore)**

- `NAVVM:455-480,498-535,542-565,568-598,636-706` — five near-identical export methods, each with 18 redundant `await MainActor.run {}` inside a `@MainActor` class (a `Task {}` already inherits the actor, so `fullRecipe`'s synchronous `database.read` and `JSONEncoder` run on main anyway). One `presentExport(_ build:)` plus a `RecipeExportService` in SaltyCore (`.saltyFile(ids:)`, `.jsonLD(ids:)`, `.html(ids:options:)`); ~250 lines → ~60.
- `NAVVM:388-400` (called from `RNSV:1204-1205, 853-855, 1127-1128`) — `fullRecipe(id:)` is a synchronous read plus full JSON decode in `body` on every evaluation of the detail column, twice when the toolbar menu is built. Pass the id down and let `RecipeDetailViewModel` fetch.
- `EDITVM:295-335` — `nutritionSummary` (English labels and units) is presentation logic every front end needs; `CreateRecipeFromWebView.swift:950-956` has its own `formatNutritionValue` with `String(format: "%.1f")`. `NutritionInformation.summaryParts` in the core returning (label, value, unit).
- `AddToShoppingListViewModel.swift:227-233` — `availableNewListName` is pure, tested, and compares with `lowercased()` + `.whitespaces` while `RecipeToShoppingList.adding` (`CORE:216`) uses `compare(options: [.caseInsensitive, .diacriticInsensitive])` + `.whitespacesAndNewlines`. Move to the core with one comparison rule. (`localizedStandardContains` is the wrong tool here; it is substring search for filtering.)
- `RecipeItemListEditor.swift:17,129-143` — only `binding(for:)` needs SwiftUI; the enum is pure and tested. Move it to the core so KMP/C# share reorder semantics.
- `RecipeDuplicator.swift` — see §4.2.

**Core code carrying UI concerns (move the other way)**

- `ENGINE` ×25 sites (`:418-752`) + `CORE/Sync/SyncProgress.swift:20-22` — UI copy ("Authenticating...", "↑ … | ↓ …") produced inside the shared engine; unlocalisable, and `SyncCancellationTests.swift:105` already string-matches it. A `SyncProgress.Step` enum with app-side labels.
- `CORE/RecipeListSortOrderSetting.swift:74-83,109-130`, `CORE/ChefViewDisplayStyle.swift:19,31`, `CORE/LibraryClassifier.swift:41` — `@AppStorage` keys and SF Symbol names shipped from the portable core.
- `CORE/ShoppingListSummary.swift:22,25`, `CORE/LastPreparedSummary.swift:25-31`, `CORE/LibraryClassifier.swift:24-38`, `CORE/Schema.swift:421-456` (`Difficulty.stringValue()`) — user-facing English and hand-rolled pluralisation returned from the core; hand back counts/enums and let each front end localise.
- `CORE/RecipePrintOptions.swift:32-38,105-117` — `CGSize` / `CGFloat` as the page-geometry vocabulary; compiles on corelibs but is a CoreGraphics idiom a C#/Kotlin consumer must translate. A `PageSize { width, height: Double }`.

---

## 6. Concurrency patterns

- `WebViewRepresentable.swift:53,79,88,130,156,165` — six `DispatchQueue.main.async` / `asyncAfter(0.05)` to publish the coordinator and "force" state; `.htmlString` / `.htmlResource` reload on every `updateNSView` / `updateUIView` (no change guard, unlike `.url`), resetting scroll and selection on every host re-render; two near-identical structs (~75 lines). Use `makeCoordinator()` as the delegate, remember `lastLoadedContent`, drive state from delegate callbacks, mark `WebViewCoordinator` `@MainActor`.
- `CreateRecipeFromWebView.swift:191-200, 650-658` — polls for the coordinator with up to five 100 ms sleeps and sleeps 100 ms to reset loading state; the coordinator exists after `makeNSView` and `didFinish` fires for `loadHTMLString`.
- `IngredientsEditView.swift:131-135`, `DirectionsEditView.swift:85-89`, `NotesEditView.swift:78-82`, `VariationsEditView.swift:78-82`, `PreparationTimesEditView.swift:78-82`, `RecipeRowFocus.swift:20-23` — five copies of a 0.2 s `Task.sleep` focus-after-add hack; `withAnimation(_:completion:)` removes it.
- `LibraryClassifiersEditView.swift:273-281` — re-issues the scroll twice on 250 ms sleeps.
- `EDITVM:140` — `pendingImage.apply` writes the file and renders the thumbnail (`RecipeImageManager.swift:215-275`, `lockFocus` is deprecated since macOS 14) synchronously on the main actor at Save. Run inside the `database.write` closure or an image actor; use `CGImageSourceCreateThumbnailAtIndex` (no full decode, no UIKit/AppKit fork).
- `CORE/OCR/ReadingOrderAssembler.swift:251-253` — `newItemPattern` is a computed property, so the regex is re-parsed on every call inside an O(n²) filter. `nonisolated(unsafe) static let` is correct here (immutable after construction).
- `CORE/Sync/SyncWireDate.swift:20-24,30-58` — a new `ISO8601DateFormatter` per call and up to six `DateFormatter` allocations per parse, for four dates × N manifest entries per sync. `Date.ISO8601FormatStyle(includingFractionalSeconds: true)` and `Date.ParseStrategy` are in FoundationEssentials and portable; at minimum hoist to `static let`.
- `ENGINE:1204-1688` — three ~150-line copies of the classifier sync algorithm differing only by type/table/endpoint; the tombstone/agreement rules were added to all three by hand. One generic `syncClassifier<Row>`.
- `FileHelper.swift:114-117` — `nonisolated(unsafe)` statics behind an `NSLock`; `Mutex` from Synchronization or a small actor.
- `ZIPService.swift:52-55` — a non-Sendable class with a mutable flag; `createZipAtTmp` / `getZipData` / `FileToZip` are unused (only `createZip(zipFinalURL:fromDirectory:)` is called, `DatabaseBackupManager.swift:230`); no extraction exists anywhere, so make it an enum of statics and delete the dead API.
- `ENGINE:409-412,493,620` — no reentrancy guard on `sync()` (documented as the caller's job); fine for the app, but the FFI/Compose hosts get no protection.

---

## 7. Accessibility

Where it was designed in, it is exemplary: `StarRatingEditView` (adjustable action, value announcements, custom clear action, 44 pt slop, RTL, reduce motion), `LibraryClassifierMergeView` rows (combined labels, `.isSelected`), `RecipeChip` and section headers in the detail view. The rest needs a pass.

**Wrong or misleading output**

- `ChefViewIngredientsList.swift:94` — high — `.accessibilityLabel(ingredient.text)` is the *unscaled* ingredient while the visible text is the scaled quantity. A VoiceOver cook on a halved recipe hears "2 cups flour" when the screen says "1 cup". Also use `.isToggle` rather than `.isButton`.
- `AddToShoppingListView.swift:93` — medium — `.accessibilityLabel("Add To")` replaces the menu's derived label, so the selected list name is lost; add `.accessibilityValue`.
- `SyncStatusFooterView.swift:41` — medium — `.accessibilityLabel("Sync Now")` replaces the row in both states; while syncing VoiceOver hears "Sync Now, dimmed" and the "Last synced…" text is never spoken. Label by state, value from `LastSyncedDescription`, `.updatesFrequently` while syncing.
- `RatingView.swift:52-56`, `DifficultyView.swift:124` — medium — `accessibilityLabel` on a container with no `accessibilityElement(children:)`, so the label is read and then each child star / caption.
- `ChefViewHeaderBar.swift:59` — low — the display-mode button's label is the *target* style ("One Step"), so current and destination are indistinguishable.
- `ChefViewDirectionsList.swift:77-83`, `ShoppingListDetailView.swift:247-256` — low — completion controls are buttons whose label flips ("Completed" / "Not Completed") and never name the row.

**Missing announcements and grouping**

- `ChefViewFocusStepView.swift:47-82` — medium — the step is three separate elements and nothing announces a step change; in Focus mode the whole screen changes silently. Combine, label "Step n of total. text", and post `AccessibilityNotification.Announcement` on step change in `ChefView`. Lines 102-109: the "Next Step" tap zone is never `.disabled(!canAdvance)` while the controls bar is, and the clear tap zones sit over the text.
- `AutoSyncFailureBanner.swift:27-100` — medium — appears with no announcement; `:97 .onTapGesture { onDismiss() }` violates AGENTS.md and a stray tap on the text dismisses it; white icon and `.blue` link on yellow fail contrast; user-facing typo "Salty Sever" (`:35`, also `CORE/Sync/SyncError.swift:87`).
- `RecipeRowView.swift:28,34-70,102-122` — medium — the row is not combined (thumbnail, name, summary, star stack and heart are visited separately); the stars are `accessibilityHidden` under an unlabelled `HStack` carrying only a `.accessibilityHint`; the "not rated" placeholder is `.hidden()` so its hint is dead; the heart uses `opacity(0)` plus a hint instead of a label; fixed 32/64 frames and `.font(.system(size:))` ignore Dynamic Type. `.accessibilityElement(children: .combine)`, a label and a value, `@ScaledMetric`.
- `DuplicateRecipesView.swift:219-261, 195-207` — medium — each row is ~7 separate elements; group header rows need `.isHeader`.
- `CreateRecipeFromWebView.swift:593` — medium — Menu label is a bare `Image(systemName:)` (VoiceOver: "ellipsis circle"); same at `RecipeDetailEditDesktopView.swift:201-205,238-242,273-277`. `Label("More", …).labelStyle(.iconOnly)`. TextEditors at `CreateRecipeFromWebView.swift:735,752,775`, `CreateRecipeFromImageView.swift:147`, `ScanTextForRecipeView.swift:147` have no label; the loading indicator at `:519-527` stays in the tree at opacity 0; macOS scan success fills the panel silently; `WebImportAddressField.swift:113` has a placeholder but no accessibility label.
- `ImportRecipesFromFileView.swift:173-186` — medium — indeterminate `ProgressView().scaleEffect(1.2)` plus a "File N of M" text that is never announced; use `ProgressView(value:total:)` with a label.
- `RecipeDetailView.swift:405,650,535,530-533` — low — bullet and step number are separate elements; `Slider` has no label; `.frame(width: 80)` clips at larger type.

**Motion, size and input**

- `ChefViewControlsBar.swift:40,54`, `ChefViewDirectionsList.swift:34-35,59`, `ChefViewFocusStepView.swift:35,89,103`, `ChefViewHeaderBar.swift:55` — medium — every `withAnimation(.smooth/.snappy)` ignores Reduce Motion; nothing in the Chef slice reads `accessibilityReduceMotion`.
- `ChefViewHeaderBar.swift:76,155`, `ChefViewControlsBar.swift:68`, `ChefViewTextSizePopover.swift:68` — low — `.dynamicTypeSize(...xxLarge)` caps the *system* accessibility size; `chefHeaderIcon()` is a fixed 26×26 frame.
- `DifficultyView.swift:18,76,89,122` — medium — fixed 120×12 geometry and `.font(.system(size: markerSize * 0.8))`; `.fill(.white)` ignores dark mode.
- `SettingsView.swift:37,652` — low — fixed `.frame(width: 500, height: 600)` clips at larger text; `.lineLimit(3)` truncates the backup explanation.
- Drag-only reordering — medium — `IngredientsEditView.swift:344-355`, `DirectionsEditView.swift:276-287`, `NotesEditView.swift:251-256`, `VariationsEditView.swift:249-254`, `PreparationTimesEditView.swift:251-256`, `RecipeRowKeyboardReordering.swift:26-31`: the handle is a static `Label` with `.draggable`, not a control, and the ⌘⌥↑/↓ fallback is undiscoverable. Add Move Up/Down to a row `.contextMenu` and `.accessibilityActions`, and Edit-menu commands.
- `RecipeImageEditView.swift:160,238` — medium — iOS tile uses `onTapGesture` (no button trait) while the macOS branch uses `Button`; four copy-pasted `.onDrop` blocks; `dropDestination(for: Data.self)` replaces string UTIs.
- `CreateRecipeFromImageView.swift:653-656,772-777` — medium — no `AVCaptureDevice.requestAccess`; a denied camera shows a black preview and Capture silently no-ops. Also no "Take Photo" on iOS at all in `RecipeImageEditView`.
- `ChefViewControlsBar.swift:39-59` — low — no keyboard shortcuts for Previous/Next on macOS or iPad hardware keyboards.
- `SyncPasswordPrompt.swift:44` — low — `SecureField` lacks `.textContentType(.password)`, so password managers cannot offer the credential.

---

## 8. AGENTS.md compliance (mechanical, with counts)

Clean: no `foregroundColor`, `cornerRadius()`, `tabItem`, `ObservableObject`, `@Published`, `NavigationView`, `UIScreen.main`, `Task.sleep(nanoseconds:)`, `AnyView`, `try!`, or one-parameter `onChange`; every `@Observable` class is `@MainActor`; all `Task.sleep` calls use `for:`.

| Rule | Count | Representative sites | Note |
|---|---|---|---|
| Computed `some View` properties (use View structs) | ~206 grep hits, of which the reviewers verified ~60 as genuine helpers | `RecipeDetailView` (mostly already struct-based on inspection), `CreateRecipeFromWebView` 10, `RNSV` 2 + 5 builder funcs, `CategoryEditView:230,252`, `ChefView:155,193`, `ExternalChefDisplayView:74,121,139`, five row editors ×3 each | Most of the row-editor ones vanish with the generic component in §9. |
| Hard-coded padding / spacing | ~247 | `RecipeDetailView` 41-43, `RecipeDetailEditDesktopView` 25, `CreateRecipeFromWebView` 22, `SettingsView` 14, Chef views ~47, negative `-6` at `RecipeDetailEditMobileView:542` | Default `.padding()`, `@ScaledMetric`, a couple of named metrics; the overscan inset in `ExternalChefDisplayView:114-115` is justified by its comment. |
| `ScrollViewReader` (prefer `ScrollPosition`) | 7 | `RNSV:648`, `LibraryClassifiersEditView:110` (justified by comment: `List` cannot use `ScrollPosition`), five row editors | The Chef views already use `ScrollPosition` / `onScrollTargetVisibilityChange` correctly. |
| `DispatchQueue` | 10 | `WebViewRepresentable` ×6, `CreateRecipeFromImageView:760,767`, `RecipeImageEditView:490,497` | §4 #12 and §6. |
| `onTapGesture` without location/count | 3 | `AutoSyncFailureBanner:97`, `RecipeImageEditView:160,238` | `RecipeFullImageView:91` uses `count: 2`, which is allowed. |
| `GeometryReader` | 1 | `RecipeFullImageView:42` | Only bounds the pan; `onGeometryChange` suffices. |
| `fontWeight` where `bold()` / the font suffices | 17 | `SettingsView:63,761` (`.medium`), `RecipeDetailView:410,412`, `NotesEditView:212`, `DirectionsEditView:244`, `IngredientsEditView:290`, bulk views, import views | `.headline` is already semibold at several of these. |
| `String(format:)` | 3 | `CreateRecipeFromWebView:954`, `SyncImagePreparer:106`, `CORE/IngredientScaler:176` | `Text(value, format: .number.precision(...))`; `String(x, radix: 16, uppercase: true)`. |
| Legacy `Formatter` classes | 7 (all in the core) | `CORE/IngredientScaler:171` (`NumberFormatter` + `NSNumber`), `CORE/Schema:1012`, `SchemaOrgRecipeJSONLDExporter:125`, `SyncWireDate:21,31,53`, `ENGINE:2498` | `FloatingPointFormatStyle` with `en_US_POSIX` (the helper already exists as `RecipePrintOptions.cssNumber:164-169`); `Date.ISO8601FormatStyle`. |
| `replacingOccurrences` where `replacing` works | 12 | `CORE/RecipeToHtml:18-22`, `HTMLEntities:38`, `NutritionAmount:38`, `SchemaOrgDuration:53`, `IngredientTextParser:229`, `RecipeFromTextParser:575`, `Schema:738`, `ScanTextForRecipeView:485` | `htmlEscaped` also makes five passes per string. |
| `Array(x.enumerated())` | 2 | `SplitRecipesView:49`, `RecipeDirectionView:17` | |
| `RoundedRectangle(cornerRadius:)` as clip/fill (use `.rect`) | ~14 | `SplitRecipesView:95-96`, `CreateRecipeFromImageView:60-72,150,168`, `ScanTextForRecipeView:74-86,150,168`, `DirectionsEditView:295`, `NotesEditView:262`, `ChefViewDirectionsList:110`, `AutoSyncFailureBanner:68,78` | |
| UIKit/AppKit colours in SwiftUI | 6 | `Color(nsColor: .tertiarySystemFill)` at `IngredientsEditView:362`, `DirectionsEditView:294`, `NotesEditView:261`; `Color(.controlBackgroundColor)` at `CreateRecipeFromWebView:935`; `RecipeImageManager:281,290` | `.fill.tertiary`, `.background`. |
| Fixed font sizes | 2 | `RecipeRowView:58`, `DifficultyView:89` | |
| Icon buttons as `Button(action:) { Label }` / `{ Image }` | ~20 | `RNSV` ×11, `SettingsView:264,305`, `SidebarSectionSettingsRow:59-73`, `CreateRecipeFromWebView:462-498,536,572,587,606` | `Button("Export", systemImage:)`; `.labelStyle(.iconOnly)` where needed. |
| Multiple types per file | many | `RNSV` holds 12 types (incl. `ExportDocument:1410-1432`), `SettingsView` 9 (incl. `RecipeListViewStyle:45-47`), `CORE/RecipeListSortOrderSetting` 3 public enums, `CORE/SaltyRecipeExport` 5 public structs, `CORE/IngredientTextParser` parser + units + extension, `CORE/Sync/ServerLibraryItems`, `ServerRecipe` | |
| Deprecated API | 6 | `.autocapitalization(.none)` at `SettingsView:187`, `CreateRecipeFromWebView:291,508` (206 already uses `textInputAutocapitalization`); `PreviewProvider` at `OpenDBView:160-164`; `.navigationBarLeading` at `RNSV:462` vs `.topBarLeading` at `:1231`; `lockFocus` in `RecipeImageManager:242-293`, `IngredientsEditView:389-396`; `presentationMode`, `MagnificationGesture` in `RecipeFullImageView` | |
| Hand-rolled plurals | ~15 | `RNSV:939,952`, `SplitRecipesView:66`, `ConsolidateDuplicatesView:80,86,148,159`, `DuplicateRecipesView:91`, `LibraryClassifiersEditViewModel:141,157,184`, `ImportRecipesFromFileView:99-108`, `AddToShoppingListView:62` | `^[\(n) recipe](inflect: true)`. |
| Force unwraps | 8 | `NAVVM:526,588,665,702` (`first!` after emptiness checks), `DatabaseBackupManager:68` (`min()!`), `ENGINE:906,951` (`lastSyncDate!`), `ENGINE:2325-2336` (`.data(using:)!` ×8) | |
| `appendingPathComponent` / `FileManager.default.urls(for: .documentDirectory)` | ~12 | `DatabaseBackupManager:165-224`, `FileHelper:89,95-104,200-226`, `ZIPService:37-44`, `SaltyRecipeTransfer:34-36` | `appending(path:)`, `URL.documentsDirectory`, `URL.temporaryDirectory`. |
| Localisation | n/a | 212 literal `Text("…")`, no string catalog, `knownRegions = (en, Base)` | The project is not localised, so the symbol-key rule does not apply; noted because the core returns English strings (§5) that will block it later. |

---

## 9. Standard SwiftUI usage and maintainability

**Decompositions that pay for themselves**

- **Generic row editor.** `IngredientsEditView`, `DirectionsEditView`, `NotesEditView`, `VariationsEditView`, `PreparationTimesEditView` share ~130 lines each of identical `listWidth` / `dropTarget` / `scrollToNewItem` / `move` / `moveUp` / `moveDown` / `delete` / toolbar / bottom-button plumbing, five `ScrollViewReader`s and five sleep-based focus hacks. A `RecipeRowListEditor<Item: RecipeEditableRow, Row: View>` taking `@Binding var items`, `newRow`, and a `@ViewBuilder row: (Binding<Item>, RecipeRowContext) -> Row`, owning `ScrollPosition`, the drop indicator/end zone, focus-after-add and keyboard reordering, shrinks each editor to ~40 lines and removes roughly 600 duplicated lines along with the clipping bug (§4.1) and the reorder accessibility gap (§7).
- **`RecipeNavigationSplitView` (1578 lines, 12 types).** `Views/Main/RecipeNavigationSplitView.swift` (root + `DetailOnlyModeModifier`), `Sidebar/SidebarColumnView.swift` + `ClassifierDropTargetView.swift` (the two drop targets at `RNSV:47-85` differ only by label/icon/action), `RecipeList/RecipeListColumnView.swift` + two `ToolbarContent` structs (iOS/macOS, replacing the 180-line `#if` block at `758-938`) + `RecipeContextMenu`, `LastMadeMenu`, `LastMadeDatePickerSheet`, `RecipeInfoInspectorView`; `RecipeDetailColumnView.swift`; `MainPresentations.swift` with an `enum MainSheet: Identifiable` replacing the ten Bool sheet flags threaded through three levels (`RNSV:108-129 → 511-519 → 1255-1264, 1325-1354`); `Models/ExportDocument.swift`; `Helpers/MainWindowCommands.swift` (the `FocusedValue` replacing the notification bus). Split the VM too: selection/query core, `RecipeExportCoordinator` (`NAVVM:450-761`), shopping-list methods (`NAVVM:807-869`).
- **`CreateRecipeFromImageView` (811) and `CreateRecipeFromWebView` (964).** `MacCameraViewController` + `RecipeImageCameraViewController` become one class in `Helpers/Camera/`; `ImagePicker` / `DocumentScanner` / `CameraView` into `Views/Import/Pickers/`; `SmartParseOptionRow` its own file; `ImagePicker` (wrapping `PHPickerViewController`, `:444-486`) is replaceable by `PhotosPicker` + `loadTransferable`; the eight identical `.onKeyPress` blocks (`CreateRecipeFromWebView:90-137`) become one modifier with `RecipeField.init?(shortcutKey:)`; `RecipeOCRService.swift:72-134` iOS/macOS twins and the three copies of the "--- Page N ---" join (`:87-90,118-121,223-231`) collapse once the service takes `[CGImage]`.
- **Platform image preview.** `CreateRecipeFromImageView.swift:56-74` and `ScanTextForRecipeView.swift:70-88` are platform-split `Image(uiImage:)` / `Image(nsImage:)` blocks with no label; `Image(cgImage, scale: 1, label:)` is cross-platform and removes the UIKit/AppKit imports from those files.
- **`IngredientsEditView.swift:374-463`** — `ComboButtonRepresentable` (NSComboButton, deprecated `lockFocus`, NSMenu rebuilt on every update) is replaceable by `Menu("New Ingredient", systemImage:) { … } primaryAction: { … }`, deleting ~90 lines.
- **`RecipeFullImageView`** — see §4.6; dead notification plumbing and an `NSEvent` monitor where `.onKeyPress` / `.keyboardShortcut` are cross-platform.
- **`WebViewRepresentable`** — two near-identical structs; a `PlatformViewRepresentable` typealias.
- **`RecipeToHtml.swift` (1733 lines)** — 1,420 lines are a CSS string literal, `:316-695` is verbatim normalize.css for elements never emitted, and a second `body` / `main` block at `:1363-1378` hard-codes `font-family`, `color: var(--salty-heading)` and `background: white`, overriding the tokenised rules at `:793-822` so the documented theme contract (`:27-41`) only works via `!important` in `RecipeHtmlTheme.swift:63,106`. Five selectors are declared twice, two are never emitted. Delete the duplicate block, trim normalize to the ~10 rules that matter, and move the stylesheet to `RecipeHtmlStylesheet.swift` as `public enum RecipeHtmlStylesheet { static let base }` (not a `Bundle.module` resource, which is the one thing that does not port). `getDefaultCSS()` (`:309`) is a pure alias of `getCSSForHTML()`.

**Smaller standard-usage items**

- `RNSV:529-530,715-734,1007-1008,1084-1085` — `LastMadeDatePickerSheet` driven by `lastMadePickerDate != nil` plus a separately-set `lastMadeTargetIDs`; `struct LastMadeRequest: Identifiable` + `.sheet(item:)`.
- `RNSV:853,993,1204` — `selectedRecipeIDs.first` on a `Set`: a multi-selection shows an arbitrary member; show "N recipes selected" via `ContentUnavailableView` as the shopping-list branch (`1169-1172`) does.
- `RNSV:1545-1577` — `RecipeInfoInspectorView` renders label/value as separate `Text`s; `LabeledContent` gives combined VoiceOver output and platform styling.
- `RecipeDetailView.swift:396,639,684,708` — `ForEach(x.indices, id: \.self)` on Identifiable rows breaks diffing on reorder; `:648` re-implements the tested `RecipeItemListEditor.stepNumber`.
- `RecipeDetailView.swift:195-200` — scroll-title hack (`maxY > 90`); `.onScrollVisibilityChange(threshold:)` on the title.
- `RecipeDetailView.swift:604-629` — two Buttons just to swap style; a segmented `Picker`.
- `CORE/RecipeToHtml.swift:195-209` vs `CORE/ChefStep.swift:34-47` — step numbers recomputed per row with `prefix(index + 1).filter{}.count` (O(n²)) and the rule differs from `ChefStep.steps(from:)`, which drops blank rows: a recipe with an empty direction row shows step 4 in Chef View and step 5 on the printout.
- `CORE/LibraryClassifier.swift:50-56`, `LibraryClassifierResolver.swift:60-66`, `LibraryDuplicateMerger.swift:135-141` — three copies of the classifier→table-name switch.
- `ChefView.swift:166-189` vs `ExternalChefDisplayView.swift:150-171` — the `Group { switch displayStyle }` + `.dynamicTypeSize` block and the AppStorage/`textSize` pair are copied. (`ExternalChefIngredientsPane` correctly composes `ChefViewIngredientsList` through `ViewThatFits` rather than duplicating it.)
- `ChefView.swift:141-151` — hand-rolled error alert where `.errorAlert(_:title:)` (`ErrorAlertViewExtension.swift:16`) exists and is used elsewhere.
- `RecipePrinter.swift:287-288` — `setValue(_:forKey:)` on `UIPrintPageRenderer`'s read-only `paperRect` / `printableRect` is undocumented KVC; assert the rects after setting. `:154-159` the load continuation never times out.
- `RecipeImportParser.swift:33-38` — `SystemLanguageModel.default.availability` queried on every `SmartParseOptionRow` body evaluation.
- Magic `UserDefaults` keys — 23 distinct string literals in the shell slice; "recipeListSortOrder" ×5 (`NAVVM:54,75,153-154`, `Menus:177`), "recipeHtmlTheme" at `NAVVM:749` and `SettingsView:606`. An `enum DefaultsKey` (some are shared with the KMP client); `SidebarSectionOrder.storageKey` shows the pattern.

**Dead code and stale comments** (grouped)

- `NAVVM:765-769` (`let x/y/s`, duplicate bundle lookup); `NAVVM:194-200` comment says the list loads full rows but it is a `RecipeListItem` projection; `Menus.swift:309-327` `#else` / `#if !os(macOS)` inside an `#if os(macOS)` block can never compile; `isNewLaunch` never reset (`NAVVM:48`, `RNSV:322`).
- `EDITVM:63,65,67-69` dead sheet flags; `:274-287` dead `refreshRecipeFromDatabase` with a synchronous main-thread read.
- `CreateRecipeFromWebViewModel.swift:342-344, 353-357, 234-243, 61, 381-392` all unreferenced; `CreateRecipeFromImageView.swift:421` stray `//endif`; `:700,717` `layer?.backgroundColor` on an `NSButton` without `wantsLayer` (no-op).
- `ChefViewModel.swift:193-204` test-only with a stale comment; `ChefViewSessionStore.swift:47-50`, `ShoppingListDetailViewModel.swift:124-127`, `CORE/ShoppingListItemsEditing.swift:27-30` unused.
- `CORE/RecipeListQueryBuilder.swift:244-247` `searchCondition(pattern:options:)` has no callers; `CORE/Schema.swift:618-620` `#if DEBUG eraseDatabaseOnSchemaChange = false` is a no-op; three blocks of commented-out GRDB code at `:127-164,281-291,762-770`.
- `CORE/Schema.swift:26,972` refer to `SaltySyncService.reconcilePreparedDates`, which does not exist; `CORE/RecipeSyncReconciler.swift:46-91` the `plan` doc comment is attached to `allowsDeletions`; `CORE/Writes/RecipeWriter.swift:71-72` says "truncate" where `roundedToWireMillis` rounds; `CORE/Sync/SyncWireDate.swift:17` says `internal` on a `public` enum; stale `//  Salty` headers across ~15 core files; `OpenDBView.swift:2` says "ImportView.swift"; both edit roots' headers say "RecipeDetailView.swift".
- Typos in user-facing text: "Salty Sever" (`AutoSyncFailureBanner:35`, `SyncError:87`, `KeychainHelper:162`), "textmay" (`RecipeDuplicator:58`), "orignal" (`RecipeDetailViewModel:113`), "tellign" (`ExternalChefDisplayView:6`), "steos" (`ChefViewTextSize:65`).

---

## 10. Cross-platform core readiness

**Portability: clean.** No Apple-only imports in `SaltyCore`; `FoundationNetworking` guarded at every `URLSession` / `URLError` site; `NSRegularExpression` ranges converted with `NSRange(_, in:)` / `Range(_, in:)` throughout (no UTF-16 offset bugs found); `ImageDataFormat` sniffs magic bytes instead of ImageIO; `MarkdownToHtml` uses a document-level CSP with a correct explanation of why tree sanitising cannot work. `SaltyCoreApple` correctly fails on non-Apple hosts. Three small items:

- `SaltyCoreApple/RecipePdfComposer.swift:16-18` — no `#if canImport(CoreGraphics)` guard, so a bare `swift build` of the package on Linux/Windows fails unless `--target SaltyCore` is passed.
- `CORE/LibraryFilenames.swift:11-15` — Windows-invalid characters (`: * ? " < > |`) and reserved device names (`CON`, `NUL`, `COM1`…) are not refused, so a server-supplied id could yield an unwritable image file on Windows.
- `CORE/URLSessionByteLimit.swift:65-70` — byte-at-a-time `append` over `AsyncBytes`, and the documented gap that corelibs buffers in full; a `URLSessionDataDelegate` that cancels past the cap works on both Foundations.

**Public API hygiene for non-Swift consumers**

- Missing `Sendable` on public value types (Swift 6 does not infer it for public types): `SaltyRecipeExport` + four item structs, `RecipeHtmlPage:11`, `RecipeHtmlTheme:13`, `RecipeListSortOrderSetting:10,39,62`, `RecipeListScope` (`RecipeListQueryBuilder:27`, also not `Hashable`), `IngredientScaler.DisplayParts:12` (also no `public init`), `RecipeDuplicateFinder.MatchKey/FieldKey:76,94` (`FieldKey` no `public init`), `SchemaOrgRecipeJSONLDExporter:17,24`, `RecipeFromTextParser:11`, `IngredientTextParser:12`, `DirectionTextParser:12`, `SaltyRecipeFileError:10`, `ImportError:10`, `ShoppingListMerge.Resolution:33`.
- `CORE/ImportExport/SchemaOrgRecipeJSONLDImporter.swift:32` — a non-final `public class` with no mutable state for a stateless parser; make it a struct.
- `CORE/ImportExport/SchemaOrgRecipeJSONLDExporter.swift:108` — `jsonObject(for:)` returns `[String: Any]` (non-Sendable, untyped, awkward over the FFI); an `Encodable` struct.
- `CORE/Sync/ServerLibraryItems.swift`, `ServerRecipe.swift:12-258`, `ServerRecipeManifestEntry.swift` — several public DTOs per file with no `public init`, so FFI consumers can only build them via JSON; `ServerRecipe.from(_:)` (`:58-85`) silently omits `categoryIds` / `tagIds` (filled only by `ENGINE:2085-2086`).
- `ENGINE:1710-1714,1724-1732,2046-2063` — `JSONSerialization` with `[String: Any]` bodies beside a perfectly good `Codable` DTO layer.
- `CORE/ImportExport/SaltyRecipeExport.swift:192-196,267` — `fromRecipe(_:database:imageData:)` takes `any DatabaseWriter` but only reads, in three transactions; `fromRecipe(_:)` is `throws` but cannot throw.
- `CORE/ImportExport/CroutonImportRecipe.swift:93`, `MacGourmetImportRecipe.swift:215` — `inout` out-params for image/tags/categories that the only caller immediately copies into a `SaltyRecipeExport`.
- `CORE/Schema.swift:421-456` — `Difficulty` declares `id` but not `Identifiable` (`Rating` does); both carry `init(index:)` "for SwiftUI sliders".
- `CORE/LastSyncedDescription.swift:35,42,44` — the clock text uses the process locale and `TimeZone.current` while "today/yesterday" uses the injected `calendar`; around midnight they can disagree.
- `CORE/MarkdownToHtml.swift:67` — CSP lacks `form-action 'none'; base-uri 'none'`.
- `CORE/RecipeFromTextParser.swift:268-584` — `.info` logging per line and per regex match in a parser that runs on every import (twice per Smart Parse).

---

## 11. Tests

734 Swift Testing cases (the "463 baseline" in the project notes is stale), all pure Swift Testing except the untouched XCTest UI-test template. Strong where it exists: `RecipeSyncReconciler` (19 + 29 corpus), duplicate finders (27 + DB suite), query builders, `IngredientScaler`, `RecipeToShoppingList`, `RecipeItemListEditor` (33), `RecipeWriter` (16), `ShoppingListMerge`, `ChefViewModel` (24), the JSON-LD hardening suites, and a cross-client contract corpus that fails loudly when absent.

**Hygiene to fix first**

- `SaltySyncServiceServerEditTests.swift:105-107`, `SaltySyncServiceErrorPathTests.swift:43` — write `serverUrl` / `serverUse` / `serverUsername` into `UserDefaults.standard` and never restore them; every successful `syncNow` in ServerEditTests also persists `lastSuccessfulSyncDate` into the host app's defaults. Enrolment and cancellation tests restore correctly.
- `LibraryClassifierEditorTests.swift:123,156,180,240` — `Task.sleep(20ms)` to make `lastModifiedDate` move, because `LibraryClassifierEditor.create/rename` take no `now:` (§4.2).
- `SyncCancellationTests.swift:104-108,123` — polls `currentStep == "Registering device..."` with 10 ms sleeps and asserts on UI strings (§5).
- `RecipeImportRealWorldTests.swift:262-263` — exact counts asserted on on-device LLM output despite the header saying assertions stay loose; the likeliest red test on an OS update. `:208-211,252` and `FileHelperTests.swift:43,59` pass vacuously when a capability is absent; use `.enabled(if:)`.
- `LibraryClassifierQueryBuilderTests.swift:57-59` — `try! #require(...)` in a non-throwing test crashes the runner instead of recording a failure.
- `SyncImagePreparerTests.swift:28-36` — asserts the executor of a mirror probe, not of `SyncImagePreparer.prepare`; deleting `@concurrent` from the source would not fail it.
- `DatabaseTests.swift:10-15` — the cross-suite isolation claim is wrong in general: `.serialized` serialises within a suite; the "no concurrent `appDatabase()`" guarantee rests on the scheme's parallel-testing-off setting.
- Fixture duplication: `makeTestDatabase()` copied verbatim in `DatabaseTests:31`, `LibraryClassifierEditorTests:20`, `SaltySyncServiceServerEditTests:93`; the migrate triple inlined in seven more files; five separate `URLProtocol` stubs with three `makeService()` variants. `InMemorySyncCredentialStore.swift` shows the right pattern; the "passes alone, flaky alongside" note at `ServerEditTests:485-487` is the symptom.
- `ContractCorpus.swift:144-178` — resolution walks up from `#filePath` checking every immediate child of each ancestor (listing `/Users/rob`, `/Users`, `/` on a miss); CI must check out `salty-contract` beside `Salty` or set `SALTY_CORPUS_DIR`, and neither is documented in this repo (there is no CI config). `ContractCorpusTests.swift:268-270` REC-040 waiver comment is stale.

**Coverage gaps, ranked by risk**

1. `ServerSyncEngine` is tested only around its edges (auth, error codes, classifier deletes, one server-only download). Never exercised: the recipe upload direction, equal-timestamp no-op, delta paging across pages, `writeDownloadedRecipe` (image columns preserved, newer local prepared date kept, dangling `courseId` nulled), every branch of `syncImages` (including the equal-timestamp re-download and the "all failed" throw), `syncPreparedDates`, the shopping-list 409 conflict path, `consolidateDuplicateLibraryItems`, and `RecipeAgreementStore` / `ClassifierAgreementStore` directly.
2. `RecipeFromTextParser` — no direct test at all (§2 #3).
3. Nine of fifteen view models: `RecipeNavigationSplitViewModel`, `RecipeDetailEditViewModel`, `RecipeDetailViewModel`, `ShoppingListDetailViewModel`, `ShoppingListFreeformViewModel` (debounce / flush / reload-drops-pending / own-change suppression: the subtlest logic in the app), `CreateRecipeFromWebViewModel`, `DuplicateRecipesViewModel`, `ConsolidateDuplicatesViewModel`, `ShoppingListsMenuModel`.
4. `AutoSyncCoordinator` (untestable as written: private init, hard-wired `SaltySyncService.shared`, `Date()`, `UserDefaults.standard`), `ManualSyncRunner`, `RecipeDuplicator`, `RecipeLastPreparedWriter`, `RecipeImageManager.determineImageFormat`, `ZipService`, `PendingRecipeImage.apply` ordering, nutrition text round-trip.
5. Parser edge cases: no empty / CRLF / unicode vulgar fraction ("½ cup") inputs for the ingredient and direction parsers; `IngredientScaler` has no zero/negative/huge factor case; `SchemaOrgRecipeJSONLDImporter.Limits.maxScriptTags` untested.

**Ten tests to add next** (file → scenario)

1. `ServerSyncEngineImageSyncTests` — equal stamps + server file + no local → one GET; local filename but file missing on disk → re-download; local newer with no file → DELETE; all fail with nothing moved → `uploadFailed`.
2. `ServerSyncEngineBodyDownloadTests` — newer server body leaves image columns and a newer local prepared pair untouched; absent course id → NULL, no FK violation.
3. `ServerSyncEngineUploadTests` — local newer → exactly one PUT/POST without `X-Salty-Force`; equal stamps → no request; two-page delta consumed.
4. `ServerSyncEnginePreparedDateTests` — piggyback upload; targeted UPDATE leaves `lastModifiedDate` byte-identical.
5. `ShoppingListSyncConflictTests` — 409 → merge → second POST; second 409 leaves the row dirty.
6. `RecipeLastPreparedWriterTests` — moves only the prepared pair; nil clears; `localNoon` on a DST day.
7. `RecipeFromTextParserTests` — title + ingredient block + numbered steps; titles and directions containing "g"; empty; CRLF; 50 kB input; `RecipeImportParser.parse(preferSmart: false)` returns `.rules`.
8. `RecipeDuplicatorTests` — fresh nested ids, re-linked categories/tags, scaled note/name, image copied under the new id.
9. `AgreementStoreTests` — `isAvailable` before the shared migration; `markAgreed` → `stamps` round-trips to wire millis; `markAllAgreed` after force resync.
10. `AutoSyncCoordinatorTests` — after injecting `now`, a `SyncRunning` protocol, a `UserDefaults` suite and a `Clock`: throttle window, pause-for-a-day expiry, debounce coalescing, cancel never shows the banner.

---

## 12. Done well

- **`Writes/RecipeWriter`**: diff-based stamping with forward-only clocks, a 1 ms storage tolerance, injectable `now`, a `SaveOutcome` that exposes the decision, and `saveBody` for stale editors; pinned by 16 tests.
- **The shared migration ledger** (`Schema.swift:858-1039`): immutable ids, per-column existence guards, cross-client mirror notes, and the explicit "don't backfill, a NULL merely re-uploads once" reasoning.
- **SQL hygiene**: every user value is bound; identifiers are interpolated only from fixed literals and say so; the junction de-dup in `foldJunction` is careful and commented.
- **The sync design**: clock-free deletion inference via tombstones plus agreement stamps, "edit beats delete" in both directions, empty-side guards, server-only recipes downloaded rather than deleted, write-the-row-then-touch-files ordering everywhere, cancellation forwarded end to end and kept out of failure counts, the password used once and never stored, the token never logged.
- **The JSON-LD pipeline** (`JSONLDValue` / `JSONLDDataset` / `SchemaOrgRecipeReader` / `SchemaOrgYield`): strict JSON with a depth cap, field/list caps, `@id` dedup, `position` ordering, SSRF guards, streamed byte caps, every rule cross-referenced to the contract spec.
- **`PendingRecipeImage` + `RecipeImageAccess` + `deleteStaleImageFiles`**: a genuinely cancellable image edit with the file-then-row-then-delete ordering documented and honoured.
- **`RecipeItemListEditor`**: id-addressed insert/delete/move with the `toOffset` subtleties explained and 33 tests; the `binding(for:)` rationale comment is exemplary.
- **`StarRatingEditView`**: a model accessible control.
- **`ChefViewModel`** (SwiftUI-free, injected session store, rules in `SaltyCore.ChefStep`), **`ChefIngredientsAnchor`** (ends as ends, rows for the middle) and **`ChefExternalDisplayCoordinator`**'s close-then-reopen guard: external-display mirroring is designed rather than hacked, and the Chef views already use `ScrollPosition` / `onScrollTargetVisibilityChange` / `onScrollGeometryChange`.
- **`SidebarSectionOrder`**, **`DatabaseBackupManager.retainedBackupIndices`**, **`LastSyncedDescription`**, **`LastPreparedSummary`**: pure, injected, tested helpers, and the backup uses SQLite's online backup API for a consistent snapshot.
- **The `FocusedValues` actions** (`SearchFieldFocusAction`, `ChefViewOpenAction`, `AddressFieldFocusAction`) are the correct scene-scoped pattern and the template for fixing the command bus.
- **Smart Parse** is defensive by design: rules own yield/servings, any model failure falls back to rules, and the guardrail choice is explained in place.
- **Comments explain why**, consistently, across the whole codebase: alert vs confirmation dialog on iPad, macOS reorder arming, `.task` cancellation during pushes, WebKit pagination quirks, why `if focusAddressField != nil` cannot be used in Commands. This made the review far easier and is worth protecting.

---

## 13. Suggested order of work

1. **Half a day, user-visible bugs** — §2 items 1, 2, 5, 10 and the build warnings (§3); the `Int(Double)` guards (§2 #4); the HEIC prefix (§2 #15); the Chef VoiceOver label (§7).
2. **One day, write rules** — route the six bypasses through `Writes/` (§4.2), add `LibraryClassifierWriter` with `now:`, switch the editor to `saveBody`, fix the multi-id `touchLastModified`, and add `RecipeLastPreparedWriterTests`.
3. **One day, parsers** — whole-word unit/header matching in `RecipeFromTextParser`, expose the line parsers publicly, delete the copy in `ScanTextForRecipeView`, add `RecipeFromTextParserTests`; LIKE escaping in `RecipeSearchQuery` before the smart-list builder ships.
4. **One to two days, editor** — pending category/tag sets applied through `RecipeClassificationWriter` in the save transaction; `NutritionEditModel` in the core; the generic row editor (§9), which also closes the standalone-mode clipping bug, the five sleep hacks and the reorder accessibility gap.
5. **One day, macOS multi-window** — `MainWindowCommands` via `FocusedValue`, `MainSheet` enum, selection intersection, block-observer cleanup; retire the two tracker singletons.
6. **One day, shopping lists** — fix the `storedText` ordering, flush on `.inactive`, guarded update in `ShoppingListWriter`, then retire `ShoppingListChangeNotifier` in favour of `@FetchOne`; add the two editor VM test files.
7. **Ongoing** — sync hardening (§4.5: device id, image failure counter, URL normalisation, backoff) and the five engine test files (§11); move UI strings and keys out of the core (§5); then the mechanical AGENTS.md sweep (§8) file by file as each is next touched.
