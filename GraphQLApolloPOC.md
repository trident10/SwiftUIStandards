# Apollo iOS Integration Guide for API Core Kit

## 1. Introduction

This document outlines the process of integrating Apollo iOS into our existing API Core Kit to add GraphQL support while maintaining our current architecture patterns. The key goals of this integration are:

- Add comprehensive GraphQL support to our networking layer
- Leverage Apollo iOS for type-safe GraphQL operations
- Maintain the existing abstraction layers and patterns
- Keep Apollo-specific types and interfaces hidden from Feature API Kits
- Ensure a consistent developer experience regardless of the underlying protocol (REST or GraphQL)

## 2. Apollo iOS Integration Steps

### 2.1 Adding Apollo iOS to the Project

1. Add Apollo iOS as a dependency using Swift Package Manager:
   ```
   File > Add Packages... > Search or Enter Package URL > https://github.com/apollographql/apollo-ios.git
   ```
   - Set the dependency rule to: Up to Next Major Version (4.0.0 < 5.0.0)
   - Select the API Core Kit target as the target for this package

2. Add Apollo iOS CLI for code generation:
   ```bash
   mkdir -p scripts
   curl -L https://install.apollo.dev/ios/latest | bash
   ```

3. Add a Run Script Phase to your target's Build Phases:
   ```bash
   cd "${SRCROOT}"
   ./scripts/apollo-ios-cli generate
   ```

### 2.2 Setting Up Apollo Client Within API Core Kit

Create a new `ApolloProvider` class within the API Core Kit to encapsulate Apollo client functionality:

```swift
// Private implementation file, not exposed in public API
final class ApolloProvider {
    private let apolloClient: ApolloClient
    
    init(url: URL, configuration: URLSessionConfiguration = .default) {
        let store = ApolloStore()
        let interceptorProvider = DefaultInterceptorProvider(store: store)
        let networkTransport = RequestChainNetworkTransport(
            interceptorProvider: interceptorProvider,
            endpointURL: url
        )
        
        self.apolloClient = ApolloClient(
            networkTransport: networkTransport,
            store: store
        )
    }
    
    // Methods to perform queries/mutations will be added here
}
```

## 3. Maintaining Abstraction

### 3.1 Hiding Apollo Client Types and Interfaces

To keep Apollo types hidden from the rest of the application, we'll create wrapper classes and protocols that fit within our existing architecture:

1. Create a `GraphQLAdapter` class that converts between our internal types and Apollo types:

```swift
// Internal to API Core Kit
final class GraphQLAdapter {
    private let apolloProvider: ApolloProvider
    
    init(apolloProvider: ApolloProvider) {
        self.apolloProvider = apolloProvider
    }
    
    func execute<T: Decodable>(_ request: GraphQLRequest<T>, completion: @escaping (Result<Response<T>, Error>) -> Void) {
        // This will convert our GraphQLRequest to Apollo's Query/Mutation and handle the response
    }
}
```

2. Extend the existing `NetworkingProvider` protocol to support GraphQL operations without exposing Apollo:

```swift
// Public API
extension NetworkingProvider {
    func executeGraphQL<T: Decodable>(_ request: GraphQLRequest<T>, completion: @escaping (Result<Response<T>, Error>) -> Void) {
        // Implementation will differ based on the concrete provider
    }
}
```

### 3.2 Creating Wrapper Classes and Protocols

1. Implement a concrete `GraphQLRequest` type that conforms to our existing `Request` protocol:

```swift
// Public API
public struct GraphQLRequest<ResponseType: Decodable>: Request {
    public typealias Response = ResponseType
    
    public let operationType: GraphQLOperationType
    public let operationName: String
    public let query: String
    public let variables: [String: Any]?
    
    public init(
        operationType: GraphQLOperationType,
        operationName: String,
        query: String,
        variables: [String: Any]? = nil
    ) {
        self.operationType = operationType
        self.operationName = operationName
        self.query = query
        self.variables = variables
    }
}

public enum GraphQLOperationType {
    case query
    case mutation
    case subscription
}
```

2. Create a `GraphQLOperation` protocol that Feature API Kits can use to define their operations:

```swift
// Public API
public protocol GraphQLOperation {
    associatedtype ResponseType: Decodable
    
    var operationType: GraphQLOperationType { get }
    var operationName: String { get }
    var query: String { get }
    var variables: [String: Any]? { get }
}

// Extension to convert a GraphQLOperation to a GraphQLRequest
public extension GraphQLOperation {
    func asRequest() -> GraphQLRequest<ResponseType> {
        return GraphQLRequest(
            operationType: operationType,
            operationName: operationName,
            query: query,
            variables: variables
        )
    }
}
```

## 4. Handling GraphQL Requests and Responses

### 4.1 Creating GraphQL Requests in Feature API Kits

Feature API Kits will define specific operations by conforming to the `GraphQLOperation` protocol:

```swift
// In a Feature API Kit
struct GetUserProfileOperation: GraphQLOperation {
    typealias ResponseType = UserProfile
    
    let operationType: GraphQLOperationType = .query
    let operationName: String = "GetUserProfile"
    let query: String = """
    query GetUserProfile($id: ID!) {
      user(id: $id) {
        id
        name
        email
        profilePicture
      }
    }
    """
    
    let variables: [String: Any]?
    
    init(userId: String) {
        self.variables = ["id": userId]
    }
}

// Usage in the feature code
let operation = GetUserProfileOperation(userId: "123")
let request = operation.asRequest()

apiClient.send(request) { result in
    switch result {
    case .success(let response):
        // Handle the UserProfile object
    case .failure(let error):
        // Handle error
    }
}
```

### 4.2 Processing Requests Using Apollo Client

Within the `GraphQLAdapter`, we'll process the requests using Apollo client:

```swift
func execute<T: Decodable>(_ request: GraphQLRequest<T>, completion: @escaping (Result<Response<T>, Error>) -> Void) {
    switch request.operationType {
    case .query:
        executeQuery(request, completion: completion)
    case .mutation:
        executeMutation(request, completion: completion)
    case .subscription:
        // Subscriptions are handled differently and may require WebSocket transport
        executeSubscription(request, completion: completion)
    }
}

private func executeQuery<T: Decodable>(_ request: GraphQLRequest<T>, completion: @escaping (Result<Response<T>, Error>) -> Void) {
    // Convert our request to Apollo Query
    let queryDocument = try? ApolloAPI.DocumentNode(definition: request.query)
    guard let queryDocument else {
        completion(.failure(APIError.invalidRequest))
        return
    }
    
    // Execute the query
    apolloProvider.apolloClient.fetch(query: ApolloAPI.GraphQLRequest(
        document: queryDocument,
        operation: request.operationName,
        variables: request.variables,
        responseCodegenConfiguration: .init())
    ) { result in
        self.handleApolloResult(result, completion: completion)
    }
}

// Similar methods for executeMutation and executeSubscription
```

### 4.3 Converting Apollo Responses

Convert Apollo responses to our internal `Response` format:

```swift
private func handleApolloResult<T: Decodable>(_ result: Result<GraphQLResult<ApolloAPI.JSONObject>, Error>, completion: @escaping (Result<Response<T>, Error>) -> Void) {
    switch result {
    case .success(let graphQLResult):
        if let errors = graphQLResult.errors, !errors.isEmpty {
            // Handle GraphQL errors
            let apiError = self.convertGraphQLErrors(errors)
            completion(.failure(apiError))
            return
        }
        
        guard let data = graphQLResult.data else {
            completion(.failure(APIError.noData))
            return
        }
        
        do {
            // Convert ApolloAPI.JSONObject to our model type T
            let jsonData = try JSONSerialization.data(withJSONObject: data)
            let decoder = JSONDecoder()
            let decodedData = try decoder.decode(T.self, from: jsonData)
            
            // Create our Response type
            let response = Response(
                data: decodedData,
                metadata: ResponseMetadata(
                    statusCode: 200,
                    headers: [:] // Add any relevant headers from the GraphQL response
                )
            )
            
            completion(.success(response))
        } catch {
            completion(.failure(APIError.decodingFailed(error)))
        }
        
    case .failure(let error):
        // Convert Apollo error to our Error type
        completion(.failure(self.convertApolloError(error)))
    }
}
```

### 4.4 Error Handling

Implement error handling that converts Apollo errors to our API Core Kit error format:

```swift
private func convertGraphQLErrors(_ errors: [GraphQLError]) -> Error {
    // Extract relevant information from GraphQL errors
    // and convert to our own error type
    return APIError.serverError(
        message: errors.map { $0.message }.joined(separator: ", "),
        code: "GRAPHQL_ERROR"
    )
}

private func convertApolloError(_ error: Error) -> Error {
    // Convert Apollo specific errors to our error type
    if let apolloError = error as? Apollo.ResponseCodeableError {
        return APIError.networkError(apolloError)
    }
    
    return APIError.unknownError(error)
}
```

## 5. Apollo Script Usage

### 5.1 Using Apollo Codegen

1. Create a configuration file at the root of your project named `apollo-codegen.yml`:

```yaml
schema:
  - schema.graphql
operations:
  - "**/*.graphql"
targetName: MyApp
output: ./MyApp/Generated/
```

2. Create a schema file (`schema.graphql`) by fetching it from your GraphQL server:

```bash
./scripts/apollo-ios-cli download-schema --endpoint=https://api.example.com/graphql
```

3. Create `.graphql` files for your queries, mutations, and subscriptions in appropriate Feature API Kit directories:

```graphql
# UserKit/GraphQL/UserQueries.graphql
query GetUserProfile($id: ID!) {
  user(id: $id) {
    id
    name
    email
    profilePicture
  }
}
```

4. Run the code generation:

```bash
./scripts/apollo-ios-cli generate
```

### 5.2 Organizing Generated Files

1. Generated files should be placed within Feature Kits in a `Generated` directory:

```
MyApp/
├── API Core Kit/
│   └── ...
├── Feature Kits/
│   ├── UserKit/
│   │   ├── GraphQL/
│   │   │   └── UserQueries.graphql
│   │   └── Generated/
│   │       └── UserAPI.swift
│   └── ProductKit/
│       ├── GraphQL/
│       │   └── ProductQueries.graphql
│       └── Generated/
│           └── ProductAPI.swift
└── ...
```

2. Modify the `apollo-codegen.yml` to generate files in the appropriate locations:

```yaml
schema:
  - schema.graphql
operations:
  - "Feature Kits/UserKit/GraphQL/*.graphql"
  - "Feature Kits/ProductKit/GraphQL/*.graphql"
targetName: MyApp
output:
  - targetName: UserKit
    path: ./Feature Kits/UserKit/Generated/
    operations:
      - "Feature Kits/UserKit/GraphQL/*.graphql"
  - targetName: ProductKit
    path: ./Feature Kits/ProductKit/Generated/
    operations:
      - "Feature Kits/ProductKit/GraphQL/*.graphql"
```

## 6. Future-proofing Considerations

### 6.1 Minimizing Impact of Switching GraphQL Clients

1. Keep all Apollo-specific code within the API Core Kit, specifically in adapter classes.
2. Use our own abstractions (protocols and models) for GraphQL operations.
3. Create a clear interface boundary that would allow replacing the underlying GraphQL client:

```swift
// Public protocol - independent of Apollo
public protocol GraphQLClientProvider {
    func executeQuery<T: Decodable>(_ request: GraphQLRequest<T>, completion: @escaping (Result<Response<T>, Error>) -> Void)
    func executeMutation<T: Decodable>(_ request: GraphQLRequest<T>, completion: @escaping (Result<Response<T>, Error>) -> Void)
    func executeSubscription<T: Decodable>(_ request: GraphQLRequest<T>, completion: @escaping (Result<Response<T>, Error>) -> Void)
}

// Internal implementation using Apollo
final class ApolloGraphQLClientProvider: GraphQLClientProvider {
    private let apolloProvider: ApolloProvider
    
    init(apolloProvider: ApolloProvider) {
        self.apolloProvider = apolloProvider
    }
    
    // Implement the protocol methods using Apollo
}
```

### 6.2 Maintaining Clean Separation

1. Keep Apollo imports strictly confined to adapter implementation files.
2. Never expose Apollo types in public interfaces:

```swift
// WRONG:
public func process(result: GraphQLResult<Data>) // Exposing Apollo types

// RIGHT:
public func process(result: Result<Response<UserProfile>, Error>) // Using our own types
```

3. Use feature toggles to enable GraphQL functionality:

```swift
public class APIClient {
    private let restProvider: RESTProvider
    private let graphQLProvider: GraphQLClientProvider?
    
    public init(
        restProvider: RESTProvider,
        graphQLProvider: GraphQLClientProvider? = nil
    ) {
        self.restProvider = restProvider
        self.graphQLProvider = graphQLProvider
    }
    
    public func send<T: Request>(_ request: T, completion: @escaping (Result<T.Response, Error>) -> Void) {
        if let graphQLRequest = request as? GraphQLRequest<T.Response>, 
           let graphQLProvider = graphQLProvider {
            // Use GraphQL
            graphQLProvider.executeQuery(graphQLRequest, completion: completion)
        } else {
            // Fall back to REST
            restProvider.execute(request, completion: completion)
        }
    }
}
```

## 7. Sample Code

### 7.1 Apollo Client Wrapper

```swift
// Internal to API Core Kit - not exposed in public API
final class ApolloClientWrapper {
    private let apolloClient: ApolloClient
    
    init(serverURL: URL) {
        let store = ApolloStore()
        let provider = NetworkInterceptorProvider(store: store, serverURL: serverURL)
        let transport = RequestChainNetworkTransport(
            interceptorProvider: provider,
            endpointURL: serverURL
        )
        self.apolloClient = ApolloClient(networkTransport: transport, store: store)
    }
    
    func fetch<Query: GraphQLQuery>(
        query: Query,
        cachePolicy: CachePolicy = .default,
        contextIdentifier: UUID? = nil,
        queue: DispatchQueue = .main,
        completion: @escaping (Result<Query.Data, Error>) -> Void
    ) {
        apolloClient.fetch(
            query: query,
            cachePolicy: cachePolicy,
            contextIdentifier: contextIdentifier,
            queue: queue
        ) { result in
            switch result {
            case .success(let graphQLResult):
                if let errors = graphQLResult.errors, !errors.isEmpty {
                    // Handle GraphQL errors
                    let combinedMessage = errors.map { $0.message ?? "Unknown error" }.joined(separator: ", ")
                    completion(.failure(APIError.graphQLError(message: combinedMessage)))
                    return
                }
                
                if let data = graphQLResult.data {
                    completion(.success(data))
                } else {
                    completion(.failure(APIError.noData))
                }
                
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // Similar methods for mutations and subscriptions
}
```

### 7.2 Example of a GraphQL Request in a Feature API Kit

```swift
// In UserFeatureKit
struct UserProfileRequest: GraphQLOperation {
    typealias ResponseType = UserProfile
    
    let operationType: GraphQLOperationType = .query
    let operationName: String = "GetUserProfile"
    let query: String
    let variables: [String: Any]?
    
    init(userId: String) {
        self.query = """
        query GetUserProfile($id: ID!) {
          user(id: $id) {
            id
            name
            email
            profilePicture
          }
        }
        """
        self.variables = ["id": userId]
    }
}

// Usage example
func fetchUserProfile(userId: String, completion: @escaping (Result<UserProfile, Error>) -> Void) {
    let request = UserProfileRequest(userId: userId).asRequest()
    apiClient.send(request, completion: completion)
}
```

### 7.3 Conversion of Apollo Response to Required Response Format

```swift
// Inside the ApolloAdapter
private func convertApolloResult<T: Decodable, Q: GraphQLQuery>(
    _ result: Result<GraphQLResult<Q.Data>, Error>,
    completion: @escaping (Result<Response<T>, Error>) -> Void
) {
    switch result {
    case .success(let graphQLResult):
        if let errors = graphQLResult.errors, !errors.isEmpty {
            let errorMessages = errors.map { $0.message ?? "Unknown GraphQL error" }
            completion(.failure(APIError.graphQLError(message: errorMessages.joined(separator: ", "))))
            return
        }
        
        guard let data = graphQLResult.data else {
            completion(.failure(APIError.noData))
            return
        }
        
        do {
            // Convert Apollo's typed data to a dictionary
            let jsonObject = try Q.Data.jsonObject(data)
            
            // Convert to JSON data
            let jsonData = try JSONSerialization.data(withJSONObject: jsonObject)
            
            // Decode to our model type
            let decoder = JSONDecoder()
            let model = try decoder.decode(T.self, from: jsonData)
            
            // Create our Response type
            let response = Response(
                data: model,
                metadata: ResponseMetadata(
                    statusCode: 200,
                    headers: [:] // Apollo doesn't provide HTTP headers directly
                )
            )
            
            completion(.success(response))
        } catch {
            completion(.failure(APIError.decodingFailed(error)))
        }
        
    case .failure(let error):
        // Convert Apollo errors to our error type
        if let apolloError = error as? Apollo.ResponseCodeableError {
            switch apolloError {
            case .invalidOperation:
                completion(.failure(APIError.invalidRequest))
            case .parsedError:
                completion(.failure(APIError.parsingFailed))
            case .networkError(let error):
                completion(.failure(APIError.networkError(error)))
            case .httpError(let response, let data):
                let statusCode = response.statusCode
                completion(.failure(APIError.httpError(statusCode: statusCode)))
            default:
                completion(.failure(APIError.unknownError(error)))
            }
        } else {
            completion(.failure(APIError.unknownError(error)))
        }
    }
}
```
