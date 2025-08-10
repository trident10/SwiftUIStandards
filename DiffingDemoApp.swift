import SwiftUI
import Combine

// MARK: - App Entry Point
@main
struct DiffingDemoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// MARK: - Main Navigation
struct ContentView: View {
    var body: some View {
        NavigationView {
            List {
                Section("Performance Issues") {
                    NavigationLink("1. Closure Breaking Diffing", 
                                 destination: ClosureDiffingDemo())
                    NavigationLink("2. Reference Type Issues", 
                                 destination: ReferenceTypeDiffingDemo())
                    NavigationLink("3. Non-Equatable Structs", 
                                 destination: NonEquatableStructDemo())
                    NavigationLink("4. Computed Properties Problem", 
                                 destination: ComputedPropertiesDemo())
                }
                
                Section("Solutions") {
                    NavigationLink("5. Custom Equatable Solution", 
                                 destination: CustomEquatableDemo())
                    NavigationLink("6. View Decomposition", 
                                 destination: ViewDecompositionDemo())
                    NavigationLink("7. Real-World Example", 
                                 destination: RealWorldExampleDemo())
                }
                
                Section("Analysis Tools") {
                    NavigationLink("8. Performance Profiler", 
                                 destination: PerformanceProfilerDemo())
                }
            }
            .navigationTitle("SwiftUI Diffing Demo")
        }
    }
}

// MARK: - Debug Renderer System

/// Core debug renderer that visualizes re-renders with color changes
struct DebugRenderer: ViewModifier {
    let label: String
    let showStats: Bool
    
    @State private var renderCount = 0
    @State private var lastRenderTime = Date()
    @State private var randomColor = Color.random
    @State private var renderTimes: [TimeInterval] = []
    
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(randomColor.opacity(0.3))
                    .animation(.easeInOut(duration: 0.3), value: randomColor)
            )
            .overlay(alignment: .topTrailing) {
                if showStats {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Renders: \(renderCount)")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(4)
                        
                        if let avgTime = averageRenderTime {
                            Text("\(String(format: "%.1f", avgTime))ms")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange)
                                .foregroundColor(.white)
                                .cornerRadius(4)
                        }
                    }
                    .padding(4)
                }
            }
            .onAppear {
                updateRenderStats()
                print("🎨 [\(label)] Initial render")
            }
            .onChange(of: randomColor) { _ in
                updateRenderStats()
                let elapsed = Date().timeIntervalSince(lastRenderTime) * 1000
                print("🎨 [\(label)] Re-render #\(renderCount) (after \(String(format: "%.1f", elapsed))ms)")
                
                if elapsed < 16 {
                    print("   ⚠️ WARNING: Rendering too frequently for 60fps!")
                }
            }
            .id(UUID()) // Force new identity to trigger color change
    }
    
    private func updateRenderStats() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastRenderTime) * 1000
        
        renderCount += 1
        lastRenderTime = now
        randomColor = .random
        
        if renderCount > 1 {
            renderTimes.append(elapsed)
            if renderTimes.count > 10 {
                renderTimes.removeFirst()
            }
        }
    }
    
    private var averageRenderTime: Double? {
        guard !renderTimes.isEmpty else { return nil }
        return renderTimes.reduce(0, +) / Double(renderTimes.count)
    }
}

extension View {
    func debugRenderer(_ label: String = "View", showStats: Bool = true) -> some View {
        self.modifier(DebugRenderer(label: label, showStats: showStats))
    }
}

extension Color {
    static var random: Color {
        Color(
            red: .random(in: 0...1),
            green: .random(in: 0...1),
            blue: .random(in: 0...1)
        )
    }
}

// MARK: - 1. Closure Breaking Diffing Demo

struct ClosureDiffingDemo: View {
    @State private var parentCounter = 0
    @State private var timer: Timer?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Closure Breaking Diffing")
                    .font(.title2)
                    .bold()
                
                Text("Parent updates: \(parentCounter)")
                    .font(.headline)
                
                VStack(spacing: 16) {
                    Text("❌ BAD: View with closure (always re-renders)")
                        .font(.caption)
                        .foregroundColor(.red)
                    
                    BadViewWithClosure(
                        title: "I have a closure",
                        count: 42,
                        onTap: { print("Tapped") }  // New closure every time!
                    )
                    .debugRenderer("BadView", showStats: true)
                    
                    Divider()
                    
                    Text("✅ GOOD: View without closure (only renders when data changes)")
                        .font(.caption)
                        .foregroundColor(.green)
                    
                    GoodViewWithoutClosure(
                        title: "No closure here",
                        count: 42
                    )
                    .debugRenderer("GoodView", showStats: true)
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
                
                HStack {
                    Button("Update Parent State") {
                        parentCounter += 1
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button(timer == nil ? "Start Auto-Update" : "Stop Auto-Update") {
                        if let timer = timer {
                            timer.invalidate()
                            self.timer = nil
                        } else {
                            self.timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                                parentCounter += 1
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                }
                
                Text("""
                Notice: The bad view flashes on every parent update, even though its data doesn't change.
                The good view only renders once.
                """)
                .font(.caption)
                .padding()
                .background(Color.yellow.opacity(0.2))
                .cornerRadius(8)
            }
            .padding()
        }
        .navigationTitle("Closure Problem")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            timer?.invalidate()
        }
    }
}

struct BadViewWithClosure: View {
    let title: String
    let count: Int
    let onTap: () -> Void
    
    var body: some View {
        VStack {
            Text(title)
            Text("Count: \(count)")
            Button("Tap Me", action: onTap)
        }
        .padding()
        .frame(maxWidth: .infinity)
    }
}

struct GoodViewWithoutClosure: View, Equatable {
    let title: String
    let count: Int
    
    var body: some View {
        VStack {
            Text(title)
            Text("Count: \(count)")
            Button("Tap Me") {
                print("Tapped")
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 2. Reference Type Diffing Demo

class UserSettings {
    var theme: String
    var fontSize: Int
    
    init(theme: String = "dark", fontSize: Int = 14) {
        self.theme = theme
        self.fontSize = fontSize
    }
}

struct ReferenceTypeDiffingDemo: View {
    @State private var settings = UserSettings()
    @State private var updateTrigger = 0
    @State private var recreateSettings = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Reference Type Diffing Issues")
                    .font(.title2)
                    .bold()
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("Current Settings:")
                    Text("Theme: \(settings.theme)")
                    Text("Font Size: \(settings.fontSize)")
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
                
                VStack(spacing: 16) {
                    Text("View with reference type (class)")
                        .font(.caption)
                    
                    ReferenceTypeView(
                        settings: recreateSettings ? UserSettings(theme: settings.theme, 
                                                                  fontSize: settings.fontSize) : settings,
                        updateTrigger: updateTrigger
                    )
                    .debugRenderer("ReferenceView", showStats: true)
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
                
                VStack(spacing: 10) {
                    Button("Modify Same Instance (Won't Trigger Update)") {
                        settings.theme = settings.theme == "dark" ? "light" : "dark"
                        settings.fontSize = Int.random(in: 12...20)
                        updateTrigger += 1
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Toggle("Recreate Instance on Update", isOn: $recreateSettings)
                        .padding(.horizontal)
                    
                    if recreateSettings {
                        Text("⚠️ Now creates new instance - will always re-render")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                
                Text("""
                Reference types are compared by identity (===), not by value.
                Modifying properties of the same instance won't trigger diffing.
                Creating a new instance always triggers re-render, even with same values.
                """)
                .font(.caption)
                .padding()
                .background(Color.yellow.opacity(0.2))
                .cornerRadius(8)
            }
            .padding()
        }
        .navigationTitle("Reference Types")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ReferenceTypeView: View {
    let settings: UserSettings
    let updateTrigger: Int
    
    var body: some View {
        VStack {
            Text("Theme: \(settings.theme)")
            Text("Font Size: \(settings.fontSize)")
            Text("Trigger: \(updateTrigger)")
        }
        .padding()
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 3. Non-Equatable Struct Demo

struct Address {  // Intentionally NOT Equatable
    let street: String
    let city: String
    let zipCode: String
}

struct Product: Equatable {
    let id: String
    let name: String
    let price: Double
}

struct NonEquatableStructDemo: View {
    @State private var address = Address(street: "123 Main St", 
                                        city: "San Francisco", 
                                        zipCode: "94102")
    @State private var product = Product(id: "1", 
                                        name: "iPhone", 
                                        price: 999.99)
    @State private var parentUpdate = 0
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Non-Equatable vs Equatable Structs")
                    .font(.title2)
                    .bold()
                
                Text("Parent updates: \(parentUpdate)")
                
                VStack(spacing: 16) {
                    Text("❌ Non-Equatable Struct (Address)")
                        .font(.caption)
                        .foregroundColor(.red)
                    
                    NonEquatableView(address: address)
                        .debugRenderer("NonEquatable", showStats: true)
                    
                    Divider()
                    
                    Text("✅ Equatable Struct (Product)")
                        .font(.caption)
                        .foregroundColor(.green)
                    
                    EquatableView(product: product)
                        .debugRenderer("Equatable", showStats: true)
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
                
                VStack(spacing: 10) {
                    Button("Update Parent (data unchanged)") {
                        parentUpdate += 1
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button("Change Address") {
                        address = Address(
                            street: "456 Oak Ave",
                            city: "New York",
                            zipCode: "10001"
                        )
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Change Product") {
                        product = Product(
                            id: "2",
                            name: "iPad",
                            price: 799.99
                        )
                    }
                    .buttonStyle(.bordered)
                }
                
                Text("""
                Non-Equatable structs use expensive recursive comparison.
                SwiftUI must check every property, even nested ones.
                Equatable structs use efficient == operator.
                """)
                .font(.caption)
                .padding()
                .background(Color.yellow.opacity(0.2))
                .cornerRadius(8)
            }
            .padding()
        }
        .navigationTitle("Struct Comparison")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct NonEquatableView: View {
    let address: Address
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(address.street)
            Text("\(address.city), \(address.zipCode)")
        }
        .padding()
        .frame(maxWidth: .infinity)
    }
}

struct EquatableView: View {
    let product: Product
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(product.name)
            Text("$\(product.price, specifier: "%.2f")")
        }
        .padding()
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 4. Computed Properties Demo

struct ComputedPropertiesDemo: View {
    @State private var items = (1...5).map { "Item \($0)" }
    @State private var selectedIndex = 0
    @State private var refreshTrigger = 0
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Computed Properties vs Separate Views")
                    .font(.title2)
                    .bold()
                
                Text("Refresh count: \(refreshTrigger)")
                
                VStack(spacing: 16) {
                    Text("❌ BAD: Using Computed Properties")
                        .font(.caption)
                        .foregroundColor(.red)
                    
                    BadComputedPropertyView(
                        items: items,
                        selectedIndex: selectedIndex,
                        refreshTrigger: refreshTrigger
                    )
                    .debugRenderer("BadComputed", showStats: true)
                    
                    Divider()
                    
                    Text("✅ GOOD: Using Separate Views")
                        .font(.caption)
                        .foregroundColor(.green)
                    
                    GoodSeparateViews(
                        items: items,
                        selectedIndex: selectedIndex,
                        refreshTrigger: refreshTrigger
                    )
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
                
                HStack {
                    Button("Trigger Refresh") {
                        refreshTrigger += 1
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button("Change Selection") {
                        selectedIndex = (selectedIndex + 1) % items.count
                    }
                    .buttonStyle(.bordered)
                }
                
                Text("""
                Computed properties are inlined into the parent body.
                Changing any state re-evaluates ALL computed properties.
                Separate views can diff independently.
                """)
                .font(.caption)
                .padding()
                .background(Color.yellow.opacity(0.2))
                .cornerRadius(8)
            }
            .padding()
        }
        .navigationTitle("Computed Properties")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct BadComputedPropertyView: View {
    let items: [String]
    let selectedIndex: Int
    let refreshTrigger: Int
    
    var body: some View {
        VStack {
            headerSection
            listSection
            footerSection
        }
        .padding()
    }
    
    private var headerSection: some View {
        Text("Header (Trigger: \(refreshTrigger))")
            .font(.headline)
            .debugRenderer("Header", showStats: false)
    }
    
    private var listSection: some View {
        VStack {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack {
                    Text(item)
                    if index == selectedIndex {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
        .debugRenderer("List", showStats: false)
    }
    
    private var footerSection: some View {
        Text("Total items: \(items.count)")
            .font(.caption)
            .debugRenderer("Footer", showStats: false)
    }
}

struct GoodSeparateViews: View {
    let items: [String]
    let selectedIndex: Int
    let refreshTrigger: Int
    
    var body: some View {
        VStack {
            HeaderView(refreshTrigger: refreshTrigger)
                .debugRenderer("Header", showStats: false)
            
            ListView(items: items, selectedIndex: selectedIndex)
                .debugRenderer("List", showStats: false)
            
            FooterView(itemCount: items.count)
                .debugRenderer("Footer", showStats: false)
        }
        .padding()
    }
}

struct HeaderView: View, Equatable {
    let refreshTrigger: Int
    
    var body: some View {
        Text("Header (Trigger: \(refreshTrigger))")
            .font(.headline)
    }
}

struct ListView: View, Equatable {
    let items: [String]
    let selectedIndex: Int
    
    var body: some View {
        VStack {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack {
                    Text(item)
                    if index == selectedIndex {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
    }
}

struct FooterView: View, Equatable {
    let itemCount: Int
    
    var body: some View {
        Text("Total items: \(itemCount)")
            .font(.caption)
    }
}

// MARK: - 5. Custom Equatable Solution Demo

struct CustomEquatableDemo: View {
    @State private var userData = UserData(name: "John", age: 30, id: UUID())
    @State private var theme = Theme.light
    @State private var parentUpdate = 0
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Custom Equatable Solution")
                    .font(.title2)
                    .bold()
                
                Text("Parent updates: \(parentUpdate)")
                
                VStack(spacing: 16) {
                    Text("View with Smart Equatable")
                        .font(.caption)
                    
                    SmartEquatableView(
                        userData: userData,
                        theme: theme,
                        onEdit: { print("Edit tapped") },
                        onDelete: { print("Delete tapped") }
                    )
                    .debugRenderer("SmartView", showStats: true)
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
                
                VStack(spacing: 10) {
                    Button("Update Parent (No Data Change)") {
                        parentUpdate += 1
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button("Change User Data") {
                        userData.name = ["Alice", "Bob", "Charlie"].randomElement()!
                        userData.age = Int.random(in: 20...50)
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Toggle Theme") {
                        theme = theme == .light ? .dark : .light
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Change ID (Won't Trigger)") {
                        userData.id = UUID()
                    }
                    .buttonStyle(.bordered)
                }
                
                Text("""
                Custom Equatable lets us:
                - Ignore closures (onEdit, onDelete)
                - Ignore non-rendering properties (id)
                - Control exactly when view re-renders
                """)
                .font(.caption)
                .padding()
                .background(Color.green.opacity(0.2))
                .cornerRadius(8)
            }
            .padding()
        }
        .navigationTitle("Custom Equatable")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct UserData {
    var name: String
    var age: Int
    var id: UUID  // Tracking ID, doesn't affect rendering
}

enum Theme: Equatable {
    case light, dark
}

struct SmartEquatableView: View, Equatable {
    let userData: UserData
    let theme: Theme
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    // Smart equality: only compare what affects rendering
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.userData.name == rhs.userData.name &&
        lhs.userData.age == rhs.userData.age &&
        lhs.theme == rhs.theme
        // Ignore: id, onEdit, onDelete
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Name: \(userData.name)")
                .foregroundColor(theme == .light ? .black : .white)
            Text("Age: \(userData.age)")
                .foregroundColor(theme == .light ? .black : .white)
            
            HStack {
                Button("Edit", action: onEdit)
                    .buttonStyle(.bordered)
                Button("Delete", action: onDelete)
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(theme == .light ? Color.gray.opacity(0.1) : Color.black.opacity(0.3))
        .cornerRadius(8)
    }
}

// MARK: - 6. View Decomposition Demo

struct ViewDecompositionDemo: View {
    @State private var searchText = ""
    @State private var sortOrder = SortOrder.name
    @State private var showOnlyFavorites = false
    @State private var items = SampleData.items
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("View Decomposition Strategy")
                    .font(.title2)
                    .bold()
                
                // Well-decomposed view hierarchy
                SearchBarView(text: $searchText)
                    .debugRenderer("SearchBar", showStats: true)
                
                FilterControlsView(
                    sortOrder: $sortOrder,
                    showOnlyFavorites: $showOnlyFavorites
                )
                .debugRenderer("Filters", showStats: true)
                
                ItemListView(
                    items: filteredItems,
                    onToggleFavorite: toggleFavorite
                )
                .debugRenderer("ItemList", showStats: true)
                
                Text("""
                Each view component diffs independently.
                Changing search doesn't re-render filters.
                Toggling favorite doesn't re-render search bar.
                """)
                .font(.caption)
                .padding()
                .background(Color.green.opacity(0.2))
                .cornerRadius(8)
            }
            .padding()
        }
        .navigationTitle("View Decomposition")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private var filteredItems: [SampleItem] {
        items
            .filter { item in
                searchText.isEmpty || item.name.localizedCaseInsensitiveContains(searchText)
            }
            .filter { item in
                !showOnlyFavorites || item.isFavorite
            }
            .sorted { lhs, rhs in
                switch sortOrder {
                case .name:
                    return lhs.name < rhs.name
                case .date:
                    return lhs.date > rhs.date
                }
            }
    }
    
    private func toggleFavorite(_ id: UUID) {
        if let index = items.firstIndex(where: { $0.id == id }) {
            items[index].isFavorite.toggle()
        }
    }
}

struct SearchBarView: View, Equatable {
    @Binding var text: String
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.text == rhs.text
    }
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
            TextField("Search items...", text: $text)
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
        .padding(.horizontal)
    }
}

struct FilterControlsView: View, Equatable {
    @Binding var sortOrder: SortOrder
    @Binding var showOnlyFavorites: Bool
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.sortOrder == rhs.sortOrder &&
        lhs.showOnlyFavorites == rhs.showOnlyFavorites
    }
    
    var body: some View {
        VStack {
            Picker("Sort by", selection: $sortOrder) {
                Text("Name").tag(SortOrder.name)
                Text("Date").tag(SortOrder.date)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)
            
            Toggle("Show only favorites", isOn: $showOnlyFavorites)
                .padding(.horizontal)
        }
    }
}

struct ItemListView: View, Equatable {
    let items: [SampleItem]
    let onToggleFavorite: (UUID) -> Void
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.items == rhs.items
    }
    
    var body: some View {
        VStack(spacing: 8) {
            ForEach(items) { item in
                ItemRowView(
                    item: item,
                    onToggleFavorite: { onToggleFavorite(item.id) }
                )
            }
        }
        .padding(.horizontal)
    }
}

struct ItemRowView: View, Equatable {
    let item: SampleItem
    let onToggleFavorite: () -> Void
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.item == rhs.item
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(item.name)
                    .font(.headline)
                Text(item.date, style: .date)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            Button(action: onToggleFavorite) {
                Image(systemName: item.isFavorite ? "star.fill" : "star")
                    .foregroundColor(item.isFavorite ? .yellow : .gray)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }
}

// MARK: - 7. Real-World Example Demo

struct RealWorldExampleDemo: View {
    @StateObject private var viewModel = ProductListViewModel()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Real-World Product List")
                    .font(.title2)
                    .bold()
                
                Text("Optimized for production with all techniques")
                    .font(.caption)
                    .foregroundColor(.gray)
                
                // Search and filters
                ProductSearchBar(text: $viewModel.searchText)
                    .debugRenderer("SearchBar", showStats: true)
                
                ProductFilters(
                    selectedCategory: $viewModel.selectedCategory,
                    priceRange: $viewModel.priceRange
                )
                .debugRenderer("Filters", showStats: true)
                
                // Product grid
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    ForEach(viewModel.filteredProducts) { product in
                        ProductCardOptimized(
                            product: product,
                            isFavorite: viewModel.favorites.contains(product.id),
                            onToggleFavorite: { viewModel.toggleFavorite(product.id) },
                            onAddToCart: { viewModel.addToCart(product.id) }
                        )
                        .debugRenderer("Product-\(product.id)", showStats: false)
                    }
                }
                .padding(.horizontal)
                
                // Performance stats
                PerformanceStatsView(viewModel: viewModel)
                    .debugRenderer("Stats", showStats: true)
            }
            .padding(.vertical)
        }
        .navigationTitle("Real-World Example")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// Optimized product card with all best practices
struct ProductCardOptimized: View, Equatable {
    let product: Product
    let isFavorite: Bool
    let onToggleFavorite: () -> Void
    let onAddToCart: () -> Void
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.product == rhs.product &&
        lhs.isFavorite == rhs.isFavorite
        // Ignore closures - they don't affect rendering
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Product image placeholder
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.2))
                .frame(height: 120)
                .overlay(
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundColor(.gray.opacity(0.5))
                )
            
            Text(product.name)
                .font(.caption)
                .lineLimit(2)
            
            Text("$\(product.price, specifier: "%.2f")")
                .font(.caption)
                .bold()
            
            HStack {
                Button(action: onToggleFavorite) {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .foregroundColor(isFavorite ? .red : .gray)
                        .font(.caption)
                }
                
                Spacer()
                
                Button(action: onAddToCart) {
                    Image(systemName: "cart.badge.plus")
                        .font(.caption)
                }
            }
        }
        .padding(8)
        .background(Color.white)
        .cornerRadius(10)
        .shadow(radius: 2)
    }
}

// MARK: - 8. Performance Profiler Demo

struct PerformanceProfilerDemo: View {
    @State private var isStressTesting = false
    @State private var stressTestItems = 10
    @State private var updateFrequency = 1.0
    @State private var timer: Timer?
    @State private var metrics = PerformanceMetrics()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Performance Profiler")
                    .font(.title2)
                    .bold()
                
                // Controls
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Stress Test Items: \(stressTestItems)")
                        Slider(value: Binding(
                            get: { Double(stressTestItems) },
                            set: { stressTestItems = Int($0) }
                        ), in: 1...50, step: 1)
                    }
                    
                    HStack {
                        Text("Update Frequency: \(String(format: "%.1f", updateFrequency))s")
                        Slider(value: $updateFrequency, in: 0.1...2.0, step: 0.1)
                    }
                    
                    Toggle("Run Stress Test", isOn: $isStressTesting)
                        .onChange(of: isStressTesting) { testing in
                            if testing {
                                startStressTest()
                            } else {
                                stopStressTest()
                            }
                        }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
                
                // Test views
                if isStressTesting {
                    VStack(spacing: 10) {
                        Text("❌ Non-Optimized Views")
                            .font(.caption)
                            .foregroundColor(.red)
                        
                        ForEach(0..<stressTestItems, id: \.self) { index in
                            NonOptimizedTestView(
                                index: index,
                                data: metrics.currentData,
                                onTap: { print("Tapped \(index)") }
                            )
                            .debugRenderer("NonOpt-\(index)", showStats: false)
                        }
                    }
                    .padding()
                    .background(Color.red.opacity(0.05))
                    .cornerRadius(10)
                    
                    VStack(spacing: 10) {
                        Text("✅ Optimized Views")
                            .font(.caption)
                            .foregroundColor(.green)
                        
                        ForEach(0..<stressTestItems, id: \.self) { index in
                            OptimizedTestView(
                                index: index,
                                data: metrics.currentData,
                                onTap: { print("Tapped \(index)") }
                            )
                            .debugRenderer("Opt-\(index)", showStats: false)
                        }
                    }
                    .padding()
                    .background(Color.green.opacity(0.05))
                    .cornerRadius(10)
                }
                
                // Metrics display
                MetricsDisplayView(metrics: metrics)
                
                Text("""
                Compare the render frequency between optimized and non-optimized views.
                Notice how non-optimized views flash constantly during stress test.
                """)
                .font(.caption)
                .padding()
                .background(Color.yellow.opacity(0.2))
                .cornerRadius(8)
            }
            .padding()
        }
        .navigationTitle("Performance Profiler")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            stopStressTest()
        }
    }
    
    private func startStressTest() {
        metrics.reset()
        timer = Timer.scheduledTimer(withTimeInterval: updateFrequency, repeats: true) { _ in
            metrics.update()
        }
    }
    
    private func stopStressTest() {
        timer?.invalidate()
        timer = nil
    }
}

struct NonOptimizedTestView: View {
    let index: Int
    let data: String
    let onTap: () -> Void  // This breaks diffing!
    
    var body: some View {
        HStack {
            Text("Item \(index)")
            Spacer()
            Text(data)
            Button("Tap", action: onTap)
                .font(.caption)
        }
        .padding(8)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(6)
    }
}

struct OptimizedTestView: View, Equatable {
    let index: Int
    let data: String
    let onTap: () -> Void
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.index == rhs.index &&
        lhs.data == rhs.data
        // Ignore onTap closure
    }
    
    var body: some View {
        HStack {
            Text("Item \(index)")
            Spacer()
            Text(data)
            Button("Tap", action: onTap)
                .font(.caption)
        }
        .padding(8)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(6)
    }
}

struct MetricsDisplayView: View {
    let metrics: PerformanceMetrics
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Performance Metrics")
                .font(.headline)
            
            HStack {
                Label("Updates", systemImage: "arrow.clockwise")
                Spacer()
                Text("\(metrics.updateCount)")
            }
            
            HStack {
                Label("Time Elapsed", systemImage: "clock")
                Spacer()
                Text(String(format: "%.1fs", metrics.elapsedTime))
            }
            
            HStack {
                Label("Updates/Second", systemImage: "speedometer")
                Spacer()
                Text(String(format: "%.2f", metrics.updatesPerSecond))
            }
            
            if metrics.updateCount > 0 {
                Text("Current Data: \(metrics.currentData)")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(10)
    }
}

// MARK: - Supporting Models

struct SampleItem: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var date: Date
    var isFavorite: Bool
}

struct SampleData {
    static let items: [SampleItem] = [
        SampleItem(name: "Apple", date: Date().addingTimeInterval(-86400), isFavorite: false),
        SampleItem(name: "Banana", date: Date().addingTimeInterval(-172800), isFavorite: true),
        SampleItem(name: "Cherry", date: Date().addingTimeInterval(-259200), isFavorite: false),
        SampleItem(name: "Date", date: Date().addingTimeInterval(-345600), isFavorite: true),
        SampleItem(name: "Elderberry", date: Date(), isFavorite: false)
    ]
}

enum SortOrder: String, CaseIterable {
    case name = "Name"
    case date = "Date"
}

class ProductListViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var selectedCategory: ProductCategory = .all
    @Published var priceRange: ClosedRange<Double> = 0...1000
    @Published var favorites = Set<String>()
    
    let products: [Product] = [
        Product(id: "1", name: "MacBook Pro", price: 2499.99),
        Product(id: "2", name: "iPhone 15 Pro", price: 999.99),
        Product(id: "3", name: "AirPods Pro", price: 249.99),
        Product(id: "4", name: "iPad Air", price: 599.99),
        Product(id: "5", name: "Apple Watch", price: 399.99),
        Product(id: "6", name: "Mac Mini", price: 699.99)
    ]
    
    var filteredProducts: [Product] {
        products.filter { product in
            (searchText.isEmpty || product.name.localizedCaseInsensitiveContains(searchText)) &&
            (product.price >= priceRange.lowerBound && product.price <= priceRange.upperBound)
        }
    }
    
    func toggleFavorite(_ id: String) {
        if favorites.contains(id) {
            favorites.remove(id)
        } else {
            favorites.insert(id)
        }
    }
    
    func addToCart(_ id: String) {
        print("Added product \(id) to cart")
    }
}

struct ProductSearchBar: View, Equatable {
    @Binding var text: String
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.text == rhs.text
    }
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)
            TextField("Search products...", text: $text)
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
        .padding(.horizontal)
    }
}

struct ProductFilters: View, Equatable {
    @Binding var selectedCategory: ProductCategory
    @Binding var priceRange: ClosedRange<Double>
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.selectedCategory == rhs.selectedCategory &&
        lhs.priceRange == rhs.priceRange
    }
    
    var body: some View {
        VStack(spacing: 12) {
            Picker("Category", selection: $selectedCategory) {
                ForEach(ProductCategory.allCases, id: \.self) { category in
                    Text(category.rawValue).tag(category)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            
            VStack(alignment: .leading) {
                Text("Price: $\(Int(priceRange.lowerBound)) - $\(Int(priceRange.upperBound))")
                    .font(.caption)
                    .foregroundColor(.gray)
                
                HStack {
                    Slider(value: Binding(
                        get: { priceRange.lowerBound },
                        set: { newValue in
                            priceRange = newValue...priceRange.upperBound
                        }
                    ), in: 0...1000, step: 50)
                    
                    Slider(value: Binding(
                        get: { priceRange.upperBound },
                        set: { newValue in
                            priceRange = priceRange.lowerBound...newValue
                        }
                    ), in: 0...3000, step: 50)
                }
            }
        }
        .padding(.horizontal)
    }
}

struct PerformanceStatsView: View {
    @ObservedObject var viewModel: ProductListViewModel
    
    var body: some View {
        HStack(spacing: 20) {
            VStack {
                Text("\(viewModel.filteredProducts.count)")
                    .font(.title3)
                    .bold()
                Text("Products")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            VStack {
                Text("\(viewModel.favorites.count)")
                    .font(.title3)
                    .bold()
                Text("Favorites")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            VStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title3)
                Text("Optimized")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(10)
    }
}

enum ProductCategory: String, CaseIterable {
    case all = "All"
    case computers = "Computers"
    case phones = "Phones"
    case accessories = "Accessories"
}

class PerformanceMetrics: ObservableObject {
    @Published var updateCount = 0
    @Published var startTime = Date()
    @Published var currentData = "Initial"
    
    var elapsedTime: TimeInterval {
        Date().timeIntervalSince(startTime)
    }
    
    var updatesPerSecond: Double {
        guard elapsedTime > 0 else { return 0 }
        return Double(updateCount) / elapsedTime
    }
    
    func reset() {
        updateCount = 0
        startTime = Date()
        currentData = "Initial"
    }
    
    func update() {
        updateCount += 1
        currentData = "Update \(updateCount)"
    }
}
