# SwiftUI MVVM Enterprise Development Standards

## Table of Contents
1. [Architecture Principles](#architecture-principles)
2. [MVVM Implementation](#mvvm-implementation)
3. [ViewModel Initialization Standards](#viewmodel-initialization-standards)
4. [SwiftUI Best Practices](#swiftui-best-practices)
5. [Code Style & Conventions](#code-style--conventions)
6. [Dependency Management](#dependency-management)
7. [Testing Standards](#testing-standards)
8. [Performance Guidelines](#performance-guidelines)
9. [Documentation Requirements](#documentation-requirements)

## Architecture Principles

### Core Tenets
- **Separation of Concerns**: Strict boundaries between View, ViewModel, and Model layers
- **Testability First**: All business logic must be independently testable
- **Protocol-Oriented Design**: Use protocols for abstraction and dependency injection
- **Immutability**: Prefer value types and immutable state where possible

### Layer Responsibilities

#### ❌ Avoid This
```swift
struct UserProfileView: View {
    @State private var user: User?
    
    var body: some View {
        VStack {
            Text(user?.name ?? "")
            Button("Load User") {
                // Business logic in View
                Task {
                    let url = URL(string: "https://api.example.com/user")!
                    let (data, _) = try await URLSession.shared.data(from: url)
                    self.user = try JSONDecoder().decode(User.self, from: data)
                }
            }
        }
    }
}
```

#### ✅ Do This
```swift
// View: Only UI and bindings
struct UserProfileView: View {
    @StateObject private var viewModel = UserProfileViewModel()
    
    var body: some View {
        VStack {
            Text(viewModel.userName)
            Button("Load User") {
                Task { await viewModel.loadUser() }
            }
        }
    }
}

// ViewModel: Business logic
@MainActor
final class UserProfileViewModel: ObservableObject {
    @Published private(set) var userName = ""
    private let userService: UserServiceProtocol
    
    init(userService: UserServiceProtocol = UserService()) {
        self.userService = userService
    }
    
    func loadUser() async {
        do {
            let user = try await userService.fetchUser()
            userName = user.name
        } catch {
            userName = "Error loading user"
        }
    }
}
```

## MVVM Implementation

### ViewModel Standards

#### ❌ Avoid This
```swift
// Don't import SwiftUI in ViewModels
import SwiftUI

class ProfileViewModel: ObservableObject {
    @Published var textColor = Color.red // SwiftUI dependency
    @Published var isShowing = false
    
    func toggleView() {
        withAnimation { // SwiftUI animation
            isShowing.toggle()
        }
    }
}
```

#### ✅ Do This
```swift
// No SwiftUI imports in ViewModel
import Foundation

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published private(set) var user: User?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    
    private let userRepository: UserRepositoryProtocol
    
    init(userRepository: UserRepositoryProtocol) {
        self.userRepository = userRepository
    }
    
    func loadUserProfile() async {
        isLoading = true
        errorMessage = nil
        
        do {
            user = try await userRepository.fetchCurrentUser()
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
}
```

### View Implementation

#### ❌ Avoid This
```swift
struct ProductListView: View {
    let products: [Product]
    @State private var filteredProducts: [Product] = []
    @State private var searchText = ""
    
    var body: some View {
        List(filteredProducts) { product in
            Text(product.name)
        }
        .onAppear {
            // Filtering logic in View
            filteredProducts = products.filter { 
                searchText.isEmpty || $0.name.contains(searchText) 
            }
        }
    }
}
```

#### ✅ Do This
```swift
struct ProductListView: View {
    @StateObject private var viewModel: ProductListViewModel
    
    init(viewModel: @autoclosure @escaping () -> ProductListViewModel) {
        self._viewModel = StateObject(wrappedValue: viewModel())
    }
    
    var body: some View {
        List(viewModel.filteredProducts) { product in
            ProductRowView(product: product)
        }
        .searchable(text: $viewModel.searchText)
        .task {
            await viewModel.loadProducts()
        }
    }
}

@MainActor
final class ProductListViewModel: ObservableObject {
    @Published var searchText = ""
    @Published private(set) var products: [Product] = []
    
    var filteredProducts: [Product] {
        guard !searchText.isEmpty else { return products }
        return products.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    func loadProducts() async {
        // Load products from repository
    }
}
```

## ViewModel Initialization Standards

### Dependency Injection

#### ❌ Avoid This
```swift
// Hard-coded dependencies
class CartViewModel: ObservableObject {
    private let service = CartService() // Tight coupling
    private let analytics = AnalyticsManager.shared // Singleton
}

// Creating ViewModels in View
struct CartView: View {
    @StateObject private var viewModel = CartViewModel() // No DI
}
```

#### ✅ Do This
```swift
// Protocol-based dependencies
@MainActor
final class CartViewModel: ObservableObject {
    private let cartService: CartServiceProtocol
    private let analyticsService: AnalyticsServiceProtocol
    
    init(
        cartService: CartServiceProtocol,
        analyticsService: AnalyticsServiceProtocol
    ) {
        self.cartService = cartService
        self.analyticsService = analyticsService
    }
}

// Factory pattern for ViewModel creation
enum ViewModelFactory {
    static func makeCartViewModel() -> CartViewModel {
        CartViewModel(
            cartService: DIContainer.shared.resolve(CartServiceProtocol.self),
            analyticsService: DIContainer.shared.resolve(AnalyticsServiceProtocol.self)
        )
    }
}

// View initialization
struct CartView: View {
    @StateObject private var viewModel: CartViewModel
    
    init() {
        self._viewModel = StateObject(wrappedValue: ViewModelFactory.makeCartViewModel())
    }
}
```

### Environment-Based Initialization

#### ❌ Avoid This
```swift
// Passing ViewModels through multiple view layers
struct AppView: View {
    @StateObject private var userViewModel = UserViewModel()
    
    var body: some View {
        HomeView(userViewModel: userViewModel) // Prop drilling
    }
}
```

#### ✅ Do This
```swift
// Environment object for shared state
struct AppView: View {
    @StateObject private var appState = AppState()
    
    var body: some View {
        HomeView()
            .environmentObject(appState)
    }
}

// ViewModels access shared state
@MainActor
final class UserViewModel: ObservableObject {
    @Published private(set) var currentUser: User?
    private let appState: AppState
    
    init(appState: AppState) {
        self.appState = appState
        self.currentUser = appState.currentUser
    }
}
```

## SwiftUI Best Practices

### View Composition

#### ❌ Avoid This
```swift
struct DashboardView: View {
    var body: some View {
        ScrollView {
            VStack {
                // Massive view body
                HStack {
                    Image(systemName: "person")
                    Text("Profile")
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                
                HStack {
                    Image(systemName: "gear")
                    Text("Settings")
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                
                // ... 200 more lines
            }
        }
    }
}
```

#### ✅ Do This
```swift
struct DashboardView: View {
    var body: some View {
        ScrollView {
            VStack {
                MenuRowView(icon: "person", title: "Profile")
                MenuRowView(icon: "gear", title: "Settings")
            }
        }
    }
}

private struct MenuRowView: View {
    let icon: String
    let title: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
            Text(title)
            Spacer()
            Image(systemName: "chevron.right")
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}
```

### State Management

#### ❌ Avoid This
```swift
struct FormView: View {
    @State var name = ""  // Missing private
    @State var email = "" // Mutable from outside
    @State private var items = [Item]() // Complex state in View
    
    var body: some View {
        Form {
            TextField("Name", text: $name)
            TextField("Email", text: $email)
        }
    }
}
```

#### ✅ Do This
```swift
struct FormView: View {
    @StateObject private var viewModel = FormViewModel()
    
    var body: some View {
        Form {
            TextField("Name", text: $viewModel.name)
            TextField("Email", text: $viewModel.email)
        }
    }
}

// Complex state in ViewModel
@MainActor
final class FormViewModel: ObservableObject {
    @Published var name = ""
    @Published var email = ""
    @Published private(set) var items = [Item]()
}
```

### Performance Optimization

#### ❌ Avoid This
```swift
struct ItemListView: View {
    let items: [Item]
    
    var body: some View {
        ScrollView {
            VStack {
                ForEach(items, id: \.name) { item in // Using unstable ID
                    ItemRow(item: item)
                }
            }
        }
    }
}

struct ExpensiveView: View {
    let data: Data
    
    var body: some View {
        // Recomputes on every parent update
        VStack {
            ForEach(0..<1000) { i in
                Text("Row \(i)")
            }
        }
    }
}
```

#### ✅ Do This
```swift
struct ItemListView: View {
    let items: [Item]
    
    var body: some View {
        ScrollView {
            LazyVStack { // Lazy loading
                ForEach(items) { item in // Items must be Identifiable
                    ItemRow(item: item)
                }
            }
        }
    }
}

struct ExpensiveView: View, Equatable {
    let data: Data
    
    var body: some View {
        LazyVStack {
            ForEach(0..<1000) { i in
                Text("Row \(i)")
            }
        }
    }
    
    static func == (lhs: ExpensiveView, rhs: ExpensiveView) -> Bool {
        lhs.data == rhs.data // Prevent unnecessary redraws
    }
}
```

## Code Style & Conventions

### Property Organization

#### ❌ Avoid This
```swift
struct MessyView: View {
    var body: some View { Text("Hello") }
    @State private var isShowing = false
    let title: String
    @Environment(\.dismiss) var dismiss
    @StateObject var viewModel = ViewModel()
}
```

#### ✅ Do This
```swift
struct OrganizedView: View {
    // MARK: - Environment
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - State Properties  
    @State private var isShowing = false
    
    // MARK: - Observable Properties
    @StateObject private var viewModel = ViewModel()
    
    // MARK: - Properties
    let title: String
    
    // MARK: - Body
    var body: some View {
        Text(title)
    }
}
```

## Dependency Management

### Service Registration

#### ❌ Avoid This
```swift
// Scattered initialization
class NetworkManager {
    static let shared = NetworkManager()
}

class DataManager {
    let network = NetworkManager.shared // Direct dependency
}
```

#### ✅ Do This
```swift
// Centralized DI Container
protocol NetworkServiceProtocol {
    func fetch<T: Decodable>(_ type: T.Type, from url: URL) async throws -> T
}

final class DIContainer {
    static let shared = DIContainer()
    private var services = [ObjectIdentifier: Any]()
    
    func register<T>(_ type: T.Type, service: T) {
        services[ObjectIdentifier(type)] = service
    }
    
    func resolve<T>(_ type: T.Type) -> T {
        guard let service = services[ObjectIdentifier(type)] as? T else {
            fatalError("\(type) not registered")
        }
        return service
    }
}

// App setup
@main
struct MyApp: App {
    init() {
        setupDependencies()
    }
    
    private func setupDependencies() {
        DIContainer.shared.register(NetworkServiceProtocol.self, 
                                   service: NetworkService())
    }
}
```

## Testing Standards

### ViewModel Testing

#### ❌ Avoid This
```swift
// Testing implementation details
func testViewModel() {
    let viewModel = UserViewModel()
    
    // Testing private properties directly
    XCTAssertEqual(viewModel.privateProperty, "value")
    
    // No async handling
    viewModel.loadData()
    XCTAssertEqual(viewModel.users.count, 3) // Race condition
}
```

#### ✅ Do This
```swift
@MainActor
final class UserViewModelTests: XCTestCase {
    private var sut: UserViewModel!
    private var mockService: MockUserService!
    
    override func setUp() {
        super.setUp()
        mockService = MockUserService()
        sut = UserViewModel(userService: mockService)
    }
    
    func testLoadUsersSuccess() async {
        // Given
        let expectedUsers = [User.mock()]
        mockService.stubbedUsers = expectedUsers
        
        // When
        await sut.loadUsers()
        
        // Then
        XCTAssertEqual(sut.users, expectedUsers)
        XCTAssertFalse(sut.isLoading)
        XCTAssertNil(sut.errorMessage)
    }
}
```

## Performance Guidelines

### Memory Management

#### ❌ Avoid This
```swift
class ViewModel: ObservableObject {
    init() {
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            self.update() // Retain cycle
        }
    }
}
```

#### ✅ Do This
```swift
@MainActor
final class ViewModel: ObservableObject {
    private var timer: Timer?
    
    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.update()
        }
    }
    
    deinit {
        timer?.invalidate()
    }
}
```

## Documentation Requirements

### Code Documentation

#### ❌ Avoid This
```swift
// Loads data
func loadData() { }

// User
struct User {
    var n: String // name
    var e: String // email
}
```

#### ✅ Do This
```swift
/// Fetches user profile data from the remote server
/// - Note: Requires active internet connection
/// - Important: Automatically retries failed requests up to 3 times
func loadUserProfile() async throws {
    // Implementation
}

/// Represents a user account in the system
struct User {
    /// User's full display name
    let displayName: String
    
    /// User's primary email address
    let email: String
    
    /// Date when the account was created
    let createdAt: Date
}
