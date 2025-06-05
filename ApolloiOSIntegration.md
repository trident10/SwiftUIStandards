# Apollo iOS Integration Architecture Guide

## Table of Contents
1. [Architecture Overview](#architecture-overview)
2. [Core Networking Protocols](#core-networking-protocols)
3. [Network Service Implementation](#network-service-implementation)
4. [Apollo Client Configuration](#apollo-client-configuration)
5. [Request/Response Handling](#requestresponse-handling)
6. [Error Handling](#error-handling)
7. [Authentication & Interceptors](#authentication--interceptors)
8. [Caching Strategy](#caching-strategy)
9. [Code Generation Setup](#code-generation-setup)
10. [Testing Infrastructure](#testing-infrastructure)
11. [Migration Strategy](#migration-strategy)

## Architecture Overview

The proposed architecture creates a unified networking layer that abstracts both REST and GraphQL operations behind common protocols, allowing seamless integration while maintaining clean separation of concerns.

```
┌─────────────────────────────────────────────────────────────┐
│                     NetworkServiceProtocol                   │
├─────────────────────────────────────────────────────────────┤
│                           ┌─────────┐                        │
│                           │ Factory │                        │
│                           └────┬────┘                        │
│                ┌──────────────┴──────────────┐              │
│                ▼                              ▼              │
│        ┌──────────────┐              ┌──────────────┐       │
│        │ RESTService  │              │GraphQLService│       │
│        └──────┬───────┘              └──────┬───────┘       │
│               │                              │               │
│        ┌──────▼───────┐              ┌──────▼───────┐       │
│        │  URLSession  │              │ ApolloClient │       │
│        └──────────────┘              └──────────────┘       │
└─────────────────────────────────────────────────────────────┘
```

## Core Networking Protocols

### Base Network Types

```swift
import Foundation
import Apollo

// MARK: - Core Types

public enum NetworkError: Error {
    case invalidURL
    case noData
    case decodingError(Error)
    case networkError(Error)
    case graphQLErrors([GraphQLError])
    case unauthorized
    case serverError(statusCode: Int, message: String?)
    case unknown(Error)
}

public protocol NetworkCancellable {
    func cancel()
}

// MARK: - Request Configuration

public protocol NetworkRequestConfigurable {
    var baseURL: URL { get }
    var headers: [String: String] { get }
    var timeout: TimeInterval { get }
}

public struct NetworkConfiguration: NetworkRequestConfigurable {
    public let baseURL: URL
    public let headers: [String: String]
    public let timeout: TimeInterval
    
    public init(
        baseURL: URL,
        headers: [String: String] = [:],
        timeout: TimeInterval = 30
    ) {
        self.baseURL = baseURL
        self.headers = headers
        self.timeout = timeout
    }
}

// MARK: - Main Protocol

public protocol NetworkServiceProtocol {
    // REST Operations
    func request<T: Decodable>(
        _ endpoint: Endpoint,
        type: T.Type
    ) async throws -> T
    
    // GraphQL Operations
    func query<Query: GraphQLQuery>(
        _ query: Query,
        cachePolicy: CachePolicy
    ) async throws -> Query.Data
    
    func perform<Mutation: GraphQLMutation>(
        _ mutation: Mutation
    ) async throws -> Mutation.Data
    
    func subscribe<Subscription: GraphQLSubscription>(
        _ subscription: Subscription
    ) -> AsyncThrowingStream<Subscription.Data, Error>
}

// MARK: - Endpoint Definition

public struct Endpoint {
    let path: String
    let method: HTTPMethod
    let headers: [String: String]?
    let parameters: [String: Any]?
    let body: Data?
    
    public init(
        path: String,
        method: HTTPMethod = .get,
        headers: [String: String]? = nil,
        parameters: [String: Any]? = nil,
        body: Data? = nil
    ) {
        self.path = path
        self.method = method
        self.headers = headers
        self.parameters = parameters
        self.body = body
    }
}

public enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
    case patch = "PATCH"
}
```

### Network Service Factory

```swift
public protocol NetworkServiceFactoryProtocol {
    func makeNetworkService(type: NetworkServiceType) -> NetworkServiceProtocol
}

public enum NetworkServiceType {
    case rest(configuration: NetworkConfiguration)
    case graphQL(configuration: GraphQLConfiguration)
}

public struct GraphQLConfiguration {
    let endpointURL: URL
    let headers: [String: String]
    let store: ApolloStore
    let cachePolicy: CachePolicy
    
    public init(
        endpointURL: URL,
        headers: [String: String] = [:],
        store: ApolloStore = ApolloStore(),
        cachePolicy: CachePolicy = .returnCacheDataElseFetch
    ) {
        self.endpointURL = endpointURL
        self.headers = headers
        self.store = store
        self.cachePolicy = cachePolicy
    }
}

public final class NetworkServiceFactory: NetworkServiceFactoryProtocol {
    private let authenticationProvider: AuthenticationProviding
    private let interceptorProvider: NetworkInterceptorProviding
    
    public init(
        authenticationProvider: AuthenticationProviding,
        interceptorProvider: NetworkInterceptorProviding
    ) {
        self.authenticationProvider = authenticationProvider
        self.interceptorProvider = interceptorProvider
    }
    
    public func makeNetworkService(type: NetworkServiceType) -> NetworkServiceProtocol {
        switch type {
        case .rest(let configuration):
            return RESTNetworkService(
                configuration: configuration,
                authenticationProvider: authenticationProvider,
                interceptorProvider: interceptorProvider
            )
            
        case .graphQL(let configuration):
            return GraphQLNetworkService(
                configuration: configuration,
                authenticationProvider: authenticationProvider,
                interceptorProvider: interceptorProvider
            )
        }
    }
}
```

## Network Service Implementation

### REST Network Service

```swift
import Foundation

public final class RESTNetworkService: NetworkServiceProtocol {
    private let configuration: NetworkConfiguration
    private let session: URLSession
    private let authenticationProvider: AuthenticationProviding
    private let interceptorProvider: NetworkInterceptorProviding
    private let decoder: JSONDecoder
    
    public init(
        configuration: NetworkConfiguration,
        authenticationProvider: AuthenticationProviding,
        interceptorProvider: NetworkInterceptorProviding,
        session: URLSession = .shared,
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.configuration = configuration
        self.authenticationProvider = authenticationProvider
        self.interceptorProvider = interceptorProvider
        self.session = session
        self.decoder = decoder
        
        // Configure decoder
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder.dateDecodingStrategy = .iso8601
    }
    
    public func request<T: Decodable>(
        _ endpoint: Endpoint,
        type: T.Type
    ) async throws -> T {
        let request = try await buildURLRequest(from: endpoint)
        
        // Apply interceptors
        let interceptedRequest = await interceptorProvider.interceptRequest(request)
        
        do {
            let (data, response) = try await session.data(for: interceptedRequest)
            
            // Handle response
            try validateResponse(response)
            
            // Apply response interceptors
            let interceptedData = await interceptorProvider.interceptResponse(
                data: data,
                response: response,
                error: nil
            )
            
            // Decode response
            return try decoder.decode(T.self, from: interceptedData)
            
        } catch {
            // Apply error interceptors
            _ = await interceptorProvider.interceptResponse(
                data: nil,
                response: nil,
                error: error
            )
            
            throw mapError(error)
        }
    }
    
    // GraphQL methods throw errors as not supported
    public func query<Query: GraphQLQuery>(
        _ query: Query,
        cachePolicy: CachePolicy
    ) async throws -> Query.Data {
        throw NetworkError.unknown(NSError(
            domain: "RESTNetworkService",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "GraphQL not supported in REST service"]
        ))
    }
    
    public func perform<Mutation: GraphQLMutation>(
        _ mutation: Mutation
    ) async throws -> Mutation.Data {
        throw NetworkError.unknown(NSError(
            domain: "RESTNetworkService",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "GraphQL not supported in REST service"]
        ))
    }
    
    public func subscribe<Subscription: GraphQLSubscription>(
        _ subscription: Subscription
    ) -> AsyncThrowingStream<Subscription.Data, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: NetworkError.unknown(NSError(
                domain: "RESTNetworkService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "GraphQL not supported in REST service"]
            )))
        }
    }
    
    // MARK: - Private Methods
    
    private func buildURLRequest(from endpoint: Endpoint) async throws -> URLRequest {
        guard let url = URL(string: endpoint.path, relativeTo: configuration.baseURL) else {
            throw NetworkError.invalidURL
        }
        
        var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: true)
        
        // Add query parameters
        if let parameters = endpoint.parameters,
           endpoint.method == .get {
            urlComponents?.queryItems = parameters.map {
                URLQueryItem(name: $0.key, value: "\($0.value)")
            }
        }
        
        guard let finalURL = urlComponents?.url else {
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: finalURL)
        request.httpMethod = endpoint.method.rawValue
        request.timeoutInterval = configuration.timeout
        
        // Set headers
        configuration.headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        endpoint.headers?.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        
        // Add authentication
        if let authHeader = await authenticationProvider.authenticationHeaders() {
            authHeader.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        }
        
        // Set body
        if endpoint.method != .get {
            if let body = endpoint.body {
                request.httpBody = body
            } else if let parameters = endpoint.parameters {
                request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
        }
        
        return request
    }
    
    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.unknown(NSError(
                domain: "RESTNetworkService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid response type"]
            ))
        }
        
        switch httpResponse.statusCode {
        case 200...299:
            break // Success
        case 401:
            throw NetworkError.unauthorized
        case 400...499:
            throw NetworkError.serverError(
                statusCode: httpResponse.statusCode,
                message: "Client error"
            )
        case 500...599:
            throw NetworkError.serverError(
                statusCode: httpResponse.statusCode,
                message: "Server error"
            )
        default:
            throw NetworkError.serverError(
                statusCode: httpResponse.statusCode,
                message: "Unknown error"
            )
        }
    }
    
    private func mapError(_ error: Error) -> NetworkError {
        if let networkError = error as? NetworkError {
            return networkError
        } else if let urlError = error as? URLError {
            return .networkError(urlError)
        } else {
            return .unknown(error)
        }
    }
}
```

### GraphQL Network Service

```swift
import Apollo
import ApolloAPI

public final class GraphQLNetworkService: NetworkServiceProtocol {
    private let apollo: ApolloClient
    private let authenticationProvider: AuthenticationProviding
    private let interceptorProvider: NetworkInterceptorProviding
    
    public init(
        configuration: GraphQLConfiguration,
        authenticationProvider: AuthenticationProviding,
        interceptorProvider: NetworkInterceptorProviding
    ) {
        self.authenticationProvider = authenticationProvider
        self.interceptorProvider = interceptorProvider
        
        // Create custom interceptor provider
        let interceptorProvider = CustomInterceptorProvider(
            authenticationProvider: authenticationProvider,
            networkInterceptorProvider: interceptorProvider,
            endpointURL: configuration.endpointURL,
            headers: configuration.headers
        )
        
        // Configure network transport
        let networkTransport = RequestChainNetworkTransport(
            interceptorProvider: interceptorProvider,
            endpointURL: configuration.endpointURL
        )
        
        // Initialize Apollo client
        self.apollo = ApolloClient(
            networkTransport: networkTransport,
            store: configuration.store
        )
    }
    
    // REST methods throw errors as not supported
    public func request<T: Decodable>(
        _ endpoint: Endpoint,
        type: T.Type
    ) async throws -> T {
        throw NetworkError.unknown(NSError(
            domain: "GraphQLNetworkService",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "REST not supported in GraphQL service"]
        ))
    }
    
    // MARK: - GraphQL Operations
    
    public func query<Query: GraphQLQuery>(
        _ query: Query,
        cachePolicy: CachePolicy = .returnCacheDataElseFetch
    ) async throws -> Query.Data {
        try await withCheckedThrowingContinuation { continuation in
            apollo.fetch(
                query: query,
                cachePolicy: cachePolicy
            ) { result in
                switch result {
                case .success(let graphQLResult):
                    if let errors = graphQLResult.errors, !errors.isEmpty {
                        continuation.resume(throwing: NetworkError.graphQLErrors(errors))
                    } else if let data = graphQLResult.data {
                        continuation.resume(returning: data)
                    } else {
                        continuation.resume(throwing: NetworkError.noData)
                    }
                    
                case .failure(let error):
                    continuation.resume(throwing: self.mapError(error))
                }
            }
        }
    }
    
    public func perform<Mutation: GraphQLMutation>(
        _ mutation: Mutation
    ) async throws -> Mutation.Data {
        try await withCheckedThrowingContinuation { continuation in
            apollo.perform(mutation: mutation) { result in
                switch result {
                case .success(let graphQLResult):
                    if let errors = graphQLResult.errors, !errors.isEmpty {
                        continuation.resume(throwing: NetworkError.graphQLErrors(errors))
                    } else if let data = graphQLResult.data {
                        continuation.resume(returning: data)
                    } else {
                        continuation.resume(throwing: NetworkError.noData)
                    }
                    
                case .failure(let error):
                    continuation.resume(throwing: self.mapError(error))
                }
            }
        }
    }
    
    public func subscribe<Subscription: GraphQLSubscription>(
        _ subscription: Subscription
    ) -> AsyncThrowingStream<Subscription.Data, Error> {
        AsyncThrowingStream { continuation in
            let cancellable = apollo.subscribe(subscription: subscription) { result in
                switch result {
                case .success(let graphQLResult):
                    if let errors = graphQLResult.errors, !errors.isEmpty {
                        continuation.finish(throwing: NetworkError.graphQLErrors(errors))
                    } else if let data = graphQLResult.data {
                        continuation.yield(data)
                    }
                    
                case .failure(let error):
                    continuation.finish(throwing: self.mapError(error))
                }
            }
            
            continuation.onTermination = { _ in
                cancellable.cancel()
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func mapError(_ error: Error) -> NetworkError {
        if let apolloError = error as? Apollo.URLSessionClient.URLSessionClientError {
            switch apolloError {
            case .networkError(let data, let response, let underlying):
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 401 {
                        return .unauthorized
                    }
                    return .serverError(
                        statusCode: httpResponse.statusCode,
                        message: data.flatMap { String(data: $0, encoding: .utf8) }
                    )
                }
                return .networkError(underlying)
                
            default:
                return .unknown(apolloError)
            }
        }
        
        return .unknown(error)
    }
}
```

## Apollo Client Configuration

### Custom Interceptor Provider

```swift
import Apollo
import ApolloAPI

final class CustomInterceptorProvider: DefaultInterceptorProvider {
    private let authenticationProvider: AuthenticationProviding
    private let networkInterceptorProvider: NetworkInterceptorProviding
    private let headers: [String: String]
    
    init(
        authenticationProvider: AuthenticationProviding,
        networkInterceptorProvider: NetworkInterceptorProviding,
        endpointURL: URL,
        headers: [String: String],
        store: ApolloStore = ApolloStore()
    ) {
        self.authenticationProvider = authenticationProvider
        self.networkInterceptorProvider = networkInterceptorProvider
        self.headers = headers
        
        super.init(client: URLSessionClient(), store: store)
    }
    
    override func interceptors<Operation: GraphQLOperation>(
        for operation: Operation
    ) -> [ApolloInterceptor] {
        var interceptors = super.interceptors(for: operation)
        
        // Add custom interceptors
        interceptors.insert(
            AuthenticationInterceptor(authenticationProvider: authenticationProvider),
            at: 0
        )
        
        interceptors.insert(
            HeadersInterceptor(headers: headers),
            at: 1
        )
        
        interceptors.insert(
            LoggingInterceptor(),
            at: 2
        )
        
        return interceptors
    }
}

// MARK: - Custom Interceptors

final class AuthenticationInterceptor: ApolloInterceptor {
    private let authenticationProvider: AuthenticationProviding
    
    init(authenticationProvider: AuthenticationProviding) {
        self.authenticationProvider = authenticationProvider
    }
    
    func interceptAsync<Operation: GraphQLOperation>(
        chain: RequestChain,
        request: HTTPRequest<Operation>,
        response: HTTPResponse<Operation>?,
        completion: @escaping (Result<GraphQLResult<Operation.Data>, Error>) -> Void
    ) {
        Task {
            if let authHeaders = await authenticationProvider.authenticationHeaders() {
                authHeaders.forEach { key, value in
                    request.addHeader(name: key, value: value)
                }
            }
            
            chain.proceedAsync(
                request: request,
                response: response,
                completion: completion
            )
        }
    }
}

final class HeadersInterceptor: ApolloInterceptor {
    private let headers: [String: String]
    
    init(headers: [String: String]) {
        self.headers = headers
    }
    
    func interceptAsync<Operation: GraphQLOperation>(
        chain: RequestChain,
        request: HTTPRequest<Operation>,
        response: HTTPResponse<Operation>?,
        completion: @escaping (Result<GraphQLResult<Operation.Data>, Error>) -> Void
    ) {
        headers.forEach { key, value in
            request.addHeader(name: key, value: value)
        }
        
        chain.proceedAsync(
            request: request,
            response: response,
            completion: completion
        )
    }
}

final class LoggingInterceptor: ApolloInterceptor {
    func interceptAsync<Operation: GraphQLOperation>(
        chain: RequestChain,
        request: HTTPRequest<Operation>,
        response: HTTPResponse<Operation>?,
        completion: @escaping (Result<GraphQLResult<Operation.Data>, Error>) -> Void
    ) {
        #if DEBUG
        print("🚀 GraphQL Request: \(Operation.operationName)")
        print("Variables: \(Operation.variables)")
        #endif
        
        let startTime = Date()
        
        chain.proceedAsync(
            request: request,
            response: response
        ) { result in
            #if DEBUG
            let duration = Date().timeIntervalSince(startTime)
            print("✅ GraphQL Response (\(String(format: "%.2f", duration))s): \(Operation.operationName)")
            
            switch result {
            case .success(let graphQLResult):
                if let errors = graphQLResult.errors {
                    print("⚠️ GraphQL Errors: \(errors)")
                }
            case .failure(let error):
                print("❌ GraphQL Error: \(error)")
            }
            #endif
            
            completion(result)
        }
    }
}
```

## Request/Response Handling

### Unified Request Builder

```swift
public protocol RequestBuilding {
    func buildRequest<T: Encodable>(
        endpoint: Endpoint,
        body: T?,
        headers: [String: String]
    ) async throws -> URLRequest
}

public final class RequestBuilder: RequestBuilding {
    private let baseURL: URL
    private let defaultHeaders: [String: String]
    private let encoder: JSONEncoder
    
    public init(
        baseURL: URL,
        defaultHeaders: [String: String] = [:],
        encoder: JSONEncoder = JSONEncoder()
    ) {
        self.baseURL = baseURL
        self.defaultHeaders = defaultHeaders
        self.encoder = encoder
        
        // Configure encoder
        self.encoder.keyEncodingStrategy = .convertToSnakeCase
        self.encoder.dateEncodingStrategy = .iso8601
    }
    
    public func buildRequest<T: Encodable>(
        endpoint: Endpoint,
        body: T?,
        headers: [String: String]
    ) async throws -> URLRequest {
        guard let url = URL(string: endpoint.path, relativeTo: baseURL) else {
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        
        // Merge headers
        defaultHeaders.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        endpoint.headers?.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        
        // Set body if provided
        if let body = body {
            request.httpBody = try encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        
        return request
    }
}

// MARK: - Response Handler

public protocol ResponseHandling {
    func handleResponse<T: Decodable>(
        data: Data,
        response: URLResponse,
        type: T.Type
    ) throws -> T
}

public final class ResponseHandler: ResponseHandling {
    private let decoder: JSONDecoder
    
    public init(decoder: JSONDecoder = JSONDecoder()) {
        self.decoder = decoder
        
        // Configure decoder
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder.dateDecodingStrategy = .iso8601
    }
    
    public func handleResponse<T: Decodable>(
        data: Data,
        response: URLResponse,
        type: T.Type
    ) throws -> T {
        // Validate HTTP response
        if let httpResponse = response as? HTTPURLResponse {
            try validateHTTPResponse(httpResponse, data: data)
        }
        
        // Decode response
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw NetworkError.decodingError(error)
        }
    }
    
    private func validateHTTPResponse(_ response: HTTPURLResponse, data: Data) throws {
        switch response.statusCode {
        case 200...299:
            return // Success
            
        case 401:
            throw NetworkError.unauthorized
            
        case 400...499:
            let message = try? decoder.decode(ErrorResponse.self, from: data).message
            throw NetworkError.serverError(
                statusCode: response.statusCode,
                message: message ?? "Client error"
            )
            
        case 500...599:
            let message = try? decoder.decode(ErrorResponse.self, from: data).message
            throw NetworkError.serverError(
                statusCode: response.statusCode,
                message: message ?? "Server error"
            )
            
        default:
            throw NetworkError.serverError(
                statusCode: response.statusCode,
                message: "Unknown error"
            )
        }
    }
}

struct ErrorResponse: Decodable {
    let message: String
    let code: String?
}
```

## Error Handling

### Unified Error Handling

```swift
public protocol NetworkErrorHandling {
    func handle(error: NetworkError) -> NetworkErrorResolution
}

public enum NetworkErrorResolution {
    case retry(after: TimeInterval)
    case authenticate
    case fail(message: String)
    case ignore
}

public final class NetworkErrorHandler: NetworkErrorHandling {
    private let retryPolicy: RetryPolicy
    private let authenticationProvider: AuthenticationProviding
    
    public init(
        retryPolicy: RetryPolicy,
        authenticationProvider: AuthenticationProviding
    ) {
        self.retryPolicy = retryPolicy
        self.authenticationProvider = authenticationProvider
    }
    
    public func handle(error: NetworkError) -> NetworkErrorResolution {
        switch error {
        case .unauthorized:
            return .authenticate
            
        case .networkError(let underlyingError):
            if let urlError = underlyingError as? URLError {
                switch urlError.code {
                case .notConnectedToInternet, .timedOut:
                    return retryPolicy.shouldRetry(for: error) ? 
                        .retry(after: retryPolicy.retryInterval) : 
                        .fail(message: "Network connection error")
                default:
                    return .fail(message: urlError.localizedDescription)
                }
            }
            return .fail(message: "Network error occurred")
            
        case .serverError(let statusCode, let message):
            if statusCode >= 500 {
                return retryPolicy.shouldRetry(for: error) ?
                    .retry(after: retryPolicy.retryInterval) :
                    .fail(message: message ?? "Server error")
            }
            return .fail(message: message ?? "Request failed")
            
        case .graphQLErrors(let errors):
            // Handle specific GraphQL errors
            if errors.contains(where: { $0.message.contains("UNAUTHENTICATED") }) {
                return .authenticate
            }
            return .fail(message: errors.first?.message ?? "GraphQL error")
            
        case .decodingError:
            return .fail(message: "Failed to parse response")
            
        case .noData:
            return .fail(message: "No data received")
            
        case .invalidURL:
            return .fail(message: "Invalid URL")
            
        case .unknown(let error):
            return .fail(message: error.localizedDescription)
        }
    }
}

// MARK: - Retry Policy

public protocol RetryPolicy {
    var maxRetries: Int { get }
    var retryInterval: TimeInterval { get }
    
    func shouldRetry(for error: NetworkError) -> Bool
}

public struct DefaultRetryPolicy: RetryPolicy {
    public let maxRetries: Int
    public let retryInterval: TimeInterval
    private var currentRetries: Int = 0
    
    public init(maxRetries: Int = 3, retryInterval: TimeInterval = 1.0) {
        self.maxRetries = maxRetries
        self.retryInterval = retryInterval
    }
    
    public func shouldRetry(for error: NetworkError) -> Bool {
        switch error {
        case .networkError, .serverError(let code, _) where code >= 500:
            return currentRetries < maxRetries
        default:
            return false
        }
    }
}
```

## Authentication & Interceptors

### Authentication Provider

```swift
public protocol AuthenticationProviding {
    func authenticationHeaders() async -> [String: String]?
    func refreshAuthentication() async throws
    func clearAuthentication() async
}

public actor AuthenticationProvider: AuthenticationProviding {
    private var token: String?
    private let tokenStorage: TokenStorage
    private let authService: AuthenticationService
    
    public init(
        tokenStorage: TokenStorage,
        authService: AuthenticationService
    ) {
        self.tokenStorage = tokenStorage
        self.authService = authService
    }
    
    public func authenticationHeaders() async -> [String: String]? {
        if token == nil {
            token = await tokenStorage.loadToken()
        }
        
        guard let token = token else { return nil }
        
        return ["Authorization": "Bearer \(token)"]
    }
    
    public func refreshAuthentication() async throws {
        let newToken = try await authService.refreshToken()
        self.token = newToken
        await tokenStorage.saveToken(newToken)
    }
    
    public func clearAuthentication() async {
        self.token = nil
        await tokenStorage.clearToken()
    }
}

// MARK: - Network Interceptor Provider

public protocol NetworkInterceptorProviding {
    func interceptRequest(_ request: URLRequest) async -> URLRequest
    func interceptResponse(
        data: Data?,
        response: URLResponse?,
        error: Error?
    ) async -> Data
}

public final class NetworkInterceptorProvider: NetworkInterceptorProviding {
    private let interceptors: [NetworkInterceptor]
    
    public init(interceptors: [NetworkInterceptor] = []) {
        self.interceptors = interceptors
    }
    
    public func interceptRequest(_ request: URLRequest) async -> URLRequest {
        var modifiedRequest = request
        
        for interceptor in interceptors {
            modifiedRequest = await interceptor.intercept(request: modifiedRequest)
        }
        
        return modifiedRequest
    }
    
    public func interceptResponse(
        data: Data?,
        response: URLResponse?,
        error: Error?
    ) async -> Data {
        var modifiedData = data ?? Data()
        
        for interceptor in interceptors {
            modifiedData = await interceptor.intercept(
                response: modifiedData,
                urlResponse: response,
                error: error
            )
        }
        
        return modifiedData
    }
}

// MARK: - Network Interceptor

public protocol NetworkInterceptor {
    func intercept(request: URLRequest) async -> URLRequest
    func intercept(
        response: Data,
        urlResponse: URLResponse?,
        error: Error?
    ) async -> Data
}

// MARK: - Logging Interceptor

public final class LoggingNetworkInterceptor: NetworkInterceptor {
    private let logger: NetworkLogging
    
    public init(logger: NetworkLogging = NetworkLogger()) {
        self.logger = logger
    }
    
    public func intercept(request: URLRequest) async -> URLRequest {
        logger.logRequest(request)
        return request
    }
    
    public func intercept(
        response: Data,
        urlResponse: URLResponse?,
        error: Error?
    ) async -> Data {
        logger.logResponse(data: response, response: urlResponse, error: error)
        return response
    }
}

public protocol NetworkLogging {
    func logRequest(_ request: URLRequest)
    func logResponse(data: Data, response: URLResponse?, error: Error?)
}

public final class NetworkLogger: NetworkLogging {
    public func logRequest(_ request: URLRequest) {
        #if DEBUG
        print("🌐 \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "")")
        if let headers = request.allHTTPHeaderFields {
            print("Headers: \(headers)")
        }
        if let body = request.httpBody,
           let bodyString = String(data: body, encoding: .utf8) {
            print("Body: \(bodyString)")
        }
        #endif
    }
    
    public func logResponse(data: Data, response: URLResponse?, error: Error?) {
        #if DEBUG
        if let httpResponse = response as? HTTPURLResponse {
            print("📥 Status: \(httpResponse.statusCode)")
        }
        if let error = error {
            print("❌ Error: \(error)")
        } else if let responseString = String(data: data, encoding: .utf8) {
            print("Response: \(responseString.prefix(500))...")
        }
        #endif
    }
}
