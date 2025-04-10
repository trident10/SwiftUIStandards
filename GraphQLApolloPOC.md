# Apollo iOS Integration with API Core Kit

## 1. Introduction

This document outlines the steps and considerations for integrating Apollo iOS, a strongly-typed GraphQL client, into our existing API Core Kit. The primary goal is to add GraphQL support while maintaining the current architecture's abstraction layers and modularity. By implementing this integration properly, we will:

- Support both REST and GraphQL API requests through a unified interface
- Hide Apollo implementation details from Feature API Kits
- Maintain our existing separation of concerns
- Enable type-safe GraphQL operations with code generation
- Ensure the system remains testable and maintainable

## 2. Apollo iOS Integration Steps

### 2a. Adding Apollo iOS to the Project

1. Add Apollo iOS via Swift Package Manager:
   ```swift
   // In your Package.swift file or via Xcode's package dependency UI
   dependencies: [
       .package(url: "https://github.com/apollographql/apollo-ios.git", .upToNextMajor(from: "4.0.0"))
   ]
   ```

2. Install Apollo CLI for code generation:
   ```bash
   mkdir -p scripts
   curl -L https://install.apollo.dev/ios/latest | bash
   ```

3. Add a build script to run code generation when .graphql files change:
   ```bash
   if [ -f ./scripts/apollo-ios-cli ]; then
     ./scripts/apollo-ios-cli generate
   else
     echo "warning: Apollo iOS code generation skipped: script not found"
   fi
   ```

### 2b. Setting up Apollo Client Within API Core Kit

1. Create an `ApolloProvider` class inside the API Core Kit:

   ```swift
   // This class should be internal to the API Core Kit
   internal final class ApolloProvider {
       private let client: ApolloClient
       
       init(url: URL, configuration: URLSessionConfiguration = .default) {
           let store = ApolloStore()
           let interceptorProvider = DefaultInterceptorProvider(store: store)
           let networkTransport = RequestChainNetworkTransport(
               interceptorProvider: interceptorProvider,
               endpointURL: url
           )
           self.client = ApolloClient(networkTransport: networkTransport, store: store)
       }
       
       // Methods to execute queries, mutations, subscriptions
       func execute<Query: GraphQLQuery>(query: Query, cachePolicy: CachePolicy = .default) async throws -> Query.Data {
           // Implementation to fetch data using Apollo client
       }
       
       // Similar methods for mutations and subscriptions
   }
   ```

## 3. Maintaining Abstraction

### 3a. Hiding Apollo Client Types and Interfaces

1. Create a protocol-based abstraction for GraphQL operations in the API Core Kit:

   ```swift
   // Public protocol for GraphQL requests
   public protocol GraphQLRequest: Request {
       associatedtype Operation: GraphQLOperation
       associatedtype ResponseData
       
       var operation: Operation { get }
       
       // Convert Apollo data to our domain model
       func map(data: Operation.Data) throws -> ResponseData
   }
   
   // Internal protocol that bridges to Apollo
   internal protocol GraphQLOperation {
       associatedtype Data
       
       // Properties needed by Apollo to execute the operation
       var operationName: String { get }
       var operationDocument: String { get }
       var variables: [String: Any]? { get }
   }
   ```

2. Implement adapters for Apollo's types:

   ```swift
   // Internal extensions to adapt Apollo's types to our protocols
   extension Apollo.GraphQLQuery: GraphQLOperation {
       typealias Data = Self.Data
   }
   
   extension Apollo.GraphQLMutation: GraphQLOperation {
       typealias Data = Self.Data
   }
   ```

### 3b. Creating Wrapper Classes or Protocols

1. Extend the existing `NetworkingProvider` protocol to support GraphQL:

   ```swift
   // Add GraphQL support to NetworkingProvider
   public extension NetworkingProvider {
       func execute<R: GraphQLRequest>(_ request: R) async throws -> Response<R.ResponseData> {
           // Implementation delegated to concrete provider
       }
   }
   ```

2. Create a concrete implementation that uses Apollo:

   ```swift
   // Internal to API Core Kit
   internal final class GraphQLNetworkingProvider: NetworkingProvider {
       private let apolloProvider: ApolloProvider
       
       init(url: URL) {
           self.apolloProvider = ApolloProvider(url: url)
       }
       
       // Implement method to execute GraphQL requests
       func execute<R: GraphQLRequest>(_ request: R) async throws -> Response<R.ResponseData> {
           do {
               let data = try await apolloProvider.execute(query: request.operation)
               let mappedData = try request.map(data: data)
               return Response(data: mappedData, metadata: [:])
           } catch {
               throw self.mapApolloError(error)
           }
       }
       
       private func mapApolloError(_ error: Error) -> Error {
           // Convert Apollo errors to our error type
       }
   }
   ```

## 4. Handling GraphQL Requests and Responses

### 4a. Creating GraphQL Requests in Feature API Kits

Feature API Kits will define their GraphQL operations and implement the `GraphQLRequest` protocol:

```swift
// In a Feature API Kit
public struct GetUserRequest: GraphQLRequest {
    // Define the request parameters
    public let userId: String
    
    public init(userId: String) {
        self.userId = userId
    }
    
    // Use the generated Apollo operation
    public var operation: Generated.GetUserQuery {
        return Generated.GetUserQuery(id: userId)
    }
    
    // Map Apollo's response to our domain model
    public func map(data: Generated.GetUserQuery.Data) throws -> User {
        guard let userData = data.user else {
            throw APIError.responseMappingFailed
        }
        
        return User(
            id: userData.id,
            name: userData.name,
            email: userData.email
        )
    }
}
```

### 4b. Processing Requests Using Apollo Client

The `APIClient` will route GraphQL requests to the appropriate provider:

```swift
// Extension to APIClient in Core Kit
extension APIClient {
    public func execute<R: GraphQLRequest>(_ request: R) async throws -> Response<R.ResponseData> {
        // Apply request interceptors
        let interceptedRequest = self.requestInterceptors.reduce(request) { $1.intercept($0) }
        
        // Execute request using GraphQL provider
        var response = try await self.graphQLProvider.execute(interceptedRequest)
        
        // Apply response interceptors
        response = self.responseInterceptors.reduce(response) { $1.intercept($0) }
        
        return response
    }
}
```

### 4c. Converting Apollo Responses

The Apollo responses will be converted to our domain models using the mapping function in each request:

```swift
// Sample implementation in the GraphQLNetworkingProvider
func execute<R: GraphQLRequest>(_ request: R) async throws -> Response<R.ResponseData> {
    do {
        let apolloResult = try await apolloProvider.execute(query: request.operation)
        
        // Handle GraphQL errors
        if let errors = apolloResult.errors, !errors.isEmpty {
            throw self.createGraphQLError(errors)
        }
        
        // Map Apollo data to our domain model
        guard let data = apolloResult.data else {
            throw APIError.noDataReturned
        }
        
        let mappedData = try request.map(data: data)
        
        // Create response with metadata
        return Response(
            data: mappedData,
            metadata: [
                "cacheHit": apolloResult.source == .cache,
                "operationName": request.operation.operationName
            ]
        )
    } catch {
        throw self.mapApolloError(error)
    }
}
```

### 4d. Error Handling and Conversion

Convert Apollo errors to our error format:

```swift
private func mapApolloError(_ error: Error) -> Error {
    switch error {
    case let apolloError as Apollo.GraphQLError:
        // Map GraphQL errors
        return APIError.graphQLError(
            message: apolloError.message ?? "Unknown GraphQL error",
            path: apolloError.path,
            extensions: apolloError.extensions
        )
    case let networkError as Apollo.ResponseCodeInterceptor.ResponseCodeError:
        // Map HTTP errors
        return APIError.httpError(
            code: networkError.httpResponse.statusCode,
            data: networkError.rawData
        )
    case let operationError as Apollo.OperationError:
        // Map operation errors
        return APIError.networkError(
            underlyingError: operationError
        )
    default:
        return APIError.unknownError(underlyingError: error)
    }
}
```

## 5. Apollo Script Usage

### 5a. Using Apollo Codegen

1. Create an Apollo configuration file (`apollo-codegen-config.json`) in your project root:

```json
{
  "schemaNamespace": "GraphQLAPI",
  "input": {
    "operationSearchPaths": ["**/*.graphql"],
    "schemaSearchPaths": ["**/schema.graphql"]
  },
  "output": {
    "testMocks": {
      "none": {}
    },
    "schemaTypes": {
      "path": "./APICore/GraphQL/GeneratedSchema",
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

2. Run the code generation script after updating `.graphql` files:

```bash
./scripts/apollo-ios-cli generate
```

### 5b. Placement of Generated Files

1. Structure your project to separate GraphQL files:

```
ProjectRoot/
├── APICore/
│   └── GraphQL/
│       ├── GeneratedSchema/        # Apollo-generated schema files
│       └── ApolloProvider.swift    # Apollo client wrapper
├── FeatureKits/
│   └── UserKit/
│       ├── GraphQL/                # Feature-specific GraphQL files
│       │   ├── Operations/
│       │   │   └── GetUser.graphql # GraphQL operation definitions
│       │   └── Requests/
│       │       └── GetUserRequest.swift # Request implementation
│       └── Models/
│           └── User.swift          # Domain models
└── schema.graphql                  # GraphQL schema
```

2. Configure each Feature API Kit to reference only its own operations:

```swift
// In your Feature API Kit target
import APICore
import GraphQLAPI // The generated Apollo code
```

## 6. Future-proofing Considerations

### 6a. Minimizing Impact of Client Changes

1. Implement a façade pattern for all Apollo interactions:

```swift
// GraphQL provider protocol (not tied to Apollo)
public protocol GraphQLClientProvider {
    func executeQuery<T>(name: String, variables: [String: Any]?, responseType: T.Type) async throws -> T
    func executeMutation<T>(name: String, variables: [String: Any]?, responseType: T.Type) async throws -> T
}

// Apollo implementation (hidden inside API Core Kit)
internal final class ApolloGraphQLProvider: GraphQLClientProvider {
    // Implementation using Apollo
}
```

2. Keep all Apollo-specific code in a dedicated module that can be replaced:

```swift
// Main module imports provider protocol but not implementation
import APICore // Contains GraphQLClientProvider protocol

// Core module implementation detail
#if USE_APOLLO
import ApolloGraphQLProvider
let graphQLProvider = ApolloGraphQLProvider()
#elseif USE_OTHER_CLIENT
import OtherGraphQLProvider
let graphQLProvider = OtherGraphQLProvider()
#endif
```

### 6b. Best Practices for Separation

1. Create clear boundaries between GraphQL-specific code and domain logic:
   - Keep domain models free of GraphQL-specific annotations
   - Use mappers to convert between GraphQL and domain models
   - Never expose generated GraphQL types in public APIs

2. Use dependency injection for the GraphQL client:

```swift
public final class APIClient {
    private let restProvider: NetworkingProvider
    private let graphQLProvider: GraphQLClientProvider
    
    public init(
        restProvider: NetworkingProvider,
        graphQLProvider: GraphQLClientProvider
    ) {
        self.restProvider = restProvider
        self.graphQLProvider = graphQLProvider
    }
    
    // API methods
}
```

3. Create testing utilities that don't depend on Apollo:

```swift
// Mock GraphQL provider for testing
public final class MockGraphQLProvider: GraphQLClientProvider {
    public var stubbedResponses: [String: Any] = [:]
    
    public func executeQuery<T>(name: String, variables: [String: Any]?, responseType: T.Type) async throws -> T {
        return stubbedResponses[name] as! T
    }
    
    // Other methods
}
```

## 7. Sample Code

### 7a. Wrapper Class for Apollo Client

```swift
internal final class ApolloProvider {
    private let client: ApolloClient
    
    init(url: URL, configuration: URLSessionConfiguration = .default) {
        let cache = InMemoryNormalizedCache()
        let store = ApolloStore(cache: cache)
        
        let interceptorProvider = DefaultInterceptorProvider(
            store: store,
            client: URLSessionClient(sessionConfiguration: configuration)
        )
        
        let networkTransport = RequestChainNetworkTransport(
            interceptorProvider: interceptorProvider,
            endpointURL: url
        )
        
        self.client = ApolloClient(networkTransport: networkTransport, store: store)
    }
    
    func execute<Query: GraphQLQuery>(
        query: Query, 
        cachePolicy: CachePolicy = .fetchIgnoringCacheData
    ) async throws -> GraphQLResult<Query.Data> {
        return try await withCheckedThrowingContinuation { continuation in
            client.fetch(query: query, cachePolicy: cachePolicy) { result in
                continuation.resume(with: result)
            }
        }
    }
    
    func perform<Mutation: GraphQLMutation>(
        mutation: Mutation
    ) async throws -> GraphQLResult<Mutation.Data> {
        return try await withCheckedThrowingContinuation { continuation in
            client.perform(mutation: mutation) { result in
                continuation.resume(with: result)
            }
        }
    }
}
```

### 7b. Example of a GraphQL Request in a Feature API Kit

```swift
// User.graphql
query GetUser($id: ID!) {
  user(id: $id) {
    id
    name
    email
    profilePicture
  }
}

// UserKit/Requests/GetUserRequest.swift
import APICore
import GraphQLAPI

public struct GetUserRequest: GraphQLRequest {
    public typealias Operation = GraphQLAPI.GetUserQuery
    public typealias ResponseData = User
    
    private let userId: String
    
    public init(userId: String) {
        self.userId = userId
    }
    
    public var operation: Operation {
        return GetUserQuery(id: userId)
    }
    
    public func map(data: Operation.Data) throws -> User {
        guard let userData = data.user else {
            throw APIError.responseMappingFailed("User data not found")
        }
        
        return User(
            id: userData.id,
            name: userData.name,
            email: userData.email,
            profileImageURL: userData.profilePicture.flatMap { URL(string: $0) }
        )
    }
}

// Usage in a feature
let apiClient = APIClient.shared
let request = GetUserRequest(userId: "123")

do {
    let response = try await apiClient.execute(request)
    let user = response.data
    // Use the user object
} catch {
    // Handle error
}
```

### 7c. Conversion of Apollo Response to Required Response Format

```swift
extension APIClient {
    public func execute<R: GraphQLRequest>(_ request: R) async throws -> Response<R.ResponseData> {
        // Apply request interceptors
        let interceptedRequest = self.apply(interceptors: self.requestInterceptors, to: request)
        
        do {
            // Execute the GraphQL request
            let apolloResult = try await graphQLProvider.execute(operation: request.operation)
            
            // Handle GraphQL errors
            if let errors = apolloResult.errors, !errors.isEmpty {
                throw self.createGraphQLError(from: errors)
            }
            
            // Extract and map data
            guard let data = apolloResult.data else {
                throw APIError.noDataReturned
            }
            
            let mappedData = try request.map(data: data)
            
            // Create our response object
            var response = Response(
                data: mappedData,
                metadata: self.createMetadata(from: apolloResult, request: request)
            )
            
            // Apply response interceptors
            response = self.apply(interceptors: self.responseInterceptors, to: response)
            
            return response
        } catch {
            // Map Apollo errors to our error type
            throw self.mapError(error)
        }
    }
    
    private func createMetadata<R: GraphQLRequest>(
        from result: GraphQLResult<R.Operation.Data>, 
        request: R
    ) -> [String: Any] {
        return [
            "operationName": request.operation.operationName,
            "cacheHit": result.source == .cache,
            "extensions": result.extensions ?? [:]
        ]
    }
}
```
