//
//  MainView.swift
//  Salty
//
//  Created by Robert on 6/6/25.
//

import SwiftUI
import SaltyCore

struct MainView: View {
    // Own the root view model here (created once) rather than re-instantiating it inside `body`
    // on every render. `isNewLaunch` is set via the initializer so it's applied to the persisted
    // instance, not a throwaway one.
    @State private var viewModel = RecipeNavigationSplitViewModel(isNewLaunch: true)

    // Confirmation for a .saltyRecipe opened/AirDropped into Salty (the manual "Import from File…"
    // menu uses its own picker + sheet).
    @State private var importConfirmURL: URL?
    @State private var importConfirmNames: [String] = []
    @State private var showingImportConfirm = false

    /// Why a `salty://` link couldn't be followed, shown as an alert; nil when there is nothing to say.
    @State private var linkProblem: String?

    @State private var autoSync = AutoSyncCoordinator.shared

    // Raised when a user-initiated sync stopped because this device isn't connected to the server yet.
    // Hosted here rather than at each trigger so pull-to-refresh, the "Last synced" footer and the Sync
    // Now menu command all get the same prompt -- the same one Settings uses, so the app asks for a
    // password in exactly one voice.
    @State private var manualSync = ManualSyncRunner.shared
    @State private var syncService = SaltySyncService.shared

    #if os(macOS)
    @Environment(\.controlActiveState) private var controlActiveState
    #else
    @Environment(\.scenePhase) private var scenePhase
    #endif

    /// The sync runner and coordinator are app-wide, but their prompt and banner belong in one
    /// window at a time: bound in every main window, the password sheet and the failure banner
    /// used to appear in all of them at once.
    private var isFrontmostWindow: Bool {
        #if os(macOS)
        controlActiveState == .key
        #else
        scenePhase == .active
        #endif
    }

    /// The enrolment prompt, shown by the frontmost window only. Dismissing clears the request.
    private var showingEnrolmentPrompt: Binding<Bool> {
        Binding(
            get: { manualSync.needsEnrolment && isFrontmostWindow },
            set: { if !$0 { manualSync.needsEnrolment = false } }
        )
    }

    var body: some View {
        RecipeNavigationSplitView(viewModel: viewModel)
            .task { autoSync.start() }
            .overlay(alignment: .top) {
                if autoSync.showFailureBanner && isFrontmostWindow {
                    AutoSyncFailureBanner(
                        onRetry: { Task { await autoSync.retryNow() } },
                        onDismiss: { autoSync.dismissFailureBanner() },
                        onPause: { autoSync.pauseForOneDay() }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: autoSync.showFailureBanner)
            .syncPasswordPrompt(isPresented: showingEnrolmentPrompt,
                                username: syncService.serverUsername) { password in
                // Connect, then finish the sync the user actually asked for.
                Task { await manualSync.connectAndSync(password: password) }
            }
            .onOpenURL { handleIncomingURL($0) }
            .alert("Import Recipe", isPresented: $showingImportConfirm) {
                Button("Cancel", role: .cancel) { importConfirmURL = nil }
                Button("Add") {
                    if let url = importConfirmURL {
                        Task { await viewModel.importOpenedRecipeFile(url) }
                    }
                    importConfirmURL = nil
                }
            } message: {
                Text(importConfirmMessage)
            }
            .alert("Can't Open Link", isPresented: showingLinkProblem) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(linkProblem ?? "")
            }
            #if os(iOS)
            // Pages shared to Salty from the share sheet wait in `ImportInbox` (the extension can't open
            // the app itself). Opened one at a time: when the app comes to the front, then as each
            // import closes.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { openNextSharedPage() }
            }
            .onChange(of: viewModel.isWebImporterPresented) { _, isUp in
                if !isUp { openNextSharedPage() }
            }
            #endif
    }

    #if os(iOS)
    private func openNextSharedPage() {
        // A request already made but not yet presented counts as presented, or two triggers landing in
        // the same update would each take a page and the first would be lost.
        guard viewModel.webImportRequest == nil, !viewModel.isWebImporterPresented,
              let page = ImportInbox.takeNext() else {
            return
        }
        open(.importFromWeb(page))
    }
    #endif

    private var showingLinkProblem: Binding<Bool> {
        Binding(
            get: { linkProblem != nil },
            set: { if !$0 { linkProblem = nil } }
        )
    }

    private var importConfirmMessage: String {
        switch importConfirmNames.count {
        case 0: return "Add this recipe to your library?"
        case 1: return "Add “\(importConfirmNames[0])” to your library?"
        default: return "Add these \(importConfirmNames.count) recipes to your library?"
        }
    }

    /// Everything the system hands this window to open: `salty://` links (see `SaltyURL`) and
    /// .saltyRecipe files (opened from Finder or Files, or AirDropped).
    private func handleIncomingURL(_ url: URL) {
        if let link = SaltyURL(url) {
            open(link)
        } else if url.pathExtension.lowercased() == "saltyrecipe" {
            importConfirmURL = url
            importConfirmNames = RecipeFileImportHelper.peekRecipeNames(url)
            showingImportConfirm = true
        }
    }

    private func open(_ link: SaltyURL) {
        switch link {
        case .importFromWeb(let page):
            // Web Import is built on SwiftUI's WebView, so there is nothing to open it in before OS 26.
            if #available(iOS 26.0, macOS 26.0, *) {
                viewModel.webImportRequest = page
            } else {
                linkProblem = "Web Import requires iOS 26 or macOS 26 or later."
            }
        case .recipe(let id):
            if !viewModel.showRecipe(id: id) {
                linkProblem = "That recipe isn't in this library. If it was added on another device, it may not have synced yet."
            }
        }
    }
}

#Preview {
    MainView()
        .environment(ChefViewSessionStore())
}
