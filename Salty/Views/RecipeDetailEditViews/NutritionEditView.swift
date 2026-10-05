//
//  NutritionEditView.swift
//  Salty
//
//  Created by Robert on 7/15/25.
//
//  The sheet lays out the fields; what they hold, whether it is a number, and what gets stored is
//  `NutritionEditModel`'s business (in SaltyCore, with tests).
//

import SwiftUI
import SaltyCore

struct NutritionEditView: View {
    @Binding var recipe: Recipe
    @State private var model: NutritionEditModel
    @Environment(\.dismiss) private var dismiss

    init(recipe: Binding<Recipe>) {
        _recipe = recipe
        _model = State(initialValue: NutritionEditModel(recipe.wrappedValue.nutrition))
    }

    var body: some View {
        NavigationStack {
            #if os(macOS)
            ScrollView {
                Form {
                    NutritionFormContent(model: $model)
                }
                .padding()
            }
            .navigationTitle("Edit Nutrition Information")
            .toolbar { toolbarContent }
            #else
            Form {
                NutritionFormContent(model: $model)
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("Edit Nutrition Information")
            .toolbar { toolbarContent }
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 300, idealWidth: 400, maxWidth: 500,
               minHeight: 400, idealHeight: 600, maxHeight: .infinity)
        .presentationSizing(.fitted)
        #endif
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") {
                dismiss()
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Save") {
                recipe.nutrition = model.nutrition
                dismiss()
            }
            .disabled(model.hasInvalidFields)
        }
    }
}

// MARK: - Form

private struct NutritionFormContent: View {
    @Binding var model: NutritionEditModel

    var body: some View {
        ForEach(NutritionEditModel.Section.allCases, id: \.self) { section in
            Section(header: PlatformSpecificSectionHeading(baseText: section.title)) {
                if section == .general {
                    ServingSizeField(text: $model.servingSize)
                }
                ForEach(section.fields, id: \.self) { field in
                    NutritionAmountField(
                        field.label,
                        text: Binding(get: { model[field] }, set: { model[field] = $0 }),
                        isValid: model.isValid(field)
                    )
                }
            }
        }
    }
}

private struct ServingSizeField: View {
    @Binding var text: String

    var body: some View {
        #if !os(macOS)
        LabeledContent("Serving Size") {
            TextField("e.g., 1 cup, 2 slices", text: $text)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
        }
        #else
        TextField("Serving Size:", text: $text)
            .textFieldStyle(.roundedBorder)
        #endif
    }
}

/// An amount field that shows a warning while what it holds isn't a number.
private struct NutritionAmountField: View {
    let label: String
    @Binding var text: String
    let isValid: Bool

    init(_ label: String, text: Binding<String>, isValid: Bool) {
        self.label = label
        self._text = text
        self.isValid = isValid
    }

    var body: some View {
        #if !os(macOS)
        LabeledContent(label) {
            HStack {
                TextField("No Information", text: $text)
                    .textFieldStyle(.plain)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                InvalidAmountMark(isShown: !isValid)
            }
        }
        #else
        HStack {
            TextField(label + ":", text: $text)
                .textFieldStyle(.roundedBorder)
            InvalidAmountMark(isShown: !isValid)
        }
        #endif
    }
}

private struct InvalidAmountMark: View {
    let isShown: Bool

    var body: some View {
        if isShown {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.caption)
                .accessibilityLabel("Not a number")
        }
    }
}

private struct PlatformSpecificSectionHeading: View {
    let baseText: String

    var body: some View {
        #if os(macOS)
        Text(baseText + ":")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
        #else
        Text(baseText)
        #endif
    }
}

// MARK: - Labels

private extension NutritionEditModel.Section {
    var title: String {
        switch self {
        case .general: "General"
        case .macronutrients: "Macronutrients"
        case .otherNutrients: "Other Nutrients"
        case .vitaminsAndMinerals: "Vitamins and Minerals"
        }
    }
}

private extension NutritionEditModel.Field {
    var label: String {
        if let unit {
            "\(name) (\(unit.symbol))"
        } else {
            name
        }
    }

    private var name: String {
        switch self {
        case .calories: "Calories"
        case .protein: "Protein"
        case .carbohydrates: "Carbohydrates"
        case .fat: "Total Fat"
        case .saturatedFat: "Saturated Fat"
        case .transFat: "Trans Fat"
        case .fiber: "Fiber"
        case .sugar: "Sugar"
        case .addedSugar: "Added Sugar"
        case .sodium: "Sodium"
        case .cholesterol: "Cholesterol"
        case .vitaminD: "Vitamin D"
        case .calcium: "Calcium"
        case .iron: "Iron"
        case .potassium: "Potassium"
        case .vitaminA: "Vitamin A"
        case .vitaminC: "Vitamin C"
        }
    }
}

private extension NutritionEditModel.Unit {
    var symbol: String {
        switch self {
        case .grams: "g"
        case .milligrams: "mg"
        case .micrograms: "μg"
        }
    }
}

#Preview {
    NutritionEditView(recipe: .constant(SampleData.sampleRecipes[0]))
}
