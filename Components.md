# SwiftUI Component Architecture Standards

## 1. Introduction

This document establishes the official coding standards for developing UI components in SwiftUI across our iOS projects. By implementing these standards, we aim to:

- Ensure consistent, maintainable, and high-quality UI components
- Facilitate code reuse and reduce redundant implementations
- Establish clear patterns for state management and data flow
- Enable faster onboarding of new team members
- Support efficient code reviews by standardizing component architecture

All team members are expected to adhere to these guidelines when developing new components or refactoring existing ones. These standards apply specifically to reusable UI components that may be used across multiple features within our applications.

## 2. Naming Conventions

### General Component Naming

All component names should be clear, descriptive, and follow these conventions:

- Use **PascalCase** for all component types, configs, and view models
- Suffix view components with `View` (e.g., `ButtonView`, `CardView`)
- Suffix configuration structs with `Config` (e.g., `ButtonViewConfig`)
- Suffix view models with `ViewModel` (e.g., `CardViewModel`)
- Use nouns for component names, not adjectives or verbs

### Specific Component Files

For a component named "ProfileCard", the files would be:
- `ProfileCardView.swift` - The SwiftUI view
- `ProfileCardViewConfig.swift` - The configuration struct (separate file for complex components)
- `ProfileCardViewModel.swift` - The view model (for complex components only)

## 3. Folder Structure

Our project structure organizes components in a consistent way:

```
YourApp/
├── Features/
│   ├── Feature1/
│   ├── Feature2/
│   └── ...
├── Components/
│   ├── Simple/
│   │   ├── Badge/
│   │   │   └── BadgeView.swift
│   │   ├── Button/
│   │   │   └── ButtonView.swift
│   │   └── ...
│   └── Complex/
│       ├── ProfileCard/
│       │   ├── ProfileCardView.swift
│       │   ├── ProfileCardViewConfig.swift
│       │   └── ProfileCardViewModel.swift
│       └── ...
└── Core/
    ├── Extensions/
    ├── Utilities/
    └── ...
```

### Rules for Organizing Components

1. Create a dedicated folder for each component under either `/Simple` or `/Complex`
2. Name the folder after the component (without the "View" suffix)
3. Place all component-related files in its dedicated folder
4. For simple components, place both the view and config in a single file
5. For complex components, use separate files for the view, config, and view model

## 4. Component Architecture Patterns

We use two primary patterns for UI components based on their complexity.

### 4.1 Simple Component Pattern

#### When to Use

Use the simple component pattern when:
- The component has minimal or no business logic
- All state can be passed from parent views
- No asynchronous operations are required
- No complex user interaction handling is needed

#### Structure

A simple component consists of:
1. A configuration struct (`ComponentViewConfig`)
2. A view struct (`ComponentView`)

Both are typically located in the same file.

#### Example Implementation: Badge Component

```swift
import SwiftUI

// MARK: - Configuration

struct BadgeViewConfig {
    let count: Int
    let backgroundColor: Color
    let textColor: Color
    
    // Default configuration
    static let `default` = BadgeViewConfig(
        count: 0,
        backgroundColor: .red,
        textColor: .white
    )
}

// MARK: - View

struct BadgeView: View {
    let config: BadgeViewConfig
    
    init(config: BadgeViewConfig = .default) {
        self.config = config
    }
    
    var body: some View {
        ZStack {
            Circle()
                .fill(config.backgroundColor)
            
            if config.count > 0 {
                Text("\(min(config.count, 99))\(config.count > 99 ? "+" : "")")
                    .font(.caption2.bold())
                    .foregroundColor(config.textColor)
                    .padding(2)
            }
        }
        .frame(width: 24, height: 24)
        .accessibilityLabel(Text("\(config.count) notifications"))
    }
}

// MARK: - Preview

struct BadgeView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            BadgeView()
            
            BadgeView(config: BadgeViewConfig(
                count: 5,
                backgroundColor: .blue,
                textColor: .white
            ))
            
            BadgeView(config: BadgeViewConfig(
                count: 100,
                backgroundColor: .green,
                textColor: .black
            ))
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
```

### 4.2 Complex Component Pattern

#### When to Use

Use the complex component pattern when:
- The component requires business logic
- The component manages its own state
- Asynchronous operations are needed (network calls, timers, etc.)
- Complex user interactions must be handled
- Side effects need to be managed

#### Structure

A complex component consists of:
1. A configuration struct (`ComponentViewConfig`) - in a separate file
2. A view model class (`ComponentViewModel`) - in a separate file
3. A view struct (`ComponentView`) - in a separate file

#### Example Implementation: User Profile Component

**ProfileCardViewConfig.swift**:
```swift
import Foundation
import SwiftUI

struct ProfileCardViewConfig {
    let userId: String
    let showActionButtons: Bool
    let onMessageTap: (() -> Void)?
    let onFollowTap: ((Bool) -> Void)?
    
    init(
        userId: String,
        showActionButtons: Bool = true,
        onMessageTap: (() -> Void)? = nil,
        onFollowTap: ((Bool) -> Void)? = nil
    ) {
        self.userId = userId
        self.showActionButtons = showActionButtons
        self.onMessageTap = onMessageTap
        self.onFollowTap = onFollowTap
    }
}
```

**ProfileCardViewModel.swift**:
```swift
import Foundation
import Combine

// User model (would normally be in a separate file)
struct User {
    let id: String
    let name: String
    let profileImage: URL?
    let bio: String
    let followerCount: Int
    let isFollowing: Bool
}

class ProfileCardViewModel: ObservableObject {
    // Published properties (reactive state)
    @Published private(set) var isLoading = false
    @Published private(set) var user: User?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isFollowing = false
    
    // Dependencies and config
    private let config: ProfileCardViewConfig
    private let userService: UserServiceProtocol
    private var cancellables = Set<AnyCancellable>()
    
    init(
        config: ProfileCardViewConfig,
        userService: UserServiceProtocol = UserService()
    ) {
        self.config = config
        self.userService = userService
        loadUserProfile()
    }
    
    func loadUserProfile() {
        isLoading = true
        errorMessage = nil
        
        userService.fetchUser(id: config.userId)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                guard let self = self else { return }
                self.isLoading = false
                
                if case .failure(let error) = completion {
                    self.errorMessage = error.localizedDescription
                }
            } receiveValue: { [weak self] user in
                self?.user = user
                self?.isFollowing = user.isFollowing
            }
            .store(in: &cancellables)
    }
    
    func toggleFollow() {
        guard let user = user else { return }
        
        let newFollowState = !isFollowing
        isFollowing = newFollowState
        
        userService.followUser(id: user.id, isFollowing: newFollowState)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                if case .failure = completion {
                    // Revert on failure
                    self?.isFollowing = !newFollowState
                }
            } receiveValue: { [weak self] success in
                if success {
                    self?.config.onFollowTap?(newFollowState)
                } else {
                    // Revert on failure
                    self?.isFollowing = !newFollowState
                }
            }
            .store(in: &cancellables)
    }
    
    func sendMessage() {
        config.onMessageTap?()
    }
}

// Mock service protocol and implementation (would normally be in separate files)
protocol UserServiceProtocol {
    func fetchUser(id: String) -> AnyPublisher<User, Error>
    func followUser(id: String, isFollowing: Bool) -> AnyPublisher<Bool, Error>
}

class UserService: UserServiceProtocol {
    func fetchUser(id: String) -> AnyPublisher<User, Error> {
        // Simulate network request
        return Future<User, Error> { promise in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                let user = User(
                    id: id,
                    name: "Alex Johnson",
                    profileImage: URL(string: "https://example.com/profile.jpg"),
                    bio: "iOS Developer | SwiftUI Enthusiast",
                    followerCount: 1250,
                    isFollowing: false
                )
                promise(.success(user))
            }
        }
        .eraseToAnyPublisher()
    }
    
    func followUser(id: String, isFollowing: Bool) -> AnyPublisher<Bool, Error> {
        // Simulate network request
        return Future<Bool, Error> { promise in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                promise(.success(true))
            }
        }
        .eraseToAnyPublisher()
    }
}
```

**ProfileCardView.swift**:
```swift
import SwiftUI

struct ProfileCardView: View {
    @StateObject private var viewModel: ProfileCardViewModel
    
    init(config: ProfileCardViewConfig) {
        _viewModel = StateObject(wrappedValue: ProfileCardViewModel(config: config))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.isLoading {
                loadingView
            } else if let errorMessage = viewModel.errorMessage {
                errorView(message: errorMessage)
            } else if let user = viewModel.user {
                userProfileContent(user: user)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
    
    // MARK: - Content Views
    
    private var loadingView: some View {
        HStack {
            Spacer()
            ProgressView()
                .padding()
            Spacer()
        }
    }
    
    private func errorView(message: String) -> some View {
        VStack(spacing: 8) {
            Text("Error loading profile")
                .font(.headline)
                .foregroundColor(.red)
            
            Text(message)
                .font(.caption)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
            
            Button("Retry") {
                viewModel.loadUserProfile()
            }
            .padding(.vertical, 8)
        }
    }
    
    private func userProfileContent(user: User) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Profile header with image and name
            HStack(spacing: 12) {
                profileImage(url: user.profileImage)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(user.name)
                        .font(.headline)
                    
                    Text("\(user.followerCount) followers")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Spacer()
            }
            
            // Bio
            Text(user.bio)
                .font(.subheadline)
                .lineLimit(3)
            
            // Action buttons
            if viewModel.config.showActionButtons {
                HStack(spacing: 12) {
                    Button(action: {
                        viewModel.toggleFollow()
                    }) {
                        Text(viewModel.isFollowing ? "Following" : "Follow")
                            .font(.subheadline.bold())
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .background(viewModel.isFollowing ? Color.gray.opacity(0.2) : Color.blue)
                            .foregroundColor(viewModel.isFollowing ? .primary : .white)
                            .cornerRadius(8)
                    }
                    
                    Button(action: {
                        viewModel.sendMessage()
                    }) {
                        Text("Message")
                            .font(.subheadline.bold())
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .background(Color.gray.opacity(0.1))
                            .foregroundColor(.primary)
                            .cornerRadius(8)
                    }
                }
            }
        }
    }
    
    private func profileImage(url: URL?) -> some View {
        Group {
            if let url = url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        Circle().fill(Color.gray.opacity(0.3))
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        Image(systemName: "person.circle.fill")
                            .resizable()
                            .foregroundColor(.gray)
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .foregroundColor(.gray)
            }
        }
        .frame(width: 60, height: 60)
        .clipShape(Circle())
    }
}

// MARK: - Preview

struct ProfileCardView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            ProfileCardView(config: ProfileCardViewConfig(
                userId: "user123",
                onMessageTap: { print("Message tapped") },
                onFollowTap: { following in print("Follow tapped: \(following)") }
            ))
            .padding()
        }
        .background(Color(.systemGray6))
        .previewLayout(.sizeThatFits)
    }
}
```

## 5. When to Use Each Pattern

| Criteria | Simple Component | Complex Component |
|----------|------------------|-------------------|
| **State Management** | Stateless or minimal state managed by parent | Component manages its own state |
| **Data Requirements** | Data passed through props/configuration | Data fetched or processed internally |
| **User Interaction** | Basic interactions (taps, swipes) | Complex interactions requiring logic |
| **Asynchronous Operations** | None | Network calls, timers, animations |
| **Side Effects** | None | Logging, analytics, persistence |
| **Complexity** | Single responsibility, focused on presentation | Multiple responsibilities, business logic |
| **Reusability** | Highly reusable across contexts | Reusable within specific domains |

## 6. Best Practices

### 6.1 Data Flow

1. **Unidirectional Data Flow**
   - Data flows down through the component hierarchy via configuration objects
   - User actions flow up via callbacks defined in configuration

2. **Explicit Configurations**
   - All component inputs should be explicitly defined in the configuration struct
   - Default values should be provided where appropriate
   - Optional callbacks should use Swift's optional closure type

3. **Minimize Shared State**
   - Prefer passing state through configuration rather than via environment objects
   - When environment objects are necessary, document their usage in comments

### 6.2 State Management

1. **State Location**
   - Simple components: State lives in parent and is passed down
   - Complex components: State lives in the view model
   - LocalState (@State) should only be used for UI-specific state

2. **State Types**
   - Use `@Published` properties in view models to expose observable state
   - Use private setters (`@Published private(set) var`) to prevent external mutation
   - Computed properties should be used for derived state

3. **State Updates**
   - All state updates should occur through explicit methods on the view model
   - State updates should be performed on the main thread
   - Complex state transitions should be handled in the view model, not the view

### 6.3 Separation of Concerns

| Component | Responsibilities | Avoid |
|-----------|------------------|-------|
| **View** | UI layout, presentation, user input handling | Business logic, network requests, complex data transformations |
| **Config** | Input parameters, callback definitions, default values | Mutable state, business logic, side effects |
| **ViewModel** | Business logic, state management, networking, side effects | UI concerns, view-specific logic |

## 7. Anti-Patterns to Avoid

### 7.1 Mixing Business Logic in Views

❌ **Incorrect:**
```swift
struct UserCardView: View {
    let userId: String
    @State private var user: User?
    
    var body: some View {
        VStack {
            // UI elements...
        }
        .onAppear {
            // Don't do network calls directly in views
            UserService.shared.fetchUser(id: userId) { result in
                switch result {
                case .success(let user):
                    self.user = user
                case .failure:
                    // Handle error
                    break
                }
            }
        }
    }
}
```

✅ **Correct:**
Use a view model to handle business logic and network calls.

### 7.2 Massive View Files

❌ **Incorrect:**
```swift
struct MassiveView: View {
    // Dozens of @State properties
    // Many helper methods
    
    var body: some View {
        // Hundreds of lines of UI code
    }
    
    // Logic functions
    // Network calls
    // Data processing
}
```

✅ **Correct:**
Break down into smaller components, extract business logic to view models, and use helper views for UI organization.

### 7.3 Hardcoded Values

❌ **Incorrect:**
```swift
struct PriceTag: View {
    var body: some View {
        Text("$19.99")
            .foregroundColor(.white)
            .padding(8)
            .background(Color.blue)
            .cornerRadius(8)
    }
}
```

✅ **Correct:**
Use configuration to make the component reusable:
```swift
struct PriceTagConfig {
    let price: Double
    let backgroundColor: Color
    let textColor: Color
    
    static let `default` = PriceTagConfig(
        price: 0.0,
        backgroundColor: .blue,
        textColor: .white
    )
}

struct PriceTag: View {
    let config: PriceTagConfig
    
    private var formattedPrice: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        return formatter.string(from: NSNumber(value: config.price)) ?? "$\(config.price)"
    }
    
    var body: some View {
        Text(formattedPrice)
            .foregroundColor(config.textColor)
            .padding(8)
            .background(config.backgroundColor)
            .cornerRadius(8)
    }
}
```

### 7.4 Implicit Dependencies

❌ **Incorrect:**
```swift
struct DashboardView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var userSession: UserSession
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        // UI that depends on multiple implicit dependencies
    }
}
```

✅ **Correct:**
Make dependencies explicit through configuration:
```swift
struct DashboardViewConfig {
    let username: String
    let isDarkMode: Bool
    let primaryColor: Color
    let onSettingsTap: () -> Void
}

struct DashboardView: View {
    let config: DashboardViewConfig
    
    var body: some View {
        // UI with explicit dependencies
    }
}
```

## 8. Conclusion

Following these component architecture standards will ensure that our SwiftUI code remains consistent, maintainable, and scalable as our application grows. The two-pattern approach allows us to choose the right level of complexity for each component while maintaining a consistent structure.

For any questions or clarifications about these standards, please contact the iOS Architecture team. These standards will be reviewed and updated quarterly to incorporate team feedback and evolving best practices in SwiftUI development.
