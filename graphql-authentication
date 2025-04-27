# Authentication Integration: REST OAuth Token Mechanism for GraphQL with Apollo Client

## 1. Introduction

This technical document outlines how our existing OAuth token authentication mechanism, currently used for REST API calls, will be extended to support GraphQL integration via Apollo Client. The goal is to maintain a single source of truth for authentication while enabling secure GraphQL API access with minimal code duplication.

## 2. Current Authentication Flow (REST APIs)

### 2.1 Overview

Our iOS application currently implements OAuth 2.0 token-based authentication for all REST API calls. The flow is as follows:

1. User completes authentication via login screen
2. App requests OAuth token from authentication endpoint
3. Token is stored in APICoreKit configuration singleton
4. All subsequent REST requests include this token automatically

### 2.2 Implementation Details

The current implementation leverages our `APICoreKit` framework, which serves as a centralized configuration hub for all API-related settings:

```swift
// APICoreKit - Current implementation

class APIConfiguration {
    static let shared = APIConfiguration()
    
    private(set) var authToken: String?
    private(set) var tokenType: String = "Bearer"
    
    private init() {}
    
    func updateAuthToken(_ token: String) {
        self.authToken = token
    }
    
    func getAuthorizationHeader() -> [String: String]? {
        guard let token = authToken else { return nil }
        return ["Authorization": "\(tokenType) \(token)"]
    }
    
    func clearAuthToken() {
        self.authToken = nil
    }
}

// Usage in REST client
class RESTClient {
    func performRequest(_ request: URLRequest) -> URLRequest {
        var mutableRequest = request
        
        // Automatically inject auth headers to all requests
        if let headers = APIConfiguration.shared.getAuthorizationHeader() {
            for (key, value) in headers {
                mutableRequest.setValue(value, forHTTPHeaderField: key)
            }
        }
        
        return mutableRequest
    }
}
```

When a user logs in, the authentication token is stored:

```swift
func handleLoginSuccess(authResponse: AuthResponse) {
    APIConfiguration.shared.updateAuthToken(authResponse.accessToken)
    // Additional login success handling
}
```

## 3. GraphQL Integration with Apollo Client

### 3.1 Apollo Client Architecture

Apollo Client for iOS consists of several components that work together to execute GraphQL operations:

- **ApolloClient**: The main client interface for executing operations
- **NetworkTransport**: Responsible for sending GraphQL requests to the server
- **HTTPNetworkTransport**: The default implementation for HTTP-based GraphQL APIs
- **InterceptorProvider**: Configures a chain of interceptors for request processing

To integrate our existing OAuth authentication mechanism with Apollo Client, we'll leverage Apollo's interceptor chain pattern, which allows for request modification before execution.

### 3.2 Integration Strategy

Our approach will:

1. Create a custom `AuthenticationInterceptor` that injects the OAuth token into GraphQL requests
2. Configure Apollo Client to use this interceptor for all requests
3. Reuse the existing token storage in `APIConfiguration` without duplication

## 4. Implementation Details

### 4.1 Authentication Interceptor

First, we'll create a custom interceptor that adds authentication headers to all GraphQL requests:

```swift
import Apollo
import ApolloAPI

class AuthenticationInterceptor: ApolloInterceptor {
    enum AuthenticationInterceptorError: Error {
        case notAuthenticated
    }
    
    let id = "AuthenticationInterceptor"
    
    func interceptAsync<Operation>(
        chain: RequestChain,
        request: HTTPRequest<Operation>,
        response: HTTPResponse<Operation>?,
        completion: @escaping (Result<GraphQLResult<Operation.Data>, Error>) -> Void
    ) where Operation: GraphQLOperation {
        
        // Retrieve authentication headers from our existing APIConfiguration
        if let authHeaders = APIConfiguration.shared.getAuthorizationHeader() {
            // Add auth headers to the GraphQL request
            for (key, value) in authHeaders {
                request.addHeader(name: key, value: value)
            }
            chain.proceedAsync(
                request: request,
                response: response,
                completion: completion
            )
        } else {
            // Handle unauthenticated state based on your app's requirements
            // Option 1: Proceed without auth (for public queries)
            chain.proceedAsync(
                request: request,
                response: response,
                completion: completion
            )
            
            // Option 2: Fail the request (for protected queries)
            // completion(.failure(AuthenticationInterceptorError.notAuthenticated))
        }
    }
}
```

### 4.2 Custom Interceptor Provider

Next, we'll create a custom interceptor provider that includes our authentication interceptor in the chain:

```swift
class NetworkInterceptorProvider: DefaultInterceptorProvider {
    override func interceptors<Operation>(for operation: Operation) -> [ApolloInterceptor] where Operation: GraphQLOperation {
        var interceptors = super.interceptors(for: operation)
        
        // Add our authentication interceptor
        // Note: The order of interceptors is important
        interceptors.insert(AuthenticationInterceptor(), at: 0)
        
        return interceptors
    }
}
```

### 4.3 Apollo Client Configuration

Finally, we'll configure the Apollo Client to use our custom interceptor provider:

```swift
import Apollo
import ApolloAPI

class GraphQLService {
    static let shared = GraphQLService()
    
    private(set) var apollo: ApolloClient
    
    private init() {
        // Create the URL for your GraphQL API endpoint
        let url = URL(string: "https://api.your-backend.com/graphql")!
        
        // Create an HTTP transport with your custom interceptor provider
        let interceptorProvider = NetworkInterceptorProvider(
            store: ApolloStore(),
            client: URLSessionClient()
        )
        
        let transport = RequestChainNetworkTransport(
            interceptorProvider: interceptorProvider,
            endpointURL: url
        )
        
        // Initialize Apollo client with the transport
        apollo = ApolloClient(networkTransport: transport)
    }
    
    // Example of how to use the configured client
    func fetchUserProfile(completion: @escaping (Result<UserProfile, Error>) -> Void) {
        apollo.fetch(query: UserProfileQuery()) { result in
            switch result {
            case .success(let graphQLResult):
                if let data = graphQLResult.data {
                    // Transform GraphQL data to your domain model
                    let userProfile = UserProfile(from: data)
                    completion(.success(userProfile))
                } else if let errors = graphQLResult.errors {
                    completion(.failure(GraphQLError.queryErrors(errors)))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}

// Error type for GraphQL operations
enum GraphQLError: Error {
    case queryErrors([GraphQLError])
    case noData
}
```

## 5. Token Refresh Mechanism

For a complete implementation, we should also handle token refresh when the OAuth token expires. We can extend our approach to handle 401 Unauthorized responses:

```swift
class TokenRefreshInterceptor: ApolloInterceptor {
    let id = "TokenRefreshInterceptor"
    
    func interceptAsync<Operation>(
        chain: RequestChain,
        request: HTTPRequest<Operation>,
        response: HTTPResponse<Operation>?,
        completion: @escaping (Result<GraphQLResult<Operation.Data>, Error>) -> Void
    ) where Operation: GraphQLOperation {
        
        // Only proceed with next steps if we received a response
        guard let response = response else {
            chain.proceedAsync(
                request: request,
                response: response,
                completion: completion
            )
            return
        }
        
        // Check status code
        if response.statusCode == 401 {
            // Token has expired, refresh it
            refreshToken { result in
                switch result {
                case .success(let newToken):
                    // Update token in APIConfiguration
                    APIConfiguration.shared.updateAuthToken(newToken)
                    
                    // Retry the operation with new token
                    // We need to create a new request as the previous one was already sent
                    let retryRequest = request.copy()
                    
                    // Update the Authorization header with the new token
                    if let authHeaders = APIConfiguration.shared.getAuthorizationHeader() {
                        for (key, value) in authHeaders {
                            retryRequest.addHeader(name: key, value: value)
                        }
                    }
                    
                    // Restart the chain with our updated request
                    chain.retry(request: retryRequest, completion: completion)
                    
                case .failure(let error):
                    // Handle refresh token failure
                    // This might involve logging the user out
                    completion(.failure(error))
                }
            }
        } else {
            // Status code doesn't indicate an authentication issue
            chain.proceedAsync(
                request: request,
                response: response,
                completion: completion
            )
        }
    }
    
    private func refreshToken(completion: @escaping (Result<String, Error>) -> Void) {
        // Implement token refresh logic here
        // This typically involves using a refresh token to get a new access token
        // For demonstration purposes, we'll leave this as a placeholder
    }
}
```

Add this interceptor to your `NetworkInterceptorProvider`:

```swift
override func interceptors<Operation>(for operation: Operation) -> [ApolloInterceptor] where Operation: GraphQLOperation {
    var interceptors = super.interceptors(for: operation)
    
    interceptors.insert(AuthenticationInterceptor(), at: 0)
    
    // Add the token refresh interceptor after the network fetch but before response parsing
    interceptors.insert(TokenRefreshInterceptor(), at: 3) // Exact position may vary
    
    return interceptors
}
```

## 6. Best Practices and Considerations

### 6.1 Error Handling

- GraphQL errors should be handled distinctly from HTTP/network errors
- Authentication errors should trigger appropriate user feedback or automatic recovery
- Consider implementing a centralized error handler for consistent user experience

### 6.2 Testing Strategy

- Unit test the interceptors in isolation
- Integration test the complete authentication flow
- Consider mocking the Apollo client for component tests
- Test both authenticated and unauthenticated scenarios

### 6.3 Security Considerations

- Store tokens securely (consider using Keychain for persistence)
- Implement token expiration handling
- Support token revocation on logout
- Add appropriate timeout configurations

## 7. Migration Plan

1. Implement the `AuthenticationInterceptor` and `TokenRefreshInterceptor`
2. Create the custom `NetworkInterceptorProvider`
3. Configure the Apollo Client
4. Test with existing authentication flow
5. Gradually migrate REST API calls to GraphQL where appropriate

## 8. Conclusion

This implementation allows us to reuse our existing authentication mechanism with GraphQL queries and mutations while maintaining a single source of truth within `APICoreKit`. The interceptor-based approach is flexible and can be extended to handle additional requirements in the future.

By leveraging Apollo's built-in interceptor chain, we ensure that all GraphQL operations automatically include the appropriate authentication headers without duplicating authentication logic across our codebase.
