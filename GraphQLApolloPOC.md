# Apollo iOS Integration for API Core Kit

## 1. Introduction

This document outlines the process for integrating the Apollo iOS library into our existing API Core Kit to support GraphQL operations. The primary goal is to add GraphQL support using Apollo client while ensuring we maintain our current architecture's abstraction levels. This integration will:

- Add GraphQL capabilities alongside existing REST functionality
- Hide Apollo-specific types/interfaces from the rest of the application
- Maintain the existing architecture patterns and abstractions
- Allow Feature API Kits to utilize GraphQL without direct Apollo dependencies

## 2. Apollo iOS Integration Steps

### 2.1 Adding Apollo iOS to the Project

1. Add Apollo iOS via Swift Package Manager:
   ```
   Dependencies > + Button > Search "https://github.com/apollographql/apollo-ios.git" > Up to Next Major Version (4.0.0 < 5.0.0)
   ```

2. Select the API Core Kit target to add the Apollo dependency.

3. Create an Apollo directory in the API Core Kit module:
   ```
   APIKit/
     ├── Core/
     ├── Apollo/
     ├── REST/
     └── ...
   ```

4. Set up the Apollo CLI for code generation:
   ```bash
   mkdir -p scripts
   curl -L https://install.apollo.dev/ios/latest | bash
   ```

5. Add the Apollo CLI script to your project's build phases for code generation (see section 5 for details).

### 2.2 Setting Up Apollo Client Within API Core Kit

1. Create an `ApolloClientProvider` as an implementation of a `GraphQLClientProvider` protocol:

   ```swift
   protocol GraphQLClientProvider {
       func execute<Query: GraphQLQueryProtocol>(query: Query) async throws -> GraphQLResult
       func perform<Mutation: GraphQLMutationProtocol>(mutation: Mutation) async throws -> GraphQLResult
       // Other necessary methods
   }
   
   class ApolloClientProvider: GraphQLClientProvider {
       private let client: ApolloClient
       
       init(url: URL, interceptors: [ApolloInterceptor] = []) {
           let store = ApolloStore()
           let provider = NetworkInterceptorProvider(store: store, client: URLSessionClient(), interceptors: interceptors)
           let transport = RequestChainNetworkTransport(
               interceptorProvider: provider,
               endpointURL: url
           )
           self.client = ApolloClient(networkTransport: transport, store: store)
       }
       
       func execute<Query: GraphQLQueryProtocol>(query: Query) async throws -> GraphQLResult {
           // Implementation using Apollo client
       }
       
       func perform<Mutation: GraphQLMutationProtocol>(mutation: Mutation) async throws -> GraphQLResult {
           // Implementation using Apollo client
       }
   }
   ```

2. Register the `ApolloClientProvider` with the API Core Kit:

   ```swift
   // In the APICore configuration
   public class APIConfiguration {
       let graphQLClientProvider: GraphQLClientProvider
       
       public init(
           baseURL: URL,
           graphQLURL: URL,
           // Other parameters
       ) {
           self.graphQLClientProvider = ApolloClientProvider(url: graphQLURL)
           // Other initialization
       }
   }
   ```

## 3. Maintaining Abstraction

### 3.1 Hiding Apollo Types

1. Create domain-specific protocols and types to wrap Apollo functionality:

   ```swift
   // In API Core Kit
   public protocol GraphQLOperation {
       associatedtype ResultType
       var operationType: GraphQLOperationType { get }
       var operationString: String { get }
       var variables: [String: Any]? { get }
   }
   
   public enum GraphQLOperationType {
       case query
       case mutation
       case subscription
   }
   
   public struct GraphQLResult {
       public let data: Any?
       public let errors: [GraphQLError]?
       
       // Methods to extract typed data
       public func get<T>(_ type: T.Type) -> T?
   }
   
   public struct GraphQLError {
       public let message: String
       public let locations: [SourceLocation]?
       public let path: [String]?
       public let extensions: [String: Any]?
   }
   ```

2. Create a `GraphQLRequest` implementation of the existing `Request` protocol:

   ```swift
   public struct GraphQLRequest<Operation: GraphQLOperation>: Request {
       public typealias ResponseType = GraphQLResult
       
       private let operation: Operation
       
       public init(operation: Operation) {
           self.operation = operation
       }
       
       // Implement Request protocol methods
   }
   ```

### 3.2 Creating Abstraction Layers

1. Add a `GraphQLClient` class that uses the `GraphQLClientProvider` but exposes API Core Kit types:

   ```swift
   class GraphQLClient {
       private let provider: GraphQLClientProvider
       
       init(provider: GraphQLClientProvider) {
           self.provider = provider
       }
       
       func execute<O: GraphQLOperation>(operation: O) async throws -> GraphQLResult {
           // Convert between API Core Kit types and Apollo types
       }
   }
   ```

2. Update the `APIClient` to handle GraphQL requests:

   ```swift
   public class APIClient {
       private let restClient: RESTClient
       private let graphQLClient: GraphQLClient
       
       public func send<R: Request>(_ request: R) async throws -> R.ResponseType {
           if let graphQLRequest = request as? GraphQLRequest<any GraphQLOperation> {
               return try await handleGraphQLRequest(graphQLRequest)
           } else {
               return try await restClient.send(request)
           }
       }
       
       private func handleGraphQLRequest<O: GraphQLOperation>(_ request: GraphQLRequest<O>) async throws -> GraphQLResult {
           // Implementation
       }
   }
   ```

## 4. Handling GraphQL Requests and Responses

### 4.1 Creating GraphQL Requests in Feature API Kits

Feature API Kits will define GraphQL operations using `.graphql` files, but will wrap the generated operations in their own types:

```swift
// In UserFeatureKit

// The .graphql file:
// query GetUser($id: ID!) {
//   user(id: $id) {
//     id
//     name
//     email
//   }
// }

struct GetUserOperation: GraphQLOperation {
    typealias ResultType = User
    
    let id: String
    
    var operationType: GraphQLOperationType { .query }
    var operationString: String { GetUserQuery.operationString }
    var variables: [String: Any]? { ["id": id] }
}

struct UserAPI {
    private let apiClient: APIClient
    
    func getUser(id: String) async throws -> User {
        let operation = GetUserOperation(id: id)
        let request = GraphQLRequest(operation: operation)
        let result = try await apiClient.send(request)
        
        guard let user = result.get(User.self) else {
            throw APIError.parsingFailed
        }
        
        return user
    }
}
```

### 4.2 Processing GraphQL Requests

The API Core Kit will process GraphQL requests by:

1. Extracting the operation details
2. Converting to Apollo's query/mutation types
3. Executing via the Apollo client
4. Converting the response back to API Core Kit types

```swift
private func handleGraphQLRequest<O: GraphQLOperation>(_ request: GraphQLRequest<O>) async throws -> GraphQLResult {
    let operation = request.operation
    
    switch operation.operationType {
    case .query:
        // Convert to Apollo query and execute
        let result = try await graphQLClient.execute(operation: operation)
        return result
        
    case .mutation:
        // Convert to Apollo mutation and execute
        let result = try await graphQLClient.perform(operation: operation)
        return result
        
    case .subscription:
        throw APIError.unsupportedOperationType
    }
}
```

### 4.3 Response Conversion

When converting Apollo responses to the API Core Kit format:

```swift
// Inside ApolloClientProvider
func execute<Query: GraphQLQueryProtocol>(query: Query) async throws -> GraphQLResult {
    return try await withCheckedThrowingContinuation { continuation in
        client.fetch(query: query) { result in
            switch result {
            case .success(let apolloResult):
                let convertedResult = self.convertApolloResult(apolloResult)
                continuation.resume(returning: convertedResult)
                
            case .failure(let error):
                continuation.resume(throwing: self.convertApolloError(error))
            }
        }
    }
}

private func convertApolloResult<T>(_ apolloResult: GraphQLResult<T>) -> GraphQLResult {
    return GraphQLResult(
        data: apolloResult.data,
        errors: apolloResult.errors?.map { self.convertGraphQLError($0) }
    )
}

private func convertGraphQLError(_ error: Apollo.GraphQLError) -> GraphQLError {
    return GraphQLError(
        message: error.message,
        locations: error.locations?.map { SourceLocation(line: $0.line, column: $0.column) },
        path: error.path,
        extensions: error.extensions
    )
}
```

### 4.4 Error Handling

Create a mapping between Apollo errors and API Core Kit errors:

```swift
private func convertApolloError(_ error: Error) -> Error {
    if let apolloError = error as? Apollo.GraphQLError {
        return APIError.graphQLError(convertGraphQLError(apolloError))
    } else if let networkError = error as? Apollo.NetworkError {
        switch networkError {
        case .transportFailure(let underlying):
            return APIError.networkError(underlying)
        case .noData:
            return APIError.emptyResponse
        case .parseError:
            return APIError.parsingFailed
        default:
            return APIError.unknown(error)
        }
    } else {
        return APIError.unknown(error)
    }
}
```

## 5. Apollo Script Usage

### 5.1 GraphQL Schema and Operations

1. Set up your project structure:
   ```
   YourProject/
     ├── graphql/
     │   ├── schema.graphql           // Your GraphQL schema
     │   └── apollo-codegen-config.json  // Apollo configuration
     └── Features/
         ├── UserFeature/
         │   └── GraphQL/
         │       ├── GetUser.graphql
         │       └── UpdateUser.graphql
         └── PostFeature/
             └── GraphQL/
                 ├── GetPosts.graphql
                 └── CreatePost.graphql
   ```

2. Create the `apollo-codegen-config.json` file:
   ```json
   {
     "schemaName": "YourAPI",
     "input": {
       "operationSearchPaths": ["./Features/**/GraphQL/*.graphql"],
       "schemaSearchPaths": ["./graphql/schema.graphql"]
     },
     "output": {
       "testMocks": {
         "none": {}
       },
       "schemaTypes": {
         "path": "./APIKit/Apollo/SchemaTypes.swift",
         "moduleType": {
           "swiftPackageManager": {}
         }
       },
       "operations": {
         "inSchemaModule": {}
       }
     }
   }
   ```

3. Add a build script phase to your project:
   ```bash
   cd "${SRCROOT}"
   ./scripts/apollo-ios-cli generate
   ```

### 5.2 Generated Files Placement

1. The Apollo code generation will create Swift files in the paths defined in the configuration
2. The generated `SchemaTypes.swift` will be placed in the API Core Kit's Apollo directory
3. Feature-specific operations will be placed in their respective Feature Kit's GraphQL directory

## 6. Future-proofing Considerations

### 6.1 Minimizing Impact of Client Changes

1. **Strict Protocol Boundaries**: Keep all Apollo-specific code behind clearly defined protocols like `GraphQLClientProvider`.

2. **Dependency Injection**: Inject the GraphQL client into your `APIClient` rather than instantiating it directly.

3. **Wrapper Types**: Maintain your own wrappers for all Apollo types, especially those exposed to Feature Kits.

4. **Abstract Factory Pattern**: Consider using a factory for creating GraphQL operations that could adapt to different underlying implementations.

5. **Separate Build Target**: Place all Apollo-specific code in a separate build target that only API Core Kit depends on.

### 6.2 Best Practices for Clean Separation

1. **Package Structure**:
   ```
   APIKit/
     ├── Public/          // Public interfaces used by Feature Kits
     ├── Core/            // Common networking functionality
     ├── Apollo/          // Apollo-specific implementation (internal)
     └── REST/            // REST-specific implementation (internal)
   ```

2. **Apollo-specific Code Isolation**:
   - Keep all Apollo imports restricted to the Apollo directory
   - Never expose Apollo types in public interfaces
   - Use protocol extensions to add Apollo-specific functionality without exposing it

3. **Automated Compliance Testing**:
   - Create unit tests that verify Feature Kits aren't directly using Apollo types
   - Set up build time checks to ensure proper layer isolation

## 7. Sample Code

### 7.1 Apollo Client Wrapper

```swift
import Apollo
import Foundation

protocol GraphQLClientProvider {
    func execute<Operation: GraphQLOperation>(operation: Operation) async throws -> GraphQLResult
}

// Concrete Apollo implementation
class ApolloGraphQLProvider: GraphQLClientProvider {
    private let client: ApolloClient
    
    init(url: URL) {
        self.client = ApolloClient(url: url)
    }
    
    func execute<Operation: GraphQLOperation>(operation: Operation) async throws -> GraphQLResult {
        switch operation.operationType {
        case .query:
            return try await executeQuery(operation)
        case .mutation:
            return try await executeMutation(operation)
        case .subscription:
            throw APIError.unsupportedOperationType
        }
    }
    
    private func executeQuery<Operation: GraphQLOperation>(_ operation: Operation) async throws -> GraphQLResult {
        // Convert operation to Apollo query and execute
        let queryDocument = operation.operationString
        let variables = operation.variables
        
        return try await withCheckedThrowingContinuation { continuation in
            client.fetch(query: ApolloQueryHelper.createQuery(queryDocument, variables: variables)) { result in
                // Convert result to GraphQLResult and resume continuation
                // Implementation details omitted for brevity
            }
        }
    }
    
    private func executeMutation<Operation: GraphQLOperation>(_ operation: Operation) async throws -> GraphQLResult {
        // Similar implementation to executeQuery but for mutations
    }
}
```

### 7.2 Example GraphQL Request in Feature API Kit

```swift
// In UserFeatureKit
import APICore

// Define operation
struct GetUserProfileOperation: GraphQLOperation {
    typealias ResultType = UserProfile
    
    let userId: String
    
    var operationType: GraphQLOperationType { .query }
    var operationString: String {
        """
        query GetUserProfile($userId: ID!) {
          userProfile(id: $userId) {
            id
            name
            email
            avatarUrl
          }
        }
        """
    }
    var variables: [String: Any]? { ["userId": userId] }
}

// Use in API service
class UserService {
    private let apiClient: APIClient
    
    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }
    
    func getUserProfile(userId: String) async throws -> UserProfile {
        let operation = GetUserProfileOperation(userId: userId)
        let request = GraphQLRequest(operation: operation)
        
        let result = try await apiClient.send(request)
        
        guard let profile = result.get(UserProfile.self) else {
            throw UserServiceError.profileNotFound
        }
        
        return profile
    }
}
```

### 7.3 Converting Apollo Response to API Core Kit Response

```swift
// In ApolloGraphQLProvider.swift
private func convertApolloResponse<T>(response: GraphQLResponse<T>) -> GraphQLResult {
    // Extract data
    let data = response.data
    
    // Convert GraphQL errors
    let errors = response.errors?.map { apolloError in
        GraphQLError(
            message: apolloError.message,
            locations: apolloError.locations?.map {
                SourceLocation(line: $0.line, column: $0.column)
            },
            path: apolloError.path,
            extensions: apolloError.extensions
        )
    }
    
    // Create the result
    return GraphQLResult(
        data: data,
        errors: errors
    )
}

// Helper for typed data extraction
extension GraphQLResult {
    public func get<T>(_ type: T.Type) -> T? {
        guard let data = data else { return nil }
        
        // Implementation would depend on how data is structured
        // This could use JSONSerialization and Decodable, or
        // it could use a more sophisticated mapping approach
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: data),
           let result = try? JSONDecoder().decode(T.self, from: jsonData) {
            return result
        }
        
        return nil
    }
}
```

---

This integration approach ensures that we can leverage Apollo's powerful GraphQL capabilities while maintaining our existing API Core Kit architecture and abstraction levels. By strictly adhering to these guidelines, we keep Apollo implementation details isolated from Feature Kits, allowing us to replace or upgrade the GraphQL client in the future with minimal impact on the codebase.
