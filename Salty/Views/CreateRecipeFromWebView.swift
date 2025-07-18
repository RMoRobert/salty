//
//  CreateRecipeFromWebView.swift
//  Salty
//
//  Created by Robert on 1/13/25.
//

#if os(macOS)
import SwiftUI

struct CreateRecipeFromWebView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = CreateRecipeFromWebViewModel()
    @State private var webView: WebViewCoordinator?
    
    var body: some View {
        NavigationStack {
            HSplitView {
                // Left side - Web Browser
                RecipeWebBrowserView(viewModel: viewModel, webView: $webView)
                    .frame(minWidth: 400, idealWidth: 600)
                
                // Right side - Recipe Editor
                RecipeWebImportEditView(viewModel: viewModel)
                    .frame(minWidth: 400, idealWidth: 500)
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Cancel") {
                        if viewModel.hasRecipeData {
                            viewModel.showingCancelAlert = true
                        } else {
                            dismiss()
                        }
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Save Recipe") {
                        if viewModel.hasRecipeData {
                            viewModel.saveRecipe()
                            dismiss()
                        } else {
                            viewModel.showingSaveAlert = true
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .onKeyPress(.init("1"), phases: .down) { keyPress in
            if keyPress.modifiers.contains(.command) {
                return handleKeyPress("1")
            }
            return .ignored
        }
        .onKeyPress(.init("2"), phases: .down) { keyPress in
            if keyPress.modifiers.contains(.command) {
                return handleKeyPress("2")
            }
            return .ignored
        }
        .onKeyPress(.init("3"), phases: .down) { keyPress in
            if keyPress.modifiers.contains(.command) {
                return handleKeyPress("3")
            }
            return .ignored
        }
        .onKeyPress(.init("4"), phases: .down) { keyPress in
            if keyPress.modifiers.contains(.command) {
                return handleKeyPress("4")
            }
            return .ignored
        }
        .onKeyPress(.init("5"), phases: .down) { keyPress in
            if keyPress.modifiers.contains(.command) {
                return handleKeyPress("5")
            }
            return .ignored
        }
        .onKeyPress(.init("6"), phases: .down) { keyPress in
            if keyPress.modifiers.contains(.command) {
                return handleKeyPress("6")
            }
            return .ignored
        }
        .onKeyPress(.init("7"), phases: .down) { keyPress in
            if keyPress.modifiers.contains(.command) {
                return handleKeyPress("7")
            }
            return .ignored
        }
        .onKeyPress(.init("8"), phases: .down) { keyPress in
            if keyPress.modifiers.contains(.command) {
                return handleKeyPress("8")
            }
            return .ignored
        }
        .alert("Discard Changes?", isPresented: $viewModel.showingCancelAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Discard", role: .destructive) {
                dismiss()
            }
        } message: {
            Text("You have unsaved recipe data. Are you sure you want to discard it?")
        }
        .alert("No Recipe Data", isPresented: $viewModel.showingSaveAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please add recipe information before saving.")
        }
    }
    
    private func handleKeyPress(_ key: String) -> KeyPress.Result {
        let fieldMap: [String: RecipeField] = [
            "1": .name,
            "2": .source,
            "3": .sourceDetails,
            "4": .servings,
            "5": .ingredients,
            "6": .directions,
            "7": .yield,
            "8": .introduction
        ]
        
        if let field = fieldMap[key] {
            extractSelectedTextToField(field)
            return .handled
        }
        return .ignored
    }
    
    private func extractSelectedTextToField(_ field: RecipeField, retryCount: Int = 0) {
        guard let webView = webView else {
            if retryCount < 5 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.extractSelectedTextToField(field, retryCount: retryCount + 1)
                }
            }
            return
        }
        
        webView.getSelectedText { selectedText in
            DispatchQueue.main.async {
                if let text = selectedText, !text.isEmpty {
                    self.viewModel.extractTextToField(text, field: field)
                }
            }
        }
    }
}

// MARK: - Recipe Web Browser View
struct RecipeWebBrowserView: View {
    @Bindable var viewModel: CreateRecipeFromWebViewModel
    @Binding var webView: WebViewCoordinator?
    @State private var urlText: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // URL Bar and Navigation Controls
            HStack(spacing: 0) {
                Button(action: { webView?.goBack() }) {
                    Label("Back", systemImage: "chevron.left")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canGoBack)
                .padding(4)
                
                Button(action: { webView?.goForward() }) {
                    Label("Forward", systemImage: "chevron.right")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canGoForward)
                .padding(4)
                
                
                Button(action: {
                    goHome()
                }) {
                    Label("Home", systemImage: "house")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                .padding(4)
                
                Button(action: { webView?.reload() }) {
                    Label("Reload", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isLoading)
                .padding(4)
                
                TextField("Enter URL", text: $urlText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        navigateToURL()
                    }
                    .onAppear {
                        urlText = (viewModel.currentURL.isEmpty || viewModel.currentURL.starts(with: "file://")) ? "about:home" : viewModel.currentURL
                    }
                    .onChange(of: viewModel.currentURL) { _, newURL in
                        urlText = (newURL.isEmpty || newURL.starts(with: "file://")) ? "about:home" : newURL
                    }
                
                Button(action: { navigateToURL() }) {
                    Label("Go", systemImage: "arrow.right")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isLoading || urlText == ((viewModel.currentURL.isEmpty || viewModel.currentURL.starts(with: "file://")) ? "about:home" : viewModel.currentURL))
                .padding(2)
                
                Spacer()
                
                Button( action: {
                    scanWebpageForRecipeData()
                }) {
                    Label("Auto Import", systemImage: "square.and.arrow.down")
                }
                .disabled(viewModel.isLoading || viewModel.currentURL.isEmpty || viewModel.currentURL.starts(with: "about:") || viewModel.currentURL.starts(with: "file://"))
                .buttonStyle(.bordered)
                .padding([.trailing], 8)
                
                // Reserved space for progress spinner
                HStack {
                    ProgressView()
                        .controlSize(.small)
                        .opacity(viewModel.isLoading ? 1.0 : 0.0)
                }
                .frame(width: 20)
                .padding([.trailing], 4)
            }
            .padding(4)
            
            // Web View
            WebViewRepresentable(
                content: viewModel.currentURL.isEmpty ? .htmlResource("createRecipeFromWebLandingPage") : .url(viewModel.currentURL),
                coordinator: $webView,
                onNavigationStateChange: { canGoBack, canGoForward, isLoading in
                    viewModel.updateNavigationState(
                        canGoBack: canGoBack,
                        canGoForward: canGoForward,
                        isLoading: isLoading
                    )
                },
                onURLChange: { newURL in
                    viewModel.currentURL = newURL
                }
            )
        }
        .background(Color(.windowBackgroundColor))
    }
    
    private func navigateToURL() {
        // Handle special "about:home" URL
        if urlText == "about:home" {
            goHome()
            return
        }
        
        // Only navigate if URL is different and not currently loading
        let currentDisplayURL = (viewModel.currentURL.isEmpty || viewModel.currentURL.starts(with: "file://")) ? "about:home" : viewModel.currentURL
        if urlText != currentDisplayURL && !viewModel.isLoading {
            viewModel.navigateToURL(urlText)
        }
    }
    
    private func goHome() {
        viewModel.currentURL = ""
        urlText = "about:home"
        // Reset loading state since HTML content loads immediately
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            viewModel.updateNavigationState(canGoBack: false, canGoForward: false, isLoading: false)
        }
    }
    
    private func scanWebpageForRecipeData() {
        guard let webView = webView else { return }
        
        webView.getPageHTML { html in
            guard let html = html else { return }
            
            DispatchQueue.main.async {
                let importer = SchemaOrgRecipeJSONLDImporter()
                let recipes = importer.parseRecipes(from: html)
                
                if let firstRecipe = recipes.first {
                    // Populate the viewModel with the found recipe data
                    self.viewModel.populateFromScannedRecipe(firstRecipe)
                }
            }
        }
    }
}

// MARK: - Recipe Web Import Edit View
struct RecipeWebImportEditView: View {
    @Bindable var viewModel: CreateRecipeFromWebViewModel
    
    var body: some View {
        ScrollView {
            
            VStack(alignment: .leading, spacing: 16) {
                Text("Import Recipe Contents")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .frame(alignment: .leading)
                
                Text("Basic Information")
                    .font(.headline)
                
                
                Form {
                    
                    TextField("Name:", text: $viewModel.recipe.name, prompt: Text("Name (⌘1)"))
                    TextField("Source:", text: $viewModel.recipe.source, prompt: Text("Source (⌘2)"))
                    TextField("Source Details:", text: $viewModel.recipe.sourceDetails, prompt: Text("Source Details (⌘3)"))
                    TextField("Servings", value: $viewModel.recipe.servings, format: .number, prompt: Text("Servings (⌘4)"))
                    TextField("Yield", text: $viewModel.recipe.yield, prompt: Text("Yield (⌘7)"))
                }
                
                // Introduction Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Introduction")
                            .font(.headline)
                        Spacer()
                        Text("(⌘8)")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    
                    TextEditor(text: $viewModel.recipe.introduction)
                        .frame(minHeight: 60)
                        .border(Color.secondary.opacity(0.3))
                }
                .padding(.bottom, 16)
                
                // Ingredients Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Ingredients")
                            .font(.headline)
                        Spacer()
                        Text("(⌘5)")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    
                    TextEditor(text: $viewModel.ingredientsText)
                        .frame(minHeight: 120)
                        .border(Color.secondary.opacity(0.3))
                        .font(.system(.body, design: .monospaced))
                    
                    Button("Clean Up Text") {
                        viewModel.ingredientsText = IngredientTextParser.cleanUpText(viewModel.ingredientsText)
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.ingredientsText.isEmpty)
                }
                .padding(.bottom, 16)
                
                // Directions Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Directions")
                            .font(.headline)
                        Spacer()
                        Text("(⌘6)")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    
                    TextEditor(text: $viewModel.directionsText)
                        .frame(minHeight: 120)
                        .border(Color.secondary.opacity(0.3))
                        .font(.system(.body, design: .monospaced))
                    
                    Button("Clean Up Text") {
                        viewModel.directionsText = DirectionTextParser.cleanUpText(viewModel.directionsText)
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.directionsText.isEmpty)
                }
                .padding(.bottom, 16)
                
                
                // Categories Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Categories")
                        .font(.headline)
                    
                    Button("Edit Categories") {
                        viewModel.showingCategoriesSheet = true
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.bottom, 16)
                
                // Courses Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Course")
                        .font(.headline)
                    
                    Picker("Course", selection: $viewModel.recipe.courseId) {
                        Text("(No Course)")
                            .tag(nil as String?)
                        
                        ForEach(viewModel.courses) { course in
                            Text(course.name)
                                .tag(course.id as String?)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 300, alignment: .leading)
                }
                .padding(.bottom, 16)
                
                // Preparation Times Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Preparation Times")
                        .font(.headline)
                    
                    if viewModel.recipe.preparationTimes.isEmpty {
                        Text("No preparation times added")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(viewModel.recipe.preparationTimes) { time in
                            Text("\(time.type): \(time.timeString)")
                        }
                    }
                    
                    Button("Edit Times") {
                        viewModel.showingPreparationTimesSheet = true
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.bottom, 16)
                
                // Notes Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Notes")
                        .font(.headline)
                    
                    if viewModel.recipe.notes.isEmpty {
                        Text("No notes added")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(viewModel.recipe.notes) { note in
                            VStack(alignment: .leading) {
                                if !note.title.isEmpty {
                                    Text(note.title)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                }
                                Text(note.content)
                                    .font(.body)
                            }
                        }
                    }
                    
                    Button("Edit Notes") {
                        viewModel.showingNotesSheet = true
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.bottom, 16)
                
                // Nutrition Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Nutrition Information")
                        .font(.headline)
                    
                    if let nutrition = viewModel.recipe.nutrition {
                        VStack(alignment: .leading, spacing: 8) {
                            if let servingSize = nutrition.servingSize {
                                Text("Serving Size: \(servingSize)")
                                    .font(.subheadline)
                            }
                            
                            if let calories = nutrition.calories {
                                Text("Calories: \(Int(calories))")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                            
                            // Macronutrients
                            if nutrition.protein != nil || nutrition.carbohydrates != nil || nutrition.fat != nil {
                                VStack(alignment: .leading, spacing: 4) {
                                    if let protein = nutrition.protein {
                                        Text("Protein: \(formatNutritionValue(protein))g")
                                    }
                                    if let carbs = nutrition.carbohydrates {
                                        Text("Carbohydrates: \(formatNutritionValue(carbs))g")
                                    }
                                    if let fat = nutrition.fat {
                                        Text("Fat: \(formatNutritionValue(fat))g")
                                    }
                                    if let fiber = nutrition.fiber {
                                        Text("Fiber: \(formatNutritionValue(fiber))g")
                                    }
                                    if let sugar = nutrition.sugar {
                                        Text("Sugar: \(formatNutritionValue(sugar))g")
                                    }
                                    if let sodium = nutrition.sodium {
                                        Text("Sodium: \(formatNutritionValue(sodium))mg")
                                    }
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        Text("No nutrition information available")
                            .foregroundColor(.secondary)
                    }
                    
                    Button("Edit Nutrition") {
                        viewModel.showingNutritionEditSheet = true
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.bottom, 16)
                
                
                
                // Photo Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Photo")
                        .font(.headline)
                    
                    RecipeImageEditView(recipe: $viewModel.recipe, imageFrameSize: 120)
                }
                .padding(.bottom, 16)
                
                
            }
            .padding()
        }
        .background(Color(.controlBackgroundColor))
        .sheet(isPresented: $viewModel.showingCategoriesSheet) {
            CategoryEditView(recipe: $viewModel.recipe)
        }
        .sheet(isPresented: $viewModel.showingPreparationTimesSheet) {
            PreparationTimesEditView(recipe: $viewModel.recipe)
        }
        .sheet(isPresented: $viewModel.showingNotesSheet) {
            NotesEditView(recipe: $viewModel.recipe)
        }
        .sheet(isPresented: $viewModel.showingNutritionEditSheet) {
            NutritionEditView(recipe: $viewModel.recipe)
        }
    }
    
    private func formatNutritionValue(_ value: Double) -> String {
        if value == floor(value) {
            return String(Int(value))
        } else {
            return String(format: "%.1f", value)
        }
    }
}

#Preview {
    CreateRecipeFromWebView()
}

#endif
