//
//  SampleData.swift
//  Salty
//
//  Created by Robert on 07/05/25.
//

import Foundation

// MARK: - Shared Sample Data

/// Sample data that can be used for both database seeding and previews
struct SampleData {
    
    // MARK: - Sample Courses
    
    static let sampleCourses = [
        Course(id: "appetizer-id", name: "Appetizer"),
        Course(id: "main-id", name: "Main"),
        Course(id: "dessert-id", name: "Dessert"),
        Course(id: "snack-id", name: "Snack"),
        Course(id: "salad-id", name: "Salad"),
        Course(id: "fruit-id", name: "Fruit"),
        Course(id: "cheese-id", name: "Cheese"),
        Course(id: "vegetable-id", name: "Vegetable"),
        Course(id: "side-dish-id", name: "Side Dish"),
        Course(id: "bread-id", name: "Bread"),
        Course(id: "sauce-id", name: "Sauce"),
        Course(id: "beverage-id", name: "Beverage")
    ]
    
    // MARK: - Sample Recipes
    
    static let sampleRecipes = [
        // Main sample recipe
        Recipe(
            id: UUID().uuidString,
            name: "My Recipe",
            createdDate: Date(timeIntervalSinceNow: -60*24*30),
            lastModifiedDate: Date(),
            lastPrepared: Date(timeIntervalSinceNow: -60*24*45),
            source: "Some Book",
            sourceDetails: "https://www.epicurious.com/recipes/food/views/ba-syn-crispy-rice-salad-spicy-tahini-dressing",
            introduction: "This is an introduction for my recipe. Some introductions are long, so let's make this one long, too. Here is some more text. Is it long enough yet? Let's write more just in case. Yay, recipes!",
            difficulty: .somewhatEasy,
            rating: .four,
            imageFilename: "1A2C3B22-DEEC-4EB2-9BFB-19055D3CB8E1.jpg",
            imageThumbnailData: nil,
            isFavorite: true,
            wantToMake: true,
            yield: "2 dozen",
            servings: 36,
            courseId: "main-id",
            directions: [
                Direction(id: UUID().uuidString, text: "Do the first step. We'll make this text a bit longer so there is a chance that it will need to wrap or show other text rendering nuances. Lorem ipsum dolor sit amet consectetur adipisicing elit. Quo, molestias! Quasi, voluptatem. Now, let's move on to the next step -- but not before adding a bit more here just in case. Wow, what a long step!"),
                Direction(id: UUID().uuidString, text: "Now, do the second step."),
            ],
            ingredients: [
                Ingredient(id: UUID().uuidString, isMain: true, text: "1 cup flour"),
                Ingredient(id: UUID().uuidString, text: "1/2 cup water"),
                Ingredient(id: UUID().uuidString, text: "salt, to taste")
            ],
            notes: [
                Note(id: UUID().uuidString, title: "Note 1", content: "This is the text of the note")
            ],
            preparationTimes: [
                PreparationTime(id: UUID().uuidString, type: "Preparation", timeString: "25 Minutes"),
                PreparationTime(id: UUID().uuidString, type: "Total Time", timeString: "1 Hour, 30 Minutes")
            ],
            nutrition: NutritionInformation(
                servingSize: "1 serving",
                calories: 285,
                protein: 12.5,
                carbohydrates: 35.2,
                fat: 8.1,
                fiber: 2.8,
                sugar: 4.2,
                sodium: 420
            ),
            tags: ["tag1", "another-tag"]
        ),
        
        // Minimal sample recipe
        Recipe(
            id: UUID().uuidString,
            name: "Simple Recipe",
            source: "Preview Kitchen",
            introduction: "A simple recipe for preview purposes",
            courseId: "snack-id"
        ),
        
        // Complex sample recipe
        Recipe(
            id: UUID().uuidString,
            name: "Complex Recipe with Long Name That Might Wrap to Multiple Lines",
            createdDate: Date(),
            lastModifiedDate: Date(),
            lastPrepared: Date(timeIntervalSinceNow: -60*24*30),
            source: "Very Long Source Name That Might Also Wrap to Multiple Lines -- But Here is More Text Just in Case it Doesn't, And Maybe a Bit More Just to Make Sure in Case We Are Not There Yet",
            sourceDetails: "Additional source details that provide more context about where this recipe came from, plus more  source details that provide more context about where this recipe came from in case this wasn't long enough before",
            introduction: "This is a very long introduction that tests how the UI handles text wrapping and overflow. It contains multiple sentences and should demonstrate how the layout adapts to different content lengths. Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.",
            difficulty: .difficult,
            rating: .five,
            imageFilename: nil,
            imageThumbnailData: nil,
            isFavorite: true,
            wantToMake: true,
            yield: "8-10 servings",
            courseId: "dessert-id",
            directions: [
                Direction(id: UUID().uuidString, text: "First, prepare all your ingredients. This step is crucial for success."),
                Direction(id: UUID().uuidString, text: "Next, combine the dry ingredients in a large bowl."),
                Direction(id: UUID().uuidString, isHeading: true, text: "Next Steps"),
                Direction(id: UUID().uuidString, text: "In a separate bowl, whisk together the wet ingredients until well combined."),
                Direction(id: UUID().uuidString, text: "Gradually add the wet ingredients to the dry ingredients, stirring gently."),
                Direction(id: UUID().uuidString, text: "Pour the batter into a prepared pan and bake until done.")
            ],
            ingredients: [
                Ingredient(id: UUID().uuidString, isMain: true, text: "2 cups all-purpose flour"),
                Ingredient(id: UUID().uuidString, isMain: true, text: "1 cup granulated sugar"),
                Ingredient(id: UUID().uuidString, isMain: true, text: "1/2 cup unsalted butter, melted"),
                Ingredient(id: UUID().uuidString, isHeading: true, isMain: false, text: "For the frosting:"),
                Ingredient(id: UUID().uuidString, text: "1/2 cup powdered sugar"),
                Ingredient(id: UUID().uuidString, text: "2 tablespoons milk"),
                Ingredient(id: UUID().uuidString, text: "1 teaspoon vanilla extract")
            ],
            notes: [
                Note(id: UUID().uuidString, title: "Storage Tips", content: "Store in an airtight container for up to 3 days."),
                Note(id: UUID().uuidString, title: "Substitutions", content: "You can substitute whole wheat flour for up to half of the all-purpose flour."),
                Note(id: UUID().uuidString, title: "", content: "This is a note without a title to test how the UI handles missing titles.")
            ],
            preparationTimes: [
                PreparationTime(id: UUID().uuidString, type: "Prep", timeString: "15 minutes"),
                PreparationTime(id: UUID().uuidString, type: "Cook", timeString: "30 minutes"),
                PreparationTime(id: UUID().uuidString, type: "Total", timeString: "45 minutes")
            ]
        )
    ]
    
    // MARK: - Sample Categories
    
    static let sampleCategories = [
        Category(id: UUID().uuidString, name: "Breakfast"),
        Category(id: UUID().uuidString, name: "Quick"),
        Category(id: UUID().uuidString, name: "Vegetarian"),
        Category(id: UUID().uuidString, name: "Vegan"),
        Category(id: UUID().uuidString, name: "Beverage"),
        Category(id: UUID().uuidString, name: "Burger"),
        Category(id: UUID().uuidString, name: "Soup"),
        Category(id: UUID().uuidString, name: "Pasta"),
        Category(id: UUID().uuidString, name: "Gluten-Free"),
        Category(id: UUID().uuidString, name: "Dairy-Free"),
        Category(id: UUID().uuidString, name: "Low-Carb"),
        Category(id: UUID().uuidString, name: "Slow Cooker"),
        Category(id: UUID().uuidString, name: "Instant Pot"),
        Category(id: UUID().uuidString, name: "No-Cook"),
        Category(id: UUID().uuidString, name: "Kid-Friendly"),
        Category(id: UUID().uuidString, name: "Holiday"),
        Category(id: UUID().uuidString, name: "Comfort Food")
    ]
} 
