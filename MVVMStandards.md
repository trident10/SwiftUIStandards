# SwiftUI MVVM Team Guidelines

## Core Principles

1. **ViewModels** handle business logic and state management
2. **Views** only handle UI rendering and user interactions
3. **Models** are simple data structures without business logic
4. **One ViewModel per View** - avoid sharing ViewModels between unrelated views

## ViewModel Standards

### Basic ViewModel Structure

```swift
@MainActor
final class ProductListViewModel: ObservableObject {
    // MARK: - Published State
    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?
    
    // MARK: - Dependencies
    private let productService: ProductServiceProtocol
    private let analytics: AnalyticsProtocol
    
    // MARK: - Init
    init(
        productService: ProductServiceProtocol,
        analytics: AnalyticsProtocol = Analytics.shared
    ) {
        self.productService = productService
        self.analytics = analytics
    }
    
    // MARK: - Public Methods
    func loadProducts() async {
        isLoading = true
        error = nil
        
        do {
            products = try await productService.fetchProducts()
            analytics.track(.productsLoaded(count: products.count))
        } catch {
            self.error = error
            analytics.track(.error(error))
        }
        
        isLoading = false
    }
    
    func deleteProduct(_ product: Product) async {
        do {
            try await productService.delete(product.id)
            products.removeAll { $0.id == product.id }
        } catch {
            self.error = error
        }
    }
}
```

## ViewModel Initialization Patterns

### 1. Direct Initialization in View

```swift
struct ProductListView: View {
    @StateObject private var viewModel = ProductListViewModel(
        productService: ProductService()
    )
    
    var body: some View {
        // View implementation
    }
}
```

### 2. Factory Initialization (Recommended)

```swift
struct ProductListView: View {
    @StateObject private var viewModel: ProductListViewModel
    
    init(productService: ProductServiceProtocol = ProductService()) {
        self._viewModel = StateObject(
            wrappedValue: ProductListViewModel(productService: productService)
        )
    }
    
    var body: some View {
        // View implementation
    }
}
```

### 3. Parent View Initialization

```swift
// Parent View
struct MainView: View {
    private let productService = ProductService()
    
    var body: some View {
        NavigationStack {
            ProductListView(productService: productService)
        }
    }
}

// Child View receives dependencies
struct ProductListView: View {
    @StateObject private var viewModel: ProductListViewModel
    
    init(productService: ProductServiceProtocol) {
        self._viewModel = StateObject(
            wrappedValue: ProductListViewModel(productService: productService)
        )
    }
}
```

### 4. Coordinator Pattern

```swift
@MainActor
final class AppCoordinator: ObservableObject {
    private let container: DependencyContainer
    
    init(container: DependencyContainer) {
        self.container = container
    }
    
    @ViewBuilder
    func makeProductListView() -> some View {
        ProductListView(
            productService: container.productService,
            onProductSelected: { [weak self] product in
                self?.showProductDetail(product)
            }
        )
    }
    
    private func showProductDetail(_ product: Product) {
        // Navigation logic
    }
}
```

## UIKit to SwiftUI Bridge

### Starting SwiftUI from UIKit

```swift
// UIKit ViewController
class ProductsViewController: UIViewController {
    
    @IBAction func showSwiftUIView() {
        let productService = ProductService()
        let swiftUIView = ProductListView(productService: productService)
        let hostingController = UIHostingController(rootView: swiftUIView)
        
        // Present modally
        present(hostingController, animated: true)
        
        // Or push to navigation
        navigationController?.pushViewController(hostingController, animated: true)
    }
}

// For complex scenarios with coordinator
class MainViewController: UIViewController {
    private let coordinator = AppCoordinator(container: .shared)
    
    @IBAction func showProducts() {
        let productListView = coordinator.makeProductListView()
            .environmentObject(coordinator)
        
        let hostingController = UIHostingController(rootView: productListView)
        navigationController?.pushViewController(hostingController, animated: true)
    }
}
```

### Sharing ViewModels with UIKit

```swift
// Shared ViewModel
@MainActor
final class SharedProductViewModel: ObservableObject {
    @Published private(set) var products: [Product] = []
    
    // For UIKit compatibility
    var productsPublisher: AnyPublisher<[Product], Never> {
        $products.eraseToAnyPublisher()
    }
}

// UIKit Usage
class UIKitViewController: UIViewController {
    private let viewModel = SharedProductViewModel(productService: ProductService())
    private var cancellables = Set<AnyCancellable>()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        viewModel.productsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] products in
                self?.updateUI(with: products)
            }
            .store(in: &cancellables)
    }
}
```

## ❌ Things to AVOID in ViewModels

### 1. **Never Import SwiftUI in ViewModels**
```swift
// ❌ WRONG
import SwiftUI

final class BadViewModel: ObservableObject {
    @Published var color: Color = .blue  // SwiftUI type
}

// ✅ CORRECT
final class GoodViewModel: ObservableObject {
    @Published var colorHex: String = "#0000FF"  // Use primitive types
}
```

### 2. **Never Access Views from ViewModels**
```swift
// ❌ WRONG
final class BadViewModel: ObservableObject {
    weak var view: ProductListView?  // Never reference views
    
    func showAlert() {
        view?.showAlert()  // ViewModel shouldn't know about UI
    }
}

// ✅ CORRECT
final class GoodViewModel: ObservableObject {
    @Published var alertMessage: String?  // View observes and shows alert
}
```

### 3. **Avoid Creating ViewModels Inside ViewModels**
```swift
// ❌ WRONG
final class ParentViewModel: ObservableObject {
    func makeChildViewModel() -> ChildViewModel {
        ChildViewModel()  // Don't create child ViewModels
    }
}

// ✅ CORRECT - Use Coordinator or Factory
final class Coordinator: ObservableObject {
    func makeChildViewModel() -> ChildViewModel {
        ChildViewModel(service: container.service)
    }
}
```

### 4. **Don't Expose Mutable Collections Directly**
```swift
// ❌ WRONG
final class BadViewModel: ObservableObject {
    @Published var items: [Item] = []  // Publicly mutable
}

// ✅ CORRECT
final class GoodViewModel: ObservableObject {
    @Published private(set) var items: [Item] = []  // Read-only
    
    func addItem(_ item: Item) {
        items.append(item)
    }
}
```

### 5. **Avoid Combine Subjects for Input (Use Methods Instead)**
```swift
// ❌ WRONG - Overly complex
final class BadViewModel: ObservableObject {
    let tapSubject = PassthroughSubject<Void, Never>()
    
    init() {
        tapSubject.sink { _ in 
            // Handle tap
        }
    }
}

// ✅ CORRECT - Simple and clear
final class GoodViewModel: ObservableObject {
    func handleTap() {
        // Handle tap directly
    }
}
```

### 6. **Don't Mix Business Logic in Views**
```swift
// ❌ WRONG
struct BadView: View {
    var body: some View {
        Button("Save") {
            // Complex business logic in view
            if validateData() && checkPermissions() {
                saveToDatabase()
            }
        }
    }
}

// ✅ CORRECT
struct GoodView: View {
    @StateObject private var viewModel: ViewModel
    
    var body: some View {
        Button("Save") {
            Task {
                await viewModel.save()  // Delegate to ViewModel
            }
        }
    }
}
```

### 7. **Avoid Massive ViewModels**
```swift
// ❌ WRONG - One ViewModel doing everything
final class MassiveViewModel: ObservableObject {
    // 500+ lines handling multiple features
}

// ✅ CORRECT - Split responsibilities
final class ProductListViewModel: ObservableObject { }
final class ProductFilterViewModel: ObservableObject { }
final class ProductSearchViewModel: ObservableObject { }
```

### 8. **Don't Forget @MainActor**
```swift
// ❌ WRONG - Can cause crashes
final class BadViewModel: ObservableObject {
    @Published var text = ""  // UI updates from background thread
    
    func update() {
        DispatchQueue.global().async {
            self.text = "Updated"  // Crash!
        }
    }
}

// ✅ CORRECT
@MainActor
final class GoodViewModel: ObservableObject {
    @Published var text = ""
    
    func update() async {
        text = "Updated"  // Safe on MainActor
    }
}
```

## Quick Reference

### ViewModel Checklist
- [ ] Marked with `@MainActor`
- [ ] Conforms to `ObservableObject`
- [ ] All dependencies injected via init
- [ ] Published properties are `private(set)`
- [ ] No SwiftUI imports
- [ ] Methods are focused and testable
- [ ] Error handling is comprehensive

### View Checklist
- [ ] Uses `@StateObject` for owned ViewModels
- [ ] Uses `@ObservedObject` for passed ViewModels
- [ ] No business logic in view body
- [ ] Delegates all actions to ViewModel
- [ ] Properly handles loading and error states
