//
//  ContentView.swift
//  FoodPlanner
//

import SwiftUI
import Combine

// MARK: – Models

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
    let plan: [MealType:[Recipe?]]
    let servings: Int
}

// MARK: – ViewModel

final class RecipesViewModel: ObservableObject {
    // persisted
    @Published var customRecipes: [Recipe] = []
    @Published var removedRecipeIDs: Set<UUID> = []
    @Published var savedMealPlans: [SavedMealPlan] = []
    // UI state
    @Published var editingRecipe: Recipe? = nil
    @Published var weeklyPlan: [MealType:[Recipe?]] = [:]
    @Published var currentServings: Int = 1

    let days = ["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"]

    private let builtIn: [MealType:[Recipe]] = [
        .breakfast: [
            Recipe(id: UUID(), name: "Oatmeal", mealType: .breakfast, serves: 1,
                   ingredients:[
                     Ingredient(name:"Rolled oats", quantity:0.5, unit:"cup"),
                     Ingredient(name:"Milk",        quantity:1,   unit:"cup"),
                     Ingredient(name:"Honey",       quantity:1,   unit:"tbsp")
                   ],
                   instructions:[
                     "Combine oats and milk in pot.",
                     "Cook on medium heat until thick.",
                     "Stir in honey and serve."
                   ])
        ],
        .lunch: [
            Recipe(id: UUID(), name: "Grilled Chicken Salad", mealType: .lunch, serves: 1,
                   ingredients:[
                     Ingredient(name:"Chicken breast", quantity:1, unit:"pc"),
                     Ingredient(name:"Lettuce",        quantity:2, unit:"cups"),
                     Ingredient(name:"Tomato",         quantity:1, unit:"pc")
                   ],
                   instructions:[
                     "Grill chicken and slice.",
                     "Toss with lettuce and tomato.",
                     "Dress with olive oil and vinegar."
                   ])
        ],
        .dinner: [
            Recipe(id: UUID(), name: "Chicken Soup", mealType: .dinner, serves: 5,
                   ingredients:[
                     Ingredient(name:"Onion",         quantity:1,   unit:"large"),
                     Ingredient(name:"Potato",        quantity:1,   unit:"kg"),
                     Ingredient(name:"Carrots",       quantity:0.7, unit:"kg"),
                     Ingredient(name:"Chicken",       quantity:1,   unit:"kg"),
                     Ingredient(name:"Bay leaf",      quantity:nil, unit:nil),
                     Ingredient(name:"Salt + pepper", quantity:nil, unit:nil)
                   ],
                   instructions:[
                     "Skin potato, onion, carrot",
                     "Dice onion",
                     "Cut potato into pieces that are digestible",
                     "Cut carrots thin",
                     "Put chicken in pot, cover with water plus 2/3 finger",
                     "Bring to boil, add ingredients, simmer 40 min until soft"
                   ])
        ]
    ]

    var recipesByType: [MealType:[Recipe]] {
        var dict = builtIn
        for m in MealType.allCases {
            dict[m] = (dict[m] ?? []).filter { !removedRecipeIDs.contains($0.id) }
        }
        MealType.allCases.forEach { dict[$0] = dict[$0] ?? [] }
        for r in customRecipes {
            dict[r.mealType]?.append(r)
        }
        return dict
    }

    // MARK: – Plan Generation & Mutation

    func generatePlan(forServings s: Int) {
        currentServings = s
        var newPlan = [MealType:[Recipe?]]()
        for m in MealType.allCases {
            let list = recipesByType[m]!
            guard !list.isEmpty else {
                newPlan[m] = Array(repeating: nil, count: days.count)
                continue
            }
            let shuffled = list.shuffled()
            newPlan[m] = (0..<days.count).map { shuffled[$0 % shuffled.count] }
        }
        weeklyPlan = newPlan
    }

    func removeSlot(meal: MealType, dayIndex: Int) {
        weeklyPlan[meal]?[dayIndex] = nil
    }

    // MARK: – Recipe CRUD

    func addOrUpdate(recipe: Recipe) {
        if let i = customRecipes.firstIndex(where:{ $0.id == recipe.id }) {
            customRecipes[i] = recipe
        } else {
            customRecipes.append(recipe)
        }
        saveRecipes()
    }

    func delete(recipe: Recipe) {
        let list = recipesByType[recipe.mealType]!
        guard list.count > 1 else { return }
        if customRecipes.contains(where:{ $0.id == recipe.id }) {
            customRecipes.removeAll { $0.id == recipe.id }
            saveRecipes()
        } else {
            removedRecipeIDs.insert(recipe.id)
            saveRemoved()
        }
    }

    // MARK: – Save & Delete Plans

    func saveCurrentPlan(named name: String) {
        let mon = monday(of: Date())
        let plan = SavedMealPlan(
            id: UUID(),
            name: name,
            date: mon,
            plan: weeklyPlan,
            servings: currentServings
        )
        savedMealPlans.append(plan)
        savePlans()
    }

    func removeSavedPlans(at offsets: IndexSet) {
        savedMealPlans.remove(atOffsets: offsets)
        savePlans()
    }

    func defaultPlanName() -> String {
        let mon = monday(of: Date())
        let df = DateFormatter(); df.dateFormat = "MMMM d"
        return "Week of \(df.string(from: mon)) meal plan"
    }

    // MARK: – Persistence

    private var recipesURL: URL {
        FileManager.default
            .urls(for:.documentDirectory,in:.userDomainMask)[0]
            .appendingPathComponent("custom_recipes.json")
    }
    private var removedURL: URL {
        FileManager.default
            .urls(for:.documentDirectory,in:.userDomainMask)[0]
            .appendingPathComponent("removed_ids.json")
    }
    private var plansURL: URL {
        FileManager.default
            .urls(for:.documentDirectory,in:.userDomainMask)[0]
            .appendingPathComponent("saved_plans.json")
    }

    init() {
        loadRecipes(); loadRemoved(); loadPlans()
    }

    private func saveRecipes() {
        guard let d = try? JSONEncoder().encode(customRecipes) else { return }
        try? d.write(to: recipesURL)
    }
    private func loadRecipes() {
        guard let d = try? Data(contentsOf: recipesURL),
              let arr = try? JSONDecoder().decode([Recipe].self, from: d)
        else { return }
        customRecipes = arr
    }

    private func saveRemoved() {
        guard let d = try? JSONEncoder().encode(Array(removedRecipeIDs)) else { return }
        try? d.write(to: removedURL)
    }
    private func loadRemoved() {
        guard let d = try? Data(contentsOf: removedURL),
              let arr = try? JSONDecoder().decode([UUID].self, from: d)
        else { return }
        removedRecipeIDs = Set(arr)
    }

    private func savePlans() {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        guard let d = try? enc.encode(savedMealPlans) else { return }
        try? d.write(to: plansURL)
    }
    private func loadPlans() {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        guard let d = try? Data(contentsOf: plansURL),
              let arr = try? dec.decode([SavedMealPlan].self, from: d)
        else { return }
        savedMealPlans = arr
    }

    private func monday(of date: Date) -> Date {
        var cal = Calendar.current; cal.firstWeekday = 2
        let comps = cal.dateComponents([.yearForWeekOfYear,.weekOfYear],from:date)
        return cal.date(from:comps)!
    }
}

// MARK: – Helpers & Styles

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
        self.font(.headline)
            .frame(maxWidth:.infinity, minHeight:44)
            .background(
                LinearGradient(gradient: .init(colors:[.blue,.purple]),
                               startPoint:.leading,endPoint:.trailing)
            )
            .foregroundColor(.white)
            .cornerRadius(10)
            .shadow(color:.black.opacity(0.2),radius:4,x:0,y:2)
    }
}

// MARK: – App Entry

@main
struct MealPlannerApp: App {
    @StateObject private var vm = RecipesViewModel()
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(vm)
        }
    }
}

// MARK: – ContentView (Home Screen)

struct ContentView: View {
    @EnvironmentObject var vm: RecipesViewModel

    @State private var servings    = 1
    @State private var showPlan    = false
    @State private var showAdd     = false
    @State private var showMass    = false
    @State private var showSaved   = false
    @State private var showRecipes = false

    var body: some View {
        NavigationView {
            VStack(spacing:16) {
                Stepper("Servings: \(servings)", value:$servings, in:1...20)
                    .padding(.horizontal)

                Button("Generate Weekly Plan") {
                    vm.generatePlan(forServings: servings)
                    showPlan = true
                }.fullWidthStyle()

                Button("Add Recipe") {
                    vm.editingRecipe = nil; showAdd = true
                }.fullWidthStyle()

                Button("Mass Recipe Add") {
                    showMass = true
                }.fullWidthStyle()

                Button("View Saved Plans") {
                    showSaved = true
                }.fullWidthStyle()

                Button("View Recipes") {
                    showRecipes = true
                }.fullWidthStyle()

                Spacer()
            }
            .padding()
            .navigationTitle("Weekly Meal Planner")
            .background(
                NavigationLink(
                    destination: PlanTabsView(
                        weeklyPlan: vm.weeklyPlan,
                        servings: vm.currentServings,
                        days: vm.days,
                        title: "This Week’s Plan",
                        showSave: true
                    ).environmentObject(vm),
                    isActive: $showPlan
                ){ EmptyView() }
                .hidden()
            )
            .sheet(isPresented: $showAdd) {
                AddRecipeView(recipe: $vm.editingRecipe)
                    .environmentObject(vm)
            }
            .sheet(isPresented: $showMass) {
                MassRecipeAddView { rec in
                    vm.editingRecipe = rec
                    showMass = false
                    showAdd  = true
                }.environmentObject(vm)
            }
            .sheet(isPresented: $showSaved) {
                SavedPlansView().environmentObject(vm)
            }
            .sheet(isPresented: $showRecipes) {
                RecipesListView().environmentObject(vm)
            }
        }
    }
}

// MARK: – MassRecipeAddView

struct MassRecipeAddView: View {
    var onParse: (Recipe) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var raw = ""

    var body: some View {
        NavigationView {
            VStack(spacing:16) {
                Text("Paste your recipe:")
                    .font(.headline)
                TextEditor(text: $raw)
                    .border(Color.gray.opacity(0.3))
                    .cornerRadius(8)
                    .frame(height: 200)
                Spacer()
                Button("Parse & Edit") {
                    onParse(parseRecipe(raw))
                }.fullWidthStyle()
            }
            .padding()
            .navigationTitle("Mass Recipe Add")
            .toolbar {
                ToolbarItem(placement:.cancellationAction) {
                    Button("Cancel"){ dismiss() }
                }
            }
        }
    }

    private func parseRecipe(_ text: String) -> Recipe {
        let lines = text.split(whereSeparator:\.isNewline).map(String.init)
        var idx = 0
        let name = lines[safe: idx] ?? ""; idx += 1

        var ingredients: [Ingredient] = []
        if lines[safe: idx]?.lowercased().starts(with:"ingredients") == true {
            idx += 1
            while idx < lines.count,
                  !lines[idx].lowercased().starts(with:"instructions") {
                let tokens = lines[idx].split(separator:" ").map(String.init)
                var qty: Double? = nil
                var unit: String? = nil
                var nameTokens: [String] = []
                for t in tokens {
                    let tok = t.trimmingCharacters(in:.punctuationCharacters)
                    let digs = tok.prefix { "0123456789.".contains($0) }
                    if let q = Double(digs), !digs.isEmpty {
                        qty = q
                        let suf = tok.suffix(from:digs.endIndex)
                        unit = suf.isEmpty ? nil : String(suf)
                    } else {
                        nameTokens.append(t)
                    }
                }
                let ingName = nameTokens.joined(separator:" ")
                ingredients.append(Ingredient(name:ingName, quantity:qty, unit:unit))
                idx += 1
            }
        }

        var instructions: [String] = []
        if lines[safe: idx]?.lowercased().starts(with:"instructions") == true {
            idx += 1
            while idx < lines.count, Double(lines[idx]) == nil {
                instructions.append(lines[idx]); idx += 1
            }
        }

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

// MARK: – AddRecipeView

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
        _name        = State(initialValue: ex?.name     ?? "")
        _mealType    = State(initialValue: ex?.mealType ?? .breakfast)
        _serves      = State(initialValue: ex?.serves   ?? 1)
        _ingredients = State(initialValue:
            ex?.ingredients.map(IngredientField.init)
            ?? Array(repeating: IngredientField(), count:3)
        )
        _steps       = State(initialValue:
            ex?.instructions ?? Array(repeating:"", count:3)
        )
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Recipe Info") {
                    TextField("Name", text:$name)
                    Picker("Meal Type", selection:$mealType) {
                        ForEach(MealType.allCases, id:\.self) {
                            Text($0.rawValue)
                        }
                    }
                    Stepper("Serves: \(serves)", value:$serves, in:1...20)
                }
                Section("Ingredients") {
                    ForEach(ingredients.indices, id:\.self) { i in
                        IngredientRow(field:$ingredients[i])
                    }
                    Button("Add Ingredient") {
                        ingredients.append(IngredientField())
                    }
                }
                Section("Steps") {
                    ForEach(steps.indices, id:\.self) { i in
                        TextField("Step \(i+1)", text:$steps[i])
                    }
                    Button("Add Step") {
                        steps.append("")
                    }
                }
            }
            .navigationTitle(recipe == nil ? "New Recipe" : "Edit Recipe")
            .toolbar {
                ToolbarItem(placement:.cancellationAction) {
                    Button("Cancel"){ dismiss() }
                }
                ToolbarItem(placement:.confirmationAction) {
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

    struct IngredientField {
        var name: String = ""
        var quantity: Double? = nil
        var unit: String?     = nil

        init() {}
        init(from ing:Ingredient) {
            name     = ing.name
            quantity = ing.quantity
            unit     = ing.unit
        }
        var toIngredient: Ingredient {
            Ingredient(name:name, quantity:quantity, unit:unit)
        }
    }

    struct IngredientRow: View {
        @Binding var field: IngredientField
        var body: some View {
            HStack {
                TextField("Name", text:$field.name)
                TextField("Qty", value:$field.quantity,
                          formatter:NumberFormatter())
                    .frame(width:50).keyboardType(.decimalPad)
                TextField("Unit", text:$field.unit.bound)
                    .frame(width:60)
            }
        }
    }
}

// MARK: – SavedPlansView

struct SavedPlansView: View {
    @EnvironmentObject var vm: RecipesViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                ForEach(vm.savedMealPlans) { plan in
                    NavigationLink(plan.name) {
                        PlanTabsView(
                            weeklyPlan:plan.plan,
                            servings:plan.servings,
                            days:vm.days,
                            title:plan.name,
                            showSave:false
                        ).environmentObject(vm)
                    }
                }
                .onDelete(perform: vm.removeSavedPlans)
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Saved Meal Plans")
            .toolbar {
                ToolbarItem(placement:.cancellationAction) {
                    Button("Done"){ dismiss() }
                }
                ToolbarItem(placement:.navigationBarTrailing) {
                    EditButton()
                }
            }
        }
    }
}

// MARK: – RecipesListView

struct RecipesListView: View {
    @EnvironmentObject var vm: RecipesViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showEdit = false
    @State private var alertMsg = ""
    @State private var showAlert = false

    var body: some View {
        NavigationView {
            List {
                ForEach(MealType.allCases, id:\.self) { meal in
                    Section(header: Text(meal.rawValue)) {
                        let list = vm.recipesByType[meal]!
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
                            let list = vm.recipesByType[meal]!
                            if list.count <= 1 {
                                alertMsg = "Cannot delete the last recipe in \(meal.rawValue)."
                                showAlert = true
                            } else {
                                idxSet.forEach { vm.delete(recipe: list[$0]) }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("All Recipes")
            .toolbar {
                ToolbarItem(placement:.cancellationAction) {
                    Button("Done"){ dismiss() }
                }
                ToolbarItem(placement:.navigationBarTrailing) {
                    EditButton()
                }
            }
            .sheet(isPresented: $showEdit) {
                AddRecipeView(recipe:$vm.editingRecipe)
                    .environmentObject(vm)
            }
            .alert(alertMsg, isPresented:$showAlert) {
                Button("OK", role:.cancel){}
            }
        }
    }
}

// MARK: – SavePlanView

struct SavePlanView: View {
    @EnvironmentObject var vm: RecipesViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var name: String

    init(defaultName:String) {
        _name = State(initialValue:defaultName)
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Plan Name", text:$name)
                }
            }
            .navigationTitle("Save Plan")
            .toolbar {
                ToolbarItem(placement:.cancellationAction) {
                    Button("Cancel"){ dismiss() }
                }
                ToolbarItem(placement:.confirmationAction) {
                    Button("Save") {
                        vm.saveCurrentPlan(named: name)
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: – PlanSlot (Identifiable)

struct PlanSlot: Identifiable {
    let id = UUID()
    let meal: MealType
    let dayIndex: Int
}

// MARK: – PlanTabsView

struct PlanTabsView: View {
    @EnvironmentObject var vm: RecipesViewModel

    let weeklyPlan: [MealType:[Recipe?]]
    let servings: Int
    let days: [String]
    let title: String
    let showSave: Bool

    @State private var editingSlot: PlanSlot? = nil
    @State private var showSaveSheet = false

    private var shopping: [Ingredient:Double] {
        var dict = [Ingredient:Double]()
        for meals in weeklyPlan.values {
            for rOpt in meals {
                guard let r = rOpt else { continue }
                let factor = Double(servings)/Double(r.serves)
                for ing in r.ingredients {
                    dict[ing, default:0] += (ing.quantity ?? 1)*factor
                }
            }
        }
        return dict
    }

    var body: some View {
        TabView {
            // MARK: – Menu Tab
            ScrollView {
                VStack(spacing:16) {
                    ForEach(days.indices, id:\.self) { i in
                        VStack(alignment:.leading,spacing:8) {
                            Text(days[i])
                                .font(.title2).bold()
                            ForEach(MealType.allCases, id:\.self) { m in
                                HStack {
                                    if let r = weeklyPlan[m]?[i] {
                                        Text(r.name)
                                            .foregroundColor(.primary)
                                    } else {
                                        Text("–")
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Menu {
                                        Button("Change…") {
                                            editingSlot = PlanSlot(meal:m, dayIndex:i)
                                        }
                                        Button("Remove", role:.destructive) {
                                            vm.removeSlot(meal:m, dayIndex:i)
                                        }
                                    } label: {
                                        Image(systemName:"ellipsis.circle")
                                            .font(.title3)
                                    }
                                }
                                .padding(.vertical,6)
                                Divider()
                            }
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(10)
                        .shadow(color:.black.opacity(0.1),radius:4,x:0,y:2)
                    }
                    if showSave {
                        Button("Save Plan") {
                            showSaveSheet = true
                        }
                        .fullWidthStyle()
                        .padding(.top,16)
                    }
                }
                .padding()
            }
            .tabItem {
                Label("Menu", systemImage:"list.bullet")
            }

            // MARK: – Ingredients Tab
            List {
                Section(header: Text("Ingredients for \(servings) servings")) {
                    ForEach(shopping.sorted(by:{ $0.key.name < $1.key.name }), id:\.key) { ing, tot in
                        if ing.quantity != nil {
                            Text("\(ing.name): \(String(format:"%.2f", tot)) \(ing.unit ?? "")")
                        } else {
                            Text(ing.name)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .tabItem {
                Label("Ingredients", systemImage:"cart")
            }
        }
        .navigationTitle(title)
        .sheet(item:$editingSlot) { slot in
            EditSlotView(meal:slot.meal, dayIndex:slot.dayIndex)
                .environmentObject(vm)
        }
        .sheet(isPresented:$showSaveSheet) {
            SavePlanView(defaultName: vm.defaultPlanName())
                .environmentObject(vm)
        }
    }
}

// MARK: – EditSlotView

struct EditSlotView: View {
    @EnvironmentObject var vm: RecipesViewModel
    let meal: MealType
    let dayIndex: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                ForEach(MealType.allCases, id:\.self) { category in
                    Section(header: Text(category.rawValue)) {
                        ForEach(vm.recipesByType[category]!) { rec in
                            Button(rec.name) {
                                vm.weeklyPlan[meal]?[dayIndex] = rec
                                dismiss()
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Choose Recipe")
            .toolbar {
                ToolbarItem(placement:.cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
