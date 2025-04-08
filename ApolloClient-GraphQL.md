# Integrating Apollo Client for GraphQL into an iOS Project

## 1. Overview of the Integration Approach

GraphQL offers a more flexible and efficient alternative to traditional REST APIs by allowing clients to request exactly the data they need. The Apollo Client is a powerful GraphQL client for iOS that provides features like caching, error handling, and type safety.

Our integration strategy involves:

- Adding Apollo Client as a dependency to the API Core Kit
- Creating an abstraction layer to decouple the codebase from Apollo's implementation details
- Implementing schema-specific operations in feature API kits
- Updating view models to utilize GraphQL operations
- Maintaining backward compatibility with existing REST endpoints during migration

The high-level architecture will look like this:

```
┌───────────────┐     ┌─────────────────┐     ┌────────────────┐      ┌──────────────┐
│  View Models  │────▶│ Feature API Kit │────▶│  API Core Kit  │─────▶│ GraphQL/REST │
│               │     │                 │     │                │      │    Server    │
└───────────────┘     └─────────────────┘     └────────────────┘      └──────────────┘
```

By implementing a layered approach, we can:
- Gradually migrate from REST to GraphQL
- Shield app code from Apollo implementation details
- Maintain consistent API interfaces for UI components

## 2. Integrating Apollo Client into the API Core Kit

### Adding Dependencies

First, add the Apollo client to your project using Swift Package Manager:

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/apollographql/apollo-ios.git", .upToNextMajor(from: "1.0.0"))
],
targets: [
    .target(
        name: "APICoreKit",
        dependencies: [
            .product(name: "Apollo", package: "apollo-ios")
        ]
    )
]
```

### Creating Abstraction Layer

Start by defining protocol-based abstractions to hide Apollo implementation details:

```swift
// GraphQLOperation.swift
public protocol GraphQLOperation {
    associatedtype Data
    var operationType: GraphQLOperationType { get }
    var operationName: String { get }
    var variables: [String: Any]? { get }
}

public enum GraphQLOperationType {
    case query
    case mutation
    case subscription
}

// GraphQLResult.swift
public struct GraphQLResult<Data> {
    public let data: Data?
    public let errors: [GraphQLError]?
    
    public var hasErrors: Bool {
        return errors?.isEmpty == false
    }
}

// GraphQLError.swift
public struct GraphQLError: Error, Equatable {
    public let message: String
    public let path: [String]?
    public let extensions: [String: Any]?
    
    public init(message: String, path: [String]? = nil, extensions: [String: Any]? = nil) {
        self.message = message
        self.path = path
        self.extensions = extensions
    }
}

// GraphQLClientProtocol.swift
public protocol GraphQLClientProtocol {
    func perform<Operation: GraphQLOperation>(
        operation: Operation
    ) async throws -> GraphQLResult<Operation.Data>
    
    func cancelOperations(withNames: [String])
}
```

### Implementing Apollo Client Wrapper

Implement the Apollo client wrapper that conforms to our abstraction:

```swift
// ApolloGraphQLClient.swift
import Apollo
import ApolloAPI

final class ApolloGraphQLClient: GraphQLClientProtocol {
    private let apolloClient: ApolloClient
    
    init(serverURL: URL, configuration: URLSessionConfiguration = .default) {
        let store = ApolloStore()
        let interceptorProvider = DefaultInterceptorProvider(store: store)
        let networkTransport = RequestChainNetworkTransport(
            interceptorProvider: interceptorProvider,
            endpointURL: serverURL
        )
        
        self.apolloClient = ApolloClient(
            networkTransport: networkTransport,
            store: store
        )
    }
    
    func perform<Operation: GraphQLOperation>(
        operation: Operation
    ) async throws -> GraphQLResult<Operation.Data> {
        let wrappedOperation = try self.wrapOperation(operation)
        
        return try await withCheckedThrowingContinuation { continuation in
            _ = apolloClient.fetch(query: wrappedOperation) { result in
                switch result {
                case .success(let response):
                    // Transform Apollo result to our GraphQLResult
                    let transformedResult = self.transformApolloResult(response, for: operation)
                    continuation.resume(returning: transformedResult)
                    
                case .failure(let error):
                    continuation.resume(throwing: self.transformError(error))
                }
            }
        }
    }
    
    func cancelOperations(withNames names: [String]) {
        apolloClient.store.clearCache()
    }
    
    // Private helper methods
    private func wrapOperation<Operation: GraphQLOperation>(_ operation: Operation) throws -> Apollo.GraphQLQuery {
        // Implementation would convert our operation to Apollo's operation
        // This is simplified for illustration
        fatalError("Implementation would depend on your operation mapping strategy")
    }
    
    private func transformApolloResult<Data>(_ result: Apollo.GraphQLResult<Data>, for operation: Any) -> GraphQLResult<Data> {
        return GraphQLResult(
            data: result.data,
            errors: result.errors?.map { GraphQLError(message: $0.message) }
        )
    }
    
    private func transformError(_ error: Error) -> Error {
        // Transform Apollo errors to our error types
        if let apolloError = error as? Apollo.GraphQLHTTPResponseError,
           let graphQLErrors = apolloError.graphQLErrors {
            return GraphQLError(message: graphQLErrors.map { $0.message }.joined(separator: ", "))
        }
        return error
    }
}
```

### Creating Factory for Client

Add a factory to make it easy to create GraphQL clients:

```swift
// GraphQLClientFactory.swift
public enum GraphQLClientFactory {
    public static func createClient(url: URL) -> GraphQLClientProtocol {
        return ApolloGraphQLClient(serverURL: url)
    }
    
    public static func createAuthenticatedClient(
        url: URL,
        tokenProvider: @escaping () -> String?
    ) -> GraphQLClientProtocol {
        // Create client with authentication interceptor
        // Implementation would add auth headers to requests
        let client = ApolloGraphQLClient(serverURL: url)
        // Add authentication interceptor
        return client
    }
}
```

## 3. Handling GraphQL Schemas in Specific Feature API Kits

### Setup for Schema and Code Generation

First, set up Apollo's code generation tool:

```bash
# Install Apollo CLI
npm install -g apollo

# Create config file
cat > apollo.config.js << EOF
module.exports = {
  client: {
    service: {
      name: 'my-app',
      url: 'https://api.example.com/graphql',
    },
    includes: ['./FeatureAPIKits/**/*.graphql'],
    excludes: ['**/__tests__/**'],
  },
}
EOF

# Download schema
apollo client:download-schema --endpoint=https://api.example.com/graphql schema.graphqls
```

### Organizing GraphQL Files

For each feature, create a dedicated directory for GraphQL files:

```
UserFeatureAPIKit/
  └── GraphQL/
      ├── Operations/
      │   ├── UserQueries.graphql
      │   └── UserMutations.graphql
      └── Generated/
          └── [Apollo generated files]
```

Example query file:

```graphql
# UserFeatureAPIKit/GraphQL/Operations/UserQueries.graphql
query GetUser($id: ID!) {
  user(id: $id) {
    id
    name
    email
    profilePicture
  }
}
```

Run code generation:

```bash
apollo codegen:generate --target=swift --tagName=@available --includes="./UserFeatureAPIKit/GraphQL/Operations/*.graphql" --localSchemaFile=schema.graphqls --output="./UserFeatureAPIKit/GraphQL/Generated"
```

### Feature-Specific Operation Wrappers

Create wrappers for the generated operations:

```swift
// UserOperation.swift
import APICoreKit

struct GetUserOperation: GraphQLOperation {
    typealias Data = GetUserQuery.Data
    
    let id: String
    
    var operationType: GraphQLOperationType { .query }
    var operationName: String { "GetUser" }
    var variables: [String: Any]? { ["id": id] }
}

// UserOperationFactory.swift
public enum UserOperations {
    public static func getUser(id: String) -> some GraphQLOperation {
        return GetUserOperation(id: id)
    }
}
```

### Feature-Specific Services

Implement a service that uses these operations:

```swift
// UserService.swift
import APICoreKit
import Foundation

public protocol UserServiceProtocol {
    func getUser(id: String) async throws -> User
    func updateUser(id: String, name: String, email: String) async throws -> User
}

public struct User: Equatable {
    public let id: String
    public let name: String
    public let email: String
    public let profilePictureURL: URL?
    
    public init(id: String, name: String, email: String, profilePictureURL: URL?) {
        self.id = id
        self.name = name
        self.email = email
        self.profilePictureURL = profilePictureURL
    }
}

public final class UserService: UserServiceProtocol {
    private let graphQLClient: GraphQLClientProtocol
    
    public init(graphQLClient: GraphQLClientProtocol) {
        self.graphQLClient = graphQLClient
    }
    
    public func getUser(id: String) async throws -> User {
        let operation = UserOperations.getUser(id: id)
        let result = try await graphQLClient.perform(operation: operation)
        
        if let errors = result.errors, !errors.isEmpty {
            throw UserServiceError.graphQLError(errors.first?.message ?? "Unknown GraphQL error")
        }
        
        guard let userData = result.data?.user else {
            throw UserServiceError.dataNotFound
        }
        
        return User(
            id: userData.id,
            name: userData.name,
            email: userData.email,
            profilePictureURL: URL(string: userData.profilePicture ?? "")
        )
    }
    
    public func updateUser(id: String, name: String, email: String) async throws -> User {
        // Similar implementation for update mutation
        // ...
    }
}

public enum UserServiceError: Error {
    case graphQLError(String)
    case dataNotFound
    case networkError(Error)
}
```

## 4. Changes to the Main Project and View Models

### Updating View Models

Integrate GraphQL services into your view models:

```swift
// UserProfileViewModel.swift
import Combine
import UserFeatureAPIKit

class UserProfileViewModel: ObservableObject {
    @Published var user: User?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let userService: UserServiceProtocol
    
    init(userService: UserServiceProtocol) {
        self.userService = userService
    }
    
    func fetchUserProfile(id: String) {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let userData = try await userService.getUser(id: id)
                
                await MainActor.run {
                    self.user = userData
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.handleError(error)
                    self.isLoading = false
                }
            }
        }
    }
    
    func updateUserProfile(name: String, email: String) {
        guard let userId = user?.id else { return }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let updatedUser = try await userService.updateUser(id: userId, name: name, email: email)
                
                await MainActor.run {
                    self.user = updatedUser
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.handleError(error)
                    self.isLoading = false
                }
            }
        }
    }
    
    private func handleError(_ error: Error) {
        if let userError = error as? UserServiceError {
            switch userError {
            case .graphQLError(let message):
                errorMessage = "GraphQL error: \(message)"
            case .dataNotFound:
                errorMessage = "User data not found"
            case .networkError(let underlyingError):
                errorMessage = "Network error: \(underlyingError.localizedDescription)"
            }
        } else {
            errorMessage = "An unexpected error occurred: \(error.localizedDescription)"
        }
    }
}
```

### Setup in App Dependency Container

Set up the GraphQL client and services in your dependency container:

```swift
// DependencyContainer.swift
import APICoreKit
import UserFeatureAPIKit

class DependencyContainer {
    let graphQLClient: GraphQLClientProtocol
    
    init(baseURL: URL = URL(string: "https://api.example.com/graphql")!) {
        self.graphQLClient = GraphQLClientFactory.createAuthenticatedClient(
            url: baseURL,
            tokenProvider: { KeychainService.shared.getAccessToken() }
        )
    }
    
    func makeUserService() -> UserServiceProtocol {
        return UserService(graphQLClient: graphQLClient)
    }
    
    func makeUserProfileViewModel() -> UserProfileViewModel {
        return UserProfileViewModel(userService: makeUserService())
    }
}
```

## 5. Maintaining Backwards Compatibility

To ensure smooth migration from REST to GraphQL, implement a hybrid approach:

```swift
// UserServiceHybrid.swift
public final class UserService: UserServiceProtocol {
    private let graphQLClient: GraphQLClientProtocol?
    private let restClient: RESTClientProtocol
    private let featureFlags: FeatureFlagsProtocol
    
    public init(
        graphQLClient: GraphQLClientProtocol?,
        restClient: RESTClientProtocol,
        featureFlags: FeatureFlagsProtocol
    ) {
        self.graphQLClient = graphQLClient
        self.restClient = restClient
        self.featureFlags = featureFlags
    }
    
    public func getUser(id: String) async throws -> User {
        if featureFlags.isEnabled(.useGraphQLForUsers), let graphQLClient = graphQLClient {
            do {
                return try await getUserWithGraphQL(id: id, client: graphQLClient)
            } catch {
                Logger.log("GraphQL user fetch failed: \(error)", level: .error)
                
                if featureFlags.isEnabled(.fallbackToRESTOnGraphQLFailure) {
                    // Fallback to REST API
                    return try await getUserWithREST(id: id)
                }
                throw error
            }
        } else {
            // Use the existing REST implementation
            return try await getUserWithREST(id: id)
        }
    }
    
    private func getUserWithGraphQL(id: String, client: GraphQLClientProtocol) async throws -> User {
        // GraphQL implementation
        let operation = UserOperations.getUser(id: id)
        let result = try await client.perform(operation: operation)
        
        if let errors = result.errors, !errors.isEmpty {
            throw UserServiceError.graphQLError(errors.first?.message ?? "Unknown GraphQL error")
        }
        
        guard let userData = result.data?.user else {
            throw UserServiceError.dataNotFound
        }
        
        return User(
            id: userData.id,
            name: userData.name,
            email: userData.email,
            profilePictureURL: URL(string: userData.profilePicture ?? "")
        )
    }
    
    private func getUserWithREST(id: String) async throws -> User {
        // Existing REST implementation
        let endpoint = UserEndpoint.getUser(id: id)
        let userData = try await restClient.request(endpoint: endpoint)
        return userData
    }
}
```

## 6. Minimizing Apollo Exposure

Keep Apollo dependencies isolated to prevent tight coupling:

### Encapsulation through Protocol Abstractions

All Apollo types should be hidden behind protocols and only used within internal implementations:

```swift
// Only expose these protocols to feature kits
public protocol GraphQLClientProtocol { /* ... */ }
public protocol GraphQLOperation { /* ... */ }
public struct GraphQLResult<Data> { /* ... */ }

// Keep Apollo dependencies internal
internal final class ApolloGraphQLClient: GraphQLClientProtocol {
    private let apolloClient: ApolloClient
    // Implementation details hidden from clients
}
```

### Operation Adapters

Create adapters to decouple Apollo-generated operations from your domain:

```swift
// Internal adapter to convert between Apollo types and our domain types
internal struct ApolloOperationAdapter<T: ApolloAPI.GraphQLOperation, Data> {
    private let apolloOperation: T
    
    init(apolloOperation: T) {
        self.apolloOperation = apolloOperation
    }
    
    func toGraphQLOperation() -> GraphQLOperation {
        // Convert Apollo operation to our abstracted operation
    }
    
    static func convertResult(_ apolloResult: Apollo.GraphQLResult<T.Data>) -> GraphQLResult<Data> {
        // Convert Apollo result to our abstracted result
    }
}
```

### Factory Methods for Clean API

Provide factory methods to create operations without exposing Apollo:

```swift
// Clean API that doesn't expose Apollo
public enum UserOperationFactory {
    public static func makeGetUserOperation(id: String) -> some GraphQLOperation {
        return GetUserOperationWrapper(id: id)
    }
}

// Internal implementation
private struct GetUserOperationWrapper: GraphQLOperation {
    let id: String
    
    var operationType: GraphQLOperationType { .query }
    var operationName: String { "GetUser" }
    var variables: [String: Any]? { ["id": id] }
    
    // Internal conversion to Apollo operation happens in the client
}
```

## 7. Testing and Error Handling

### Creating MockGraphQLClient for Testing

```swift
// MockGraphQLClient.swift
public final class MockGraphQLClient: GraphQLClientProtocol {
    public var mockResult: Any?
    public var mockError: Error?
    public var performedOperations: [String] = []
    
    public init(mockResult: Any? = nil, mockError: Error? = nil) {
        self.mockResult = mockResult
        self.mockError = mockError
    }
    
    public func perform<Operation: GraphQLOperation>(
        operation: Operation
    ) async throws -> GraphQLResult<Operation.Data> {
        performedOperations.append(operation.operationName)
        
        if let error = mockError {
            throw error
        }
        
        guard let result = mockResult as? GraphQLResult<Operation.Data> else {
            throw NSError(domain: "MockGraphQLClient", code: 1, 
                          userInfo: [NSLocalizedDescriptionKey: "Mock result not configured or wrong type"])
        }
        
        return result
    }
    
    public func cancelOperations(withNames names: [String]) {
        // Do nothing in mock
    }
}
```

### Unit Testing Feature Services

```swift
// UserServiceTests.swift
import XCTest
@testable import UserFeatureAPIKit
import APICoreKit

final class UserServiceTests: XCTestCase {
    func testGetUser_Success() async throws {
        // Arrange
        let expectedUser = User(id: "123", name: "Test User", email: "test@example.com", profilePictureURL: nil)
        
        // Create mock data that matches GraphQL schema
        let mockData = MockUserData(
            user: MockUser(
                id: expectedUser.id,
                name: expectedUser.name,
                email: expectedUser.email,
                profilePicture: nil
            )
        )
        
        let mockResult = GraphQLResult<MockUserData>(data: mockData, errors: nil)
        let mockClient = MockGraphQLClient(mockResult: mockResult)
        let service = UserService(graphQLClient: mockClient)
        
        // Act
        let user = try await service.getUser(id: "123")
        
        // Assert
        XCTAssertEqual(user.id, expectedUser.id)
        XCTAssertEqual(user.name, expectedUser.name)
        XCTAssertEqual(user.email, expectedUser.email)
        XCTAssertEqual(mockClient.performedOperations.first, "GetUser")
    }
    
    func testGetUser_Error() async {
        // Arrange
        let mockError = GraphQLError(message: "User not found")
        let mockResult = GraphQLResult<MockUserData>(data: nil, errors: [mockError])
        let mockClient = MockGraphQLClient(mockResult: mockResult)
        let service = UserService(graphQLClient: mockClient)
        
        // Act & Assert
        do {
            _ = try await service.getUser(id: "123")
            XCTFail("Should have thrown an error")
        } catch UserServiceError.graphQLError(let message) {
            XCTAssertEqual(message, "User not found")
        } catch {
            XCTFail("Wrong error thrown: \(error)")
        }
    }
}

// Mock data structures for testing
struct MockUserData {
    let user: MockUser?
}

struct MockUser {
    let id: String
    let name: String
    let email: String
    let profilePicture: String?
}
```

### Comprehensive Error Handling

```swift
// GraphQLErrorHandler.swift
public enum GraphQLErrorType: Error {
    case network(underlying: Error)
    case graphQL(errors: [GraphQLError])
    case parsing(underlying: Error)
    case noData
    case cancelled
    case unknown
}

extension GraphQLErrorType: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .network(let error):
            return "Network error: \(error.localizedDescription)"
        case .graphQL(let errors):
            return "GraphQL errors: \(errors.map { $0.message }.joined(separator: ", "))"
        case .parsing(let error):
            return "Data parsing error: \(error.localizedDescription)"
        case .noData:
            return "No data returned"
        case .cancelled:
            return "Operation was cancelled"
        case .unknown:
            return "An unknown error occurred"
        }
    }
}

// Usage in client implementation
private func mapApolloError(_ error: Error) -> GraphQLErrorType {
    if let apolloError = error as? Apollo.GraphQLHTTPResponseError {
        if let graphQLErrors = apolloError.graphQLErrors, !graphQLErrors.isEmpty {
            return .graphQL(errors: graphQLErrors.map { 
                GraphQLError(message: $0.message, path: $0.path, extensions: $0.extensions) 
            })
        }
        return .network(underlying: apolloError)
    } else if error is DecodingError {
        return .parsing(underlying: error)
    } else if (error as NSError).domain == NSURLErrorDomain {
        if (error as NSError).code == NSURLErrorCancelled {
            return .cancelled
        }
        return .network(underlying: error)
    }
    return .unknown
}
```

## 8. Summary and Next Steps

### Summary

By following this guide, you've:
- Created a layer of abstraction around Apollo Client to minimize direct dependencies
- Implemented feature-specific GraphQL operations with type safety
- Set up a strategy for gradual migration from REST to GraphQL
- Established patterns for testing and error handling

### Next Steps

1. **Gradual Migration Planning**:
   - Identify high-priority features to migrate first
   - Create a spreadsheet tracking endpoints and their migration status
   - Set up feature flags to control GraphQL adoption

2. **Schema Management**:
   - Implement a process for schema updates and code generation
   - Consider setting up a CI job to keep schemas in sync

3. **Performance Monitoring**:
   - Instrument GraphQL requests for tracking performance
   - Set up dashboards to compare REST vs. GraphQL performance

4. **Advanced Features**:
   - Implement subscriptions for real-time data
   - Set up optimistic UI updates with Apollo cache
   - Add query persistence for offline support

5. **Knowledge Sharing**:
   - Document common GraphQL patterns for your team
   - Create example PRs demonstrating migration patterns
   - Schedule knowledge-sharing sessions about GraphQL benefits

By following this modular approach to Apollo Client integration, you can gradually adopt GraphQL while maintaining backward compatibility and keeping your codebase clean and maintainable.
