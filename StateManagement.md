# SwiftUI State Management Best Practices

## Overview

SwiftUI's state management system provides property wrappers to handle different types of data flow and ownership. Choosing the correct property wrapper is crucial for app performance, preventing crashes, and maintaining clean architecture. A well-structured app should prefer single sources of truth, such as ViewState enums, over multiple scattered @Published properties.

### Property Wrapper Quick Reference

| Property Wrapper | Purpose | Ownership |
|-----------------|---------|-----------|
| `@State` | Local view state for value types | View owns |
| `@StateObject` | Observable object lifecycle management | View owns |
| `@ObservedObject` | External observable object reference | External owns |
| `@EnvironmentObject` | Dependency injection across view hierarchy | Environment owns |
| `@Binding` | Two-way data binding | Parent owns |
| `@Published` | Observable property changes | ObservableObject owns |

## Best Practices

### 1. Use @State Only for Value Types

**❌ Bad Example**
```swift
struct ProfileView: View {
    // Never use @State with reference types
    @State private var viewModel = UserViewModel()
    
    var body: some View {
        Text(viewModel.username)
            .onAppear {
                viewModel.loadUser() // ViewModel might be recreated!
            }
    }
}
```

**✅ Good Example**
```swift
struct ProfileView: View {
    // Use @State for simple value types
    @State private var username = ""
    @State private var isEditing = false
    @State private var age = 0
    
    var body: some View {
        VStack {
            TextField("Username", text: $username)
            Toggle("Edit Mode", isOn: $isEditing)
            Stepper("Age: \(age)", value: $age)
        }
    }
}
```

### 2. Choose @StateObject for Owned ObservableObjects

**❌ Bad Example**
```swift
struct TodoListView: View {
    // Creates new instance on every parent update
    @ObservedObject var viewModel = TodoViewModel()
    
    var body: some View {
        List(viewModel.todos) { todo in
            TodoRow(todo: todo)
        }
    }
}
```

**✅ Good Example**
```swift
struct TodoListView: View {
    // Created once and survives view updates
    @StateObject private var viewModel = TodoViewModel()
    
    var body: some View {
        List(viewModel.todos) { todo in
            TodoRow(todo: todo)
        }
        .onAppear {
            viewModel.loadTodos()
        }
    }
}
```

### 3. Pass ObservableObjects with @ObservedObject

**❌ Bad Example**
```swift
struct ParentView: View {
    @StateObject private var sharedModel = DataModel()
    
    var body: some View {
        // Don't create new instances when passing
        ChildView(model: DataModel())
    }
}

struct ChildView: View {
    // Don't use @StateObject for passed objects
    @StateObject var model: DataModel
    
    var body: some View {
        Text(model.title)
    }
}
```

**✅ Good Example**
```swift
struct ParentView: View {
    @StateObject private var sharedModel = DataModel()
    
    var body: some View {
        // Pass the existing instance
        ChildView(model: sharedModel)
    }
}

struct ChildView: View {
    // Use @ObservedObject for passed objects
    @ObservedObject var model: DataModel
    
    var body: some View {
        Text(model.title)
    }
}
```

### 4. Use @EnvironmentObject for Deep Hierarchy Sharing

**❌ Bad Example**
```swift
// Prop drilling through multiple levels
struct Level1View: View {
    let userSession: UserSession
    
    var body: some View {
        Level2View(userSession: userSession)
    }
}

struct Level2View: View {
    let userSession: UserSession
    
    var body: some View {
        Level3View(userSession: userSession)
    }
}

struct Level3View: View {
    let userSession: UserSession
    
    var body: some View {
        Text(userSession.username)
    }
}
```

**✅ Good Example**
```swift
struct AppView: View {
    @StateObject private var userSession = UserSession()
    
    var body: some View {
        ContentView()
            .environmentObject(userSession)
    }
}

// Any descendant can access directly
struct DeepChildView: View {
    @EnvironmentObject var userSession: UserSession
    
    var body: some View {
        Text(userSession.username)
    }
}
```

### 5. Apply @Published to UI-Triggering Properties

**❌ Bad Example**
```swift
class SettingsViewModel: ObservableObject {
    // Forgot @Published - UI won't update
    var isDarkMode = false
    var fontSize = 16.0
    
    // Don't publish computed properties
    @Published var displayText: String {
        return "Size: \(fontSize)"
    }
}
```

**✅ Good Example**
```swift
class SettingsViewModel: ObservableObject {
    // Publish stored properties that affect UI
    @Published var isDarkMode = false
    @Published var fontSize = 16.0
    
    // Computed properties don't need @Published
    var displayText: String {
        return "Size: \(fontSize)"
    }
}
```

### 6. Use @Binding for Parent-Child Communication

**❌ Bad Example**
```swift
struct ToggleView: View {
    // Creating local state instead of binding
    @State private var isOn = false
    let onChange: (Bool) -> Void
    
    var body: some View {
        Toggle("Setting", isOn: $isOn)
            .onChange(of: isOn) { value in
                onChange(value) // Manual syncing
            }
    }
}
```

**✅ Good Example**
```swift
struct ToggleView: View {
    // Direct binding to parent's state
    @Binding var isOn: Bool
    
    var body: some View {
        Toggle("Setting", isOn: $isOn)
    }
}

struct ParentView: View {
    @State private var settingEnabled = false
    
    var body: some View {
        ToggleView(isOn: $settingEnabled)
    }
}
```

### 7. Ensure Thread Safety with @MainActor

**❌ Bad Example**
```swift
class DataViewModel: ObservableObject {
    @Published var items: [Item] = []
    
    func loadData() {
        Task {
            let fetchedItems = try await API.fetchItems()
            items = fetchedItems // Not on main thread!
        }
    }
}
```

**✅ Good Example**
```swift
@MainActor
class DataViewModel: ObservableObject {
    @Published var items: [Item] = []
    
    func loadData() {
        Task {
            do {
                let fetchedItems = try await API.fetchItems()
                items = fetchedItems // Guaranteed main thread
            } catch {
                // Handle error
            }
        }
    }
}
```

### 8. Prevent Memory Leaks in Closures

**❌ Bad Example**
```swift
class TimerViewModel: ObservableObject {
    @Published var count = 0
    private var timer: Timer?
    
    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.count += 1 // Strong reference cycle!
        }
    }
}
```

**✅ Good Example**
```swift
class TimerViewModel: ObservableObject {
    @Published var count = 0
    private var timer: Timer?
    
    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.count += 1
        }
    }
    
    deinit {
        timer?.invalidate()
    }
}
```

### 9. Use ViewState Enum Instead of Multiple @Published Properties

**❌ Bad Example**
```swift
class ProductListViewModel: ObservableObject {
    // Multiple published properties for different states
    @Published var products: [Product] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isEmpty = false
    
    func loadProducts() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let fetchedProducts = try await API.fetchProducts()
                products = fetchedProducts
                isEmpty = fetchedProducts.isEmpty
                isLoading = false
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
}

// View becomes complex with multiple state checks
struct ProductListView: View {
    @StateObject private var viewModel = ProductListViewModel()
    
    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView()
            } else if let error = viewModel.errorMessage {
                ErrorView(message: error)
            } else if viewModel.isEmpty {
                EmptyStateView()
            } else {
                List(viewModel.products) { product in
                    ProductRow(product: product)
                }
            }
        }
    }
}
```

**✅ Good Example**
```swift
class ProductListViewModel: ObservableObject {
    // Single source of truth for view state
    @Published private(set) var viewState: ViewState = .loading
    
    enum ViewState {
        case loading
        case loaded(products: [Product])
        case error(Error)
    }
    
    // Computed property for easy access
    var products: [Product] {
        if case .loaded(let products) = viewState {
            return products
        }
        return []
    }
    
    func loadProducts() {
        viewState = .loading
        
        Task {
            do {
                let fetchedProducts = try await API.fetchProducts()
                viewState = .loaded(products: fetchedProducts)
            } catch {
                viewState = .error(error)
            }
        }
    }
}

// Clean view with declarative modifiers
struct ProductListView: View {
    @StateObject private var viewModel = ProductListViewModel()
    
    var body: some View {
        List(viewModel.products) { product in
            ProductRow(product: product)
        }
        .overlay {
            if viewModel.products.isEmpty, case .loaded = viewModel.viewState {
                EmptyStateView()
            }
        }
        .onAppear {
            viewModel.loadProducts()
        }
        .loading(viewModel.viewState)
        .error(viewModel.viewState) {
            viewModel.loadProducts()
        }
    }
}

// Reusable ViewState modifiers
extension View {
    func loading(_ state: ProductListViewModel.ViewState) -> some View {
        overlay {
            if case .loading = state {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemBackground))
            }
        }
    }
    
    func error(_ state: ProductListViewModel.ViewState, onRetry: @escaping () -> Void) -> some View {
        overlay {
            if case .error(let error) = state {
                ErrorView(error: error, onRetry: onRetry)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemBackground))
            }
        }
    }
}

// Benefits of ViewState Enum Pattern:
// 1. Single source of truth - no conflicting states
// 2. Impossible states prevented - can't be loading AND showing error
// 3. Cleaner view code with declarative modifiers
// 4. Easier testing - mock single viewState instead of multiple properties
// 5. Type-safe state transitions
```

## Things to Avoid

### 1. **Initializing @State in init()**
```swift
// ❌ Never do this
init(value: String) {
    _myState = State(initialValue: value)
}

// ✅ Initialize inline or use onAppear
@State private var myState = ""
```

### 2. **Using Multiple Sources of Truth**
```swift
// ❌ Avoid redundant state
@State private var selectedItem: Item?
@State private var selectedIndex: Int?

// ✅ Single source of truth
@State private var selectedItem: Item?
```

### 3. **Overusing @EnvironmentObject**
```swift
// ❌ Don't inject everything
.environmentObject(networkManager)
.environmentObject(cacheManager)
.environmentObject(analyticsManager)
.environmentObject(locationManager)

// ✅ Only truly shared state
.environmentObject(userSession)
.environmentObject(appTheme)
```

### 4. **Mutating Parent's @StateObject in Child Views**
```swift
// ❌ Don't directly mutate parent's data
Button("Add") {
    parentViewModel.items.append(newItem)
}

// ✅ Use callbacks or methods
Button("Add") {
    parentViewModel.addItem(newItem)
}
```

### 5. **Creating ObservableObject Without @StateObject or @ObservedObject**
```swift
// ❌ This won't trigger updates
let viewModel = MyViewModel()

// ✅ Use proper property wrapper
@StateObject private var viewModel = MyViewModel()
```

### 6. **Using @ObservedObject for Transient Views**
```swift
// ❌ Risky in navigation or sheet presentations
NavigationLink(destination: DetailView(viewModel: DetailViewModel()))

// ✅ Create stable references
@StateObject private var detailViewModel = DetailViewModel()
NavigationLink(destination: DetailView(viewModel: detailViewModel))
```

### 7. **Forgetting to Handle Task Cancellation**
```swift
// ❌ Can cause crashes or incorrect state
Task {
    let data = try await fetchData()
    self.items = data
}

// ✅ Check for cancellation
Task {
    let data = try await fetchData()
    guard !Task.isCancelled else { return }
    self.items = data
}
```

### 8. **Mixing UIKit Patterns with SwiftUI State**
```swift
// ❌ Don't use delegates or notifications for state
NotificationCenter.default.post(name: .dataChanged, object: nil)

// ✅ Use SwiftUI's reactive system
@Published var data: [Item] = []
```

### 9. **Using Multiple @Published Properties for Related State**
```swift
// ❌ Avoid scattered state management
@Published var isLoading = false
@Published var hasError = false
@Published var errorMessage: String?
@Published var data: [Item] = []

// ✅ Use ViewState enum
@Published private(set) var viewState: ViewState = .idle
```
