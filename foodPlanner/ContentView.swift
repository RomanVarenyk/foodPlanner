//
//  ContentView.swift
//  FoodPlanner
//

import SwiftUI
import Combine

// ────────────────────────────────────────────
// MARK: – Models
// ────────────────────────────────────────────

struct Ingredient: Hashable, Codable {
    let name: String
    let quantity: Double?
    let unit: String?
}

enum MealType: String, CaseIterable, Codable {
    case breakfast = "Breakfast"
    case lunch     = "Lunch"
    case dinner    = "Dinner"
}

struct Recipe: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var mealType: MealType
    var serves: Int
    var ingredients: [Ingredient]
    var instructions: [String]
}

struct SavedMealPlan: Identifiable, Codable {
    let id: UUID
    let name: String
    let date: Date
    let plan: [MealType:[Recipe]]
    let servings: Int
}

// ────────────────────────────────────────────
// MARK: – ViewModel
// ────────────────────────────────────────────

final class RecipesViewModel: ObservableObject {
    // Built-in + user recipes
    @Published var customRecipes: [Recipe] = []
    @Published var removedRecipeIDs: Set<UUID> = []
    
    // Saved plans
    @Published var savedMealPlans: [SavedMealPlan] = []
    
    // In-flight edit & last-generated plan
    @Published var editingRecipe: Recipe? = nil
    @Published var weeklyPlan: [MealType:[Recipe]] = [:]
    @Published var currentServings: Int = 1
    
    // Full day names
    let days = ["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"]
    
    // Hard-coded built-in samples
    private let builtIn: [MealType:[Recipe]] = [
        .breakfast: [
            Recipe(
                id: UUID(), name: "Oatmeal", mealType: .breakfast, serves: 1,
                ingredients: [
                    Ingredient(name: "Rolled oats", quantity: 0.5, unit: "cup"),
                    Ingredient(name: "Milk",        quantity: 1,   unit: "cup"),
                    Ingredient(name: "Honey",       quantity: 1,   unit: "tbsp")
                ],
                instructions: [
                    "Combine oats and milk in pot.",
                    "Cook on medium heat until thick.",
                    "Stir in honey and serve."
                ]
            )
        ],
        .lunch: [
            Recipe(
                id: UUID(), name: "Grilled Chicken Salad", mealType: .lunch, serves: 1,
                ingredients: [
                    Ingredient(name: "Chicken breast", quantity: 1, unit: "pc"),
                    Ingredient(name: "Lettuce",        quantity: 2, unit: "cups"),
                    Ingredient(name: "Tomato",         quantity: 1, unit: "pc")
                ],
                instructions: [
                    "Grill chicken and slice.",
                    "Toss with lettuce and tomato.",
                    "Dress with olive oil and vinegar."
                ]
            )
        ],
        .dinner: [
            Recipe(
                id: UUID(), name: "Chicken Soup", mealType: .dinner, serves: 5,
                ingredients: [
                    Ingredient(name: "Onion",         quantity: 1,   unit: "large"),
                    Ingredient(name: "Potato",        quantity: 1,   unit: "kg"),
                    Ingredient(name: "Carrots",       quantity: 0.7, unit: "kg"),
                    Ingredient(name: "Chicken",       quantity: 1,   unit: "kg"),
                    Ingredient(name: "Bay leaf",      quantity: nil, unit: nil),
                    Ingredient(name: "Salt + pepper", quantity: nil, unit: nil)
                ],
                instructions: [
                    "Skin potato, onion, carrot",
                    "Dice onion",
                    "Cut potato into pieces that are digestible",
                    "Cut carrots thin",
                    "Put chicken in pot, cover with water plus 2/3 finger",
                    "Bring to boil, add ingredients, simmer 40 min until soft"
                ]
            )
        ]
    ]
    
    /// Merge built-in (minus removed) + custom
    var recipesByType: [MealType:[Recipe]] {
        var dict = builtIn
        // filter out removed built-ins
        for m in MealType.allCases {
            dict[m] = dict[m]?.filter { !removedRecipeIDs.contains($0.id) } ?? []
        }
        // ensure categories exist
        MealType.allCases.forEach { dict[$0] = dict[$0] ?? [] }
        // append customs
        for r in customRecipes {
            dict[r.mealType]?.append(r)
        }
        return dict
    }
    
    // ─ Generate Weekly Plan ──────────────────
    func generatePlan(forServings s: Int) {
        currentServings = s
        weeklyPlan = [:]
        for m in MealType.allCases {
            let list = recipesByType[m] ?? []
            guard !list.isEmpty else { continue }
            let shuffled = list.shuffled()
            weeklyPlan[m] = (0..<days.count).map { shuffled[$0 % shuffled.count] }
        }
    }
    
    // ─ Add or Update Recipe ─────────────────
    func addOrUpdate(recipe: Recipe) {
        if let idx = customRecipes.firstIndex(where: { $0.id == recipe.id }) {
            customRecipes[idx] = recipe
        } else {
            customRecipes.append(recipe)
        }
        saveRecipes()
    }
    
    // ─ Delete Recipe ────────────────────────
    func delete(recipe: Recipe) {
        let list = recipesByType[recipe.mealType] ?? []
        guard list.count > 1 else { return } // UI prevents last-one removal
        if let idx = customRecipes.firstIndex(where: { $0.id == recipe.id }) {
            customRecipes.remove(at: idx)
            saveRecipes()
        } else {
            removedRecipeIDs.insert(recipe.id)
            saveRemoved()
        }
    }
    
    // ─ Save Current Plan ────────────────────
    func saveCurrentPlan(named name: String) {
        let mon = monday(of: Date())
        let plan = SavedMealPlan(
            id: UUID(), name: name, date: mon,
            plan: weeklyPlan, servings: currentServings
        )
        savedMealPlans.append(plan)
        savePlans()
    }
    
    func defaultPlanName() -> String {
        let mon = monday(of: Date())
        let df = DateFormatter(); df.dateFormat = "MMMM d"
        return "Week of \(df.string(from: mon)) meal plan"
    }
    
    // ────────────────────────────────────────────
    // MARK: – Persistence
    // ────────────────────────────────────────────
    
    private var recipesURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("custom_recipes.json")
    }
    private var removedURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("removed_ids.json")
    }
    private var plansURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("saved_plans.json")
    }
    
    init() {
        loadRecipes()
        loadRemoved()
        loadPlans()
    }
    
    private func saveRecipes() {
        guard let data = try? JSONEncoder().encode(customRecipes) else { return }
        try? data.write(to: recipesURL)
    }
    private func loadRecipes() {
        guard let data = try? Data(contentsOf: recipesURL),
              let arr = try? JSONDecoder().decode([Recipe].self, from: data)
        else { return }
        customRecipes = arr
    }
    
    private func saveRemoved() {
        guard let data = try? JSONEncoder().encode(Array(removedRecipeIDs)) else { return }
        try? data.write(to: removedURL)
    }
    private func loadRemoved() {
        guard let data = try? Data(contentsOf: removedURL),
              let arr = try? JSONDecoder().decode([UUID].self, from: data)
        else { return }
        removedRecipeIDs = Set(arr)
    }
    
    private func savePlans() {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(savedMealPlans) else { return }
        try? data.write(to: plansURL)
    }
    private func loadPlans() {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: plansURL),
              let arr = try? dec.decode([SavedMealPlan].self, from: data)
        else { return }
        savedMealPlans = arr
    }
    
    private func monday(of date: Date) -> Date {
        var cal = Calendar.current; cal.firstWeekday = 2
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return cal.date(from: comps)!
    }
}

// ────────────────────────────────────────────
// MARK: – Helpers & Styles
// ────────────────────────────────────────────

fileprivate extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

extension Binding where Value == String? {
    var bound: Binding<String> {
        Binding<String>(
            get: { wrappedValue ?? "" },
            set: { wrappedValue = $0 }
        )
    }
}

extension View {
    func fullWidthStyle() -> some View {
        self
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                LinearGradient(
                    gradient: .init(colors: [Color.blue, Color.purple]),
                    startPoint: .leading, endPoint: .trailing
                )
            )
            .foregroundColor(.white)
            .cornerRadius(10)
            .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
    }
}

// ────────────────────────────────────────────
// MARK: – App Entry Point
// ────────────────────────────────────────────

@main
struct MealPlannerApp: App {
    @StateObject private var vm = RecipesViewModel()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(vm)
        }
    }
}

// ────────────────────────────────────────────
// MARK: – ContentView (Home Screen)
// ────────────────────────────────────────────

struct ContentView: View {
    @EnvironmentObject var vm: RecipesViewModel
    
    @State private var servings    = 1
    @State private var showPlan    = false
    @State private var showAdd     = false
    @State private var showMassAdd = false
    @State private var showSaved   = false
    @State private var showRecipes = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                Stepper("Servings per meal: \(servings)",
                        value: $servings, in: 1...20)
                    .padding(.horizontal)
                
                Button("Generate Weekly Plan") {
                    vm.generatePlan(forServings: servings)
                    showPlan = true
                }.fullWidthStyle()
                
                Button("Add Recipe") {
                    vm.editingRecipe = nil
                    showAdd = true
                }.fullWidthStyle()
                
                Button("Mass Recipe Add") {
                    showMassAdd = true
                }.fullWidthStyle()
                
                Button("View Saved Meal Plans") {
                    showSaved = true
                }.fullWidthStyle()
                
                Button("View Recipes") {
                    showRecipes = true
                }.fullWidthStyle()
                
                Spacer()
            }
            .padding()
            .navigationTitle("Weekly Meal Planner")
            // hidden nav link for plan
            .background(
                NavigationLink(
                    destination: PlanTabsView(
                        weeklyPlan: vm.weeklyPlan,
                        servings: vm.currentServings,
                        days: vm.days,
                        title: "This Week’s Plan",
                        showSave: true
                    )
                    .environmentObject(vm),
                    isActive: $showPlan
                ) { EmptyView() }
                .hidden()
            )
            // sheets
            .sheet(isPresented: $showAdd) {
                AddRecipeView(recipe: $vm.editingRecipe)
                    .environmentObject(vm)
            }
            .sheet(isPresented: $showMassAdd) {
                MassRecipeAddView { parsed in
                    vm.editingRecipe = parsed
                    showMassAdd = false
                    showAdd    = true
                }
                .environmentObject(vm)
            }
            .sheet(isPresented: $showSaved) {
                SavedPlansView()
                    .environmentObject(vm)
            }
            .sheet(isPresented: $showRecipes) {
                RecipesListView()
                    .environmentObject(vm)
            }
        }
    }
}

// ────────────────────────────────────────────
// MARK: – Mass Recipe Add & Parser
// ────────────────────────────────────────────

struct MassRecipeAddView: View {
    var onParse: (Recipe) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var raw = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                Text("Paste your recipe:")
                    .font(.headline)
                TextEditor(text: $raw)
                    .border(Color.gray.opacity(0.3))
                    .cornerRadius(8)
                    .frame(height: 200)
                Spacer()
                Button("Parse & Edit") {
                    onParse(parseRecipe(raw))
                }
                .fullWidthStyle()
            }
            .padding()
            .navigationTitle("Mass Recipe Add")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
    
    private func parseRecipe(_ text: String) -> Recipe {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        var idx = 0
        let name = lines[safe: idx] ?? ""; idx += 1
        
        // Ingredients
        var ingredients: [Ingredient] = []
        if lines[safe: idx]?.lowercased().starts(with: "ingredients") == true {
            idx += 1
            while idx < lines.count,
                  !lines[idx].lowercased().starts(with: "instructions") {
                let tokens = lines[idx].split(separator: " ").map(String.init)
                var qty: Double? = nil
                var unit: String?   = nil
                var nameTokens: [String] = []
                for t in tokens {
                    let tok = t.trimmingCharacters(in: .punctuationCharacters)
                    let digits = tok.prefix { "0123456789.".contains($0) }
                    if let q = Double(digits), !digits.isEmpty {
                        qty = q
                        let suf = tok.suffix(from: digits.endIndex)
                        unit = suf.isEmpty ? nil : String(suf)
                    } else {
                        nameTokens.append(t)
                    }
                }
                let ingName = nameTokens.joined(separator: " ")
                ingredients.append(Ingredient(name: ingName, quantity: qty, unit: unit))
                idx += 1
            }
        }
        
        // Instructions
        var instructions: [String] = []
        if lines[safe: idx]?.lowercased().starts(with: "instructions") == true {
            idx += 1
            while idx < lines.count, Double(lines[idx]) == nil {
                instructions.append(lines[idx])
                idx += 1
            }
        }
        
        // Serves
        let serves = Int(lines.last ?? "") ?? 1
        
        return Recipe(
            id: UUID(),
            name: name,
            mealType: .breakfast,
            serves: serves,
            ingredients: ingredients,
            instructions: instructions
        )
    }
}

// ────────────────────────────────────────────
// MARK: – Add/Edit Recipe Form
// ────────────────────────────────────────────

struct AddRecipeView: View {
    @EnvironmentObject var vm: RecipesViewModel
    @Binding var recipe: Recipe?
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String
    @State private var mealType: MealType
    @State private var serves: Int
    @State private var ingredients: [IngredientField]
    @State private var steps: [String]
    
    init(recipe: Binding<Recipe?>) {
        self._recipe = recipe
        let ex = recipe.wrappedValue
        _name        = State(initialValue: ex?.name       ?? "")
        _mealType    = State(initialValue: ex?.mealType   ?? .breakfast)
        _serves      = State(initialValue: ex?.serves     ?? 1)
        _ingredients = State(initialValue:
            ex?.ingredients.map(IngredientField.init)
            ?? Array(repeating: IngredientField(), count: 3)
        )
        _steps       = State(initialValue:
            ex?.instructions ?? Array(repeating: "", count: 3)
        )
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Recipe Info") {
                    TextField("Name", text: $name)
                    Picker("Meal Type", selection: $mealType) {
                        ForEach(MealType.allCases, id: \.self) {
                            Text($0.rawValue)
                        }
                    }
                    Stepper("Serves: \(serves)", value: $serves, in: 1...20)
                }
                Section("Ingredients") {
                    ForEach(ingredients.indices, id: \.self) { i in
                        IngredientRow(field: $ingredients[i])
                    }
                    Button("Add Ingredient") {
                        ingredients.append(IngredientField())
                    }
                }
                Section("Steps") {
                    ForEach(steps.indices, id: \.self) { i in
                        TextField("Step \(i+1)", text: $steps[i])
                    }
                    Button("Add Step") {
                        steps.append("")
                    }
                }
            }
            .navigationTitle(recipe == nil ? "New Recipe" : "Edit Recipe")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let rec = Recipe(
                            id: recipe?.id ?? UUID(),
                            name: name,
                            mealType: mealType,
                            serves: serves,
                            ingredients: ingredients.map(\.toIngredient),
                            instructions: steps
                        )
                        vm.addOrUpdate(recipe: rec)
                        dismiss()
                    }
                }
            }
        }
    }
}

fileprivate struct IngredientField {
    var name: String = ""
    var quantity: Double? = nil
    var unit: String? = nil
    
    init() {}
    init(from ing: Ingredient) {
        name     = ing.name
        quantity = ing.quantity
        unit     = ing.unit
    }
    var toIngredient: Ingredient {
        Ingredient(name: name, quantity: quantity, unit: unit)
    }
}

fileprivate struct IngredientRow: View {
    @Binding var field: IngredientField
    var body: some View {
        HStack {
            TextField("Name", text: $field.name)
            TextField("Qty", value: $field.quantity, formatter: NumberFormatter())
                .frame(width: 50)
                .keyboardType(.decimalPad)
            TextField("Unit", text: $field.unit.bound)
                .frame(width: 60)
        }
    }
}

// ────────────────────────────────────────────
// MARK: – Saved Plans List
// ────────────────────────────────────────────

struct SavedPlansView: View {
    @EnvironmentObject var vm: RecipesViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                ForEach(vm.savedMealPlans) { plan in
                    NavigationLink(plan.name) {
                        PlanTabsView(
                            weeklyPlan: plan.plan,
                            servings: plan.servings,
                            days: vm.days,
                            title: plan.name,
                            showSave: false
                        )
                        .environmentObject(vm)
                    }
                }
            }
            .navigationTitle("Saved Meal Plans")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// ────────────────────────────────────────────
// MARK: – Recipes List & Delete/Edit
// ────────────────────────────────────────────

struct RecipesListView: View {
    @EnvironmentObject var vm: RecipesViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showEdit = false
    @State private var alertMsg = ""
    @State private var showAlert = false
    
    var body: some View {
        NavigationView {
            List {
                ForEach(MealType.allCases, id: \.self) { meal in
                    Section(header: Text(meal.rawValue)) {
                        let list = vm.recipesByType[meal] ?? []
                        ForEach(list) { recipe in
                            Button {
                                vm.editingRecipe = recipe
                                showEdit = true
                            } label: {
                                HStack {
                                    Text(recipe.name)
                                    Spacer()
                                    Text("\(recipe.serves) servings")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .onDelete { idxSet in
                            let list = vm.recipesByType[meal] ?? []
                            if list.count <= 1 {
                                alertMsg = "Cannot delete the last recipe in \(meal.rawValue)."
                                showAlert = true
                            } else {
                                idxSet.forEach { i in
                                    let rec = list[i]
                                    vm.delete(recipe: rec)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("All Recipes")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
            }
            .sheet(isPresented: $showEdit) {
                AddRecipeView(recipe: $vm.editingRecipe)
                    .environmentObject(vm)
            }
            .alert(alertMsg, isPresented: $showAlert) {
                Button("OK", role: .cancel) {}
            }
        }
    }
}

// ────────────────────────────────────────────
// MARK: – Save Plan Sheet
// ────────────────────────────────────────────

struct SavePlanView: View {
    @EnvironmentObject var vm: RecipesViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    
    init(defaultName: String) {
        _name = State(initialValue: defaultName)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Plan Name", text: $name)
                }
            }
            .navigationTitle("Save Plan")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        vm.saveCurrentPlan(named: name)
                        dismiss()
                    }
                }
            }
        }
    }
}

// ────────────────────────────────────────────
// MARK: – PlanTabsView & DayCardView
// ────────────────────────────────────────────

struct PlanTabsView: View {
    let weeklyPlan: [MealType:[Recipe]]
    let servings: Int
    let days: [String]
    let title: String
    let showSave: Bool
    
    @EnvironmentObject var vm: RecipesViewModel
    @State private var showSaveSheet = false
    
    private var shopping: [Ingredient:Double] {
        var dict: [Ingredient:Double] = [:]
        for dayMeals in weeklyPlan.values {
            for r in dayMeals {
                let batches = Double(servings)/Double(r.serves)
                for ing in r.ingredients {
                    let qty = (ing.quantity ?? 1)*batches
                    dict[ing, default: 0] += qty
                }
            }
        }
        return dict
    }
    
    var body: some View {
        TabView {
            menuTab
              .tabItem { Label("Menu", systemImage: "list.bullet") }
            
            ingredientsTab
              .tabItem { Label("Ingredients", systemImage: "cart") }
        }
        .navigationTitle(title)
        .sheet(isPresented: $showSaveSheet) {
            SavePlanView(defaultName: vm.defaultPlanName())
                .environmentObject(vm)
        }
    }
    
    @ViewBuilder
    private var menuTab: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(days.indices, id: \.self) { i in
                    DayCardView(
                        dayName: days[i],
                        recipes: Dictionary(
                            uniqueKeysWithValues: MealType.allCases.compactMap {
                                m in
                                weeklyPlan[m]?[safe: i].map { (m,$0) }
                            }
                        )
                    )
                }
                if showSave {
                    Button("Save Plan") {
                        showSaveSheet = true
                    }
                    .fullWidthStyle()
                    .padding(.top, 16)
                }
            }
            .padding()
        }
    }
    
    @ViewBuilder
    private var ingredientsTab: some View {
        List {
            Section(header: Text("Ingredients for \(servings) servings each")) {
                ForEach(
                    shopping.sorted(by: { $0.key.name < $1.key.name }),
                    id: \.key
                ) { entry in
                    let ing = entry.key, tot = entry.value
                    if ing.quantity != nil {
                        Text("\(ing.name): \(String(format: "%.2f", tot)) \(ing.unit ?? "")")
                    } else {
                        Text(ing.name)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

/// A card view that shows Breakfast, Lunch, Dinner for a single day
struct DayCardView: View {
    let dayName: String
    let recipes: [MealType:Recipe]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(dayName)
                .font(.title2).bold()
            ForEach(MealType.allCases, id: \.self) { m in
                if let r = recipes[m] {
                    HStack {
                        Text(m.rawValue).fontWeight(.semibold)
                        Spacer()
                        Text(r.name).foregroundColor(.secondary)
                    }
                    .padding(.vertical, 6)
                    Divider()
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}
