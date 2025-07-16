//
//  NutritionEditView.swift
//  Salty
//
//  Created by Robert on 7/15/25.
//

import SwiftUI

// MARK: - Validated Text Field Component
struct ValidatedTextField: View {
    let placeholder: String
    @Binding var text: String
    @Binding var isValid: Bool
    let allowEmpty: Bool
    
    init(_ placeholder: String, text: Binding<String>, isValid: Binding<Bool>, allowEmpty: Bool = true) {
        self.placeholder = placeholder
        self._text = text
        self._isValid = isValid
        self.allowEmpty = allowEmpty
    }
    
    var body: some View {
        HStack {
            TextField(placeholder, text: $text)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                // .overlay(
                //     RoundedRectangle(cornerRadius: 8)
                //         .stroke(isValid ? Color.clear : Color.red, lineWidth: 2)
                // )
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .onChange(of: text) { _, newValue in
                    validateNumericField(newValue)
                }
            
            if !isValid {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
    }
    
    private func validateNumericField(_ text: String) {
        if text.isEmpty && allowEmpty {
            isValid = true
        } else {
            isValid = Double(text) != nil
        }
    }
}

struct NutritionEditView: View {
    @Binding var recipe: Recipe
    @State private var editingNutrition = NutritionInformation()
    @Environment(\.dismiss) private var dismiss
    
    // String representations for text fields
    @State private var servingSizeText: String = ""
    @State private var caloriesText: String = ""
    @State private var proteinText: String = ""
    @State private var carbohydratesText: String = ""
    @State private var fatText: String = ""
    @State private var saturatedFatText: String = ""
    @State private var transFatText: String = ""
    @State private var fiberText: String = ""
    @State private var sugarText: String = ""
    @State private var addedSugarText: String = ""
    @State private var sodiumText: String = ""
    @State private var cholesterolText: String = ""
    @State private var vitaminDText: String = ""
    @State private var calciumText: String = ""
    @State private var ironText: String = ""
    @State private var potassiumText: String = ""
    @State private var vitaminAText: String = ""
    @State private var vitaminCText: String = ""
    
    // Validation state
    @State private var isCaloriesValid: Bool = true
    @State private var isProteinValid: Bool = true
    @State private var isCarbohydratesValid: Bool = true
    @State private var isFatValid: Bool = true
    @State private var isSaturatedFatValid: Bool = true
    @State private var isTransFatValid: Bool = true
    @State private var isFiberValid: Bool = true
    @State private var isSugarValid: Bool = true
    @State private var isAddedSugarValid: Bool = true
    @State private var isSodiumValid: Bool = true
    @State private var isCholesterolValid: Bool = true
    @State private var isVitaminDValid: Bool = true
    @State private var isCalciumValid: Bool = true
    @State private var isIronValid: Bool = true
    @State private var isPotassiumValid: Bool = true
    @State private var isVitaminAValid: Bool = true
    @State private var isVitaminCValid: Bool = true
    
    // Computed property to check if there are any validation errors
    private var hasValidationErrors: Bool {
        !isCaloriesValid || !isProteinValid || !isCarbohydratesValid || !isFatValid ||
        !isSaturatedFatValid || !isTransFatValid || !isFiberValid || !isSugarValid ||
        !isAddedSugarValid || !isSodiumValid || !isCholesterolValid || !isVitaminDValid ||
        !isCalciumValid || !isIronValid || !isPotassiumValid || !isVitaminAValid || !isVitaminCValid
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("General:") {
                    TextField("Serving Size (e.g., 1 cup, 2 slices)", text: $servingSizeText)
                    
                    ValidatedTextField("Calories", text: $caloriesText, isValid: $isCaloriesValid)
                }
                
                Section("Macronutrients:") {
                    ValidatedTextField("Protein (g)", text: $proteinText, isValid: $isProteinValid)
                    ValidatedTextField("Carbohydrates (g)", text: $carbohydratesText, isValid: $isCarbohydratesValid)
                    ValidatedTextField("Total Fat (g)", text: $fatText, isValid: $isFatValid)
                    ValidatedTextField("Saturated Fat (g)", text: $saturatedFatText, isValid: $isSaturatedFatValid)
                    ValidatedTextField("Trans Fat (g)", text: $transFatText, isValid: $isTransFatValid)
                    ValidatedTextField("Fiber (g)", text: $fiberText, isValid: $isFiberValid)
                    ValidatedTextField("Sugar (g)", text: $sugarText, isValid: $isSugarValid)
                    ValidatedTextField("Added Sugar (g)", text: $addedSugarText, isValid: $isAddedSugarValid)
                }
                
                Section("Other Nutrients:") {
                    ValidatedTextField("Sodium (mg)", text: $sodiumText, isValid: $isSodiumValid)
                    ValidatedTextField("Cholesterol (mg)", text: $cholesterolText, isValid: $isCholesterolValid)
                }
                
                Section("Vitamins & Minerals:") {
                    ValidatedTextField("Vitamin D (μg)", text: $vitaminDText, isValid: $isVitaminDValid)
                    ValidatedTextField("Calcium (mg)", text: $calciumText, isValid: $isCalciumValid)
                    ValidatedTextField("Iron (mg)", text: $ironText, isValid: $isIronValid)
                    ValidatedTextField("Potassium (mg)", text: $potassiumText, isValid: $isPotassiumValid)
                    ValidatedTextField("Vitamin A (μg)", text: $vitaminAText, isValid: $isVitaminAValid)
                    ValidatedTextField("Vitamin C (mg)", text: $vitaminCText, isValid: $isVitaminCValid)
                }
            }
            .padding()
            .navigationTitle("Edit Nutrition Information")
            //.navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                        dismiss()
                    }
                    .disabled(hasValidationErrors)
                }
            }
            .onAppear {
                loadInitialValues()
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 500)
        #endif
    }
    
    private func loadInitialValues() {
        let nutrition = recipe.nutrition ?? NutritionInformation()
        editingNutrition = nutrition
        
        servingSizeText = nutrition.servingSize ?? ""
        caloriesText = nutrition.calories?.formatted() ?? ""
        proteinText = nutrition.protein?.formatted() ?? ""
        carbohydratesText = nutrition.carbohydrates?.formatted() ?? ""
        fatText = nutrition.fat?.formatted() ?? ""
        saturatedFatText = nutrition.saturatedFat?.formatted() ?? ""
        transFatText = nutrition.transFat?.formatted() ?? ""
        fiberText = nutrition.fiber?.formatted() ?? ""
        sugarText = nutrition.sugar?.formatted() ?? ""
        addedSugarText = nutrition.addedSugar?.formatted() ?? ""
        sodiumText = nutrition.sodium?.formatted() ?? ""
        cholesterolText = nutrition.cholesterol?.formatted() ?? ""
        vitaminDText = nutrition.vitaminD?.formatted() ?? ""
        calciumText = nutrition.calcium?.formatted() ?? ""
        ironText = nutrition.iron?.formatted() ?? ""
        potassiumText = nutrition.potassium?.formatted() ?? ""
        vitaminAText = nutrition.vitaminA?.formatted() ?? ""
        vitaminCText = nutrition.vitaminC?.formatted() ?? ""
    }
    
    private func updateNutrition() {
        editingNutrition.servingSize = servingSizeText.isEmpty ? nil : servingSizeText
        editingNutrition.calories = Double(caloriesText)
        editingNutrition.protein = Double(proteinText)
        editingNutrition.carbohydrates = Double(carbohydratesText)
        editingNutrition.fat = Double(fatText)
        editingNutrition.saturatedFat = Double(saturatedFatText)
        editingNutrition.transFat = Double(transFatText)
        editingNutrition.fiber = Double(fiberText)
        editingNutrition.sugar = Double(sugarText)
        editingNutrition.addedSugar = Double(addedSugarText)
        editingNutrition.sodium = Double(sodiumText)
        editingNutrition.cholesterol = Double(cholesterolText)
        editingNutrition.vitaminD = Double(vitaminDText)
        editingNutrition.calcium = Double(calciumText)
        editingNutrition.iron = Double(ironText)
        editingNutrition.potassium = Double(potassiumText)
        editingNutrition.vitaminA = Double(vitaminAText)
        editingNutrition.vitaminC = Double(vitaminCText)
    }
    
    private func saveChanges() {
        updateNutrition()
        
        // Only save if there's actual nutrition data, otherwise set to nil
        let hasAnyData = !servingSizeText.isEmpty ||
                        !caloriesText.isEmpty ||
                        !proteinText.isEmpty ||
                        !carbohydratesText.isEmpty ||
                        !fatText.isEmpty ||
                        !saturatedFatText.isEmpty ||
                        !transFatText.isEmpty ||
                        !fiberText.isEmpty ||
                        !sugarText.isEmpty ||
                        !addedSugarText.isEmpty ||
                        !sodiumText.isEmpty ||
                        !cholesterolText.isEmpty ||
                        !vitaminDText.isEmpty ||
                        !calciumText.isEmpty ||
                        !ironText.isEmpty ||
                        !potassiumText.isEmpty ||
                        !vitaminAText.isEmpty ||
                        !vitaminCText.isEmpty
        
        recipe.nutrition = hasAnyData ? editingNutrition : nil
    }
}

//#Preview {
//    NutritionEditView(recipe: .constant(SampleData.sampleRecipes[0]))
//}
