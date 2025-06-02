# ViewModel Initialization Standards for MVVM in SwiftUI

## StateObject Initialization Pattern

### a. From Coordinator

```swift
// Coordinator
final class AppCoordinator: ObservableObject {
    private let dependencies: AppDependencies
    
    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
    }
    
    @ViewBuilder
    func makeProductDetailView(productId: String) -> some View {
        ProductDetailView(
            viewModel: ProductDetailViewModel(
                productId: productId,
                repository: dependencies.productRepository,
                analytics: dependencies.analytics
            )
        )
    }
}

// View
struct ProductDetailView: View {
    @StateObject private var viewModel: ProductDetailViewModel
    
    init(viewModel: ProductDetailViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    var body: some View {
        // View implementation
    }
}
```

### b. ParentView Initializing ChildView

```swift
// Parent View
struct OrderView: View {
    @StateObject private var orderViewModel: OrderViewModel
    private let dependencies: AppDependencies
    
    init(orderId: String, dependencies: AppDependencies) {
        self.dependencies = dependencies
        _orderViewModel = StateObject(wrappedValue: 
            OrderViewModel(
                orderId: orderId,
                repository: dependencies.orderRepository
            )
        )
    }
    
    var body: some View {
        List(orderViewModel.items) { item in
            // Pass dependencies to child view
            OrderItemView(
                item: item,
                dependencies: dependencies
            )
        }
    }
}

// Child View
struct OrderItemView: View {
    @StateObject private var viewModel: OrderItemViewModel
    
    init(item: OrderItem, dependencies: AppDependencies) {
        _viewModel = StateObject(wrappedValue:
            OrderItemViewModel(
                item: item,
                cartService: dependencies.cartService
            )
        )
    }
}
```

### c. Factory Pattern with StateObject

```swift
// ViewModel Factory
final class ViewModelFactory {
    private let dependencies: AppDependencies
    
    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
    }
    
    func makeUserProfileViewModel(userId: String) -> UserProfileViewModel {
        UserProfileViewModel(
            userId: userId,
            repository: dependencies.userRepository,
            imageLoader: dependencies.imageLoader
        )
    }
}

// View with Factory
struct UserProfileView: View {
    @StateObject private var viewModel: UserProfileViewModel
    
    init(userId: String, factory: ViewModelFactory) {
        _viewModel = StateObject(wrappedValue: 
            factory.makeUserProfileViewModel(userId: userId)
        )
    }
}
```

### d. Environment-Based Injection

```swift
// Environment Key
struct ViewModelFactoryKey: EnvironmentKey {
    static let defaultValue = ViewModelFactory(dependencies: .shared)
}

extension EnvironmentValues {
    var viewModelFactory: ViewModelFactory {
        get { self[ViewModelFactoryKey.self] }
        set { self[ViewModelFactoryKey.self] = newValue }
    }
}

// Root View Setup
@main
struct MyApp: App {
    let factory = ViewModelFactory(dependencies: AppDependencies())
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.viewModelFactory, factory)
        }
    }
}

// Using Environment in Child Views
struct ProductListView: View {
    @Environment(\.viewModelFactory) private var factory
    @StateObject private var viewModel: ProductListViewModel
    
    init() {
        // Workaround for accessing environment in init
        let tempFactory = ViewModelFactory(dependencies: .shared)
        _viewModel = StateObject(wrappedValue: 
            tempFactory.makeProductListViewModel()
        )
    }
}
```

### e. Closure-Based Initialization

```swift
// For dynamic ViewModel creation
struct SearchResultsView: View {
    @StateObject private var viewModel: SearchResultsViewModel
    
    init(
        query: String,
        makeViewModel: (String) -> SearchResultsViewModel
    ) {
        _viewModel = StateObject(wrappedValue: makeViewModel(query))
    }
}

// Usage
SearchResultsView(query: searchText) { query in
    SearchResultsViewModel(
        query: query,
        searchService: dependencies.searchService
    )
}
```

## Key Rules

1. **Always use `_viewModel = StateObject(wrappedValue:)`** in View init
2. **Never create StateObject directly in body** - causes recreation
3. **Pass dependencies through init**, not through property access
4. **For iOS 17+**, consider using `@State` with `@Observable` macro instead
5. **Test ViewModels separately** from Views by extracting initialization logic
