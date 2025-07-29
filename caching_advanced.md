# Apollo iOS Caching Integration Guide

## Overview

Apollo iOS caching is a sophisticated client-side caching system that provides normalized storage for GraphQL responses. Unlike simple response caching, normalized caching stores individual objects from your GraphQL responses in a flat structure, allowing for efficient data retrieval, automatic UI updates when related data changes, and reduced network requests.

The normalized cache automatically handles relationships between objects, deduplicates data, and ensures consistency across your app. When you fetch a user's profile and later fetch a list of users that includes the same user, Apollo's cache will automatically merge and update the data, keeping your UI in sync.

## Prerequisites

Before implementing caching, ensure you have:

- **Apollo iOS SDK** (version 1.0+) already integrated in your project
- **Basic Apollo Client setup** with schema and generated code
- **Understanding of your GraphQL schema** and object types
- **Network layer configured** (URLSession or custom)

Your existing Apollo setup should look something like:

```swift
import Apollo

let apollo = ApolloClient(url: URL(string: "https://api.example.com/graphql")!)
```

## Step-by-Step Integration Guide for Normalized Caching

### Step 1: Add Cache Dependencies

First, ensure you have the necessary Apollo caching components. If you're using SPM, make sure you have these targets:

```swift
// In your Package.swift or Xcode project
dependencies: [
    .package(url: "https://github.com/apollographql/apollo-ios", from: "1.0.0")
]

// Import in your files
import Apollo
import ApolloSQLite // For persistent cache
```

### Step 2: Create the Normalized Cache

Create a normalized cache store. You can choose between in-memory or persistent storage:

```swift
import Apollo
import ApolloSQLite

class ApolloManager {
    static let shared = ApolloManager()
    
    private(set) lazy var apollo: ApolloClient = {
        // Create cache
        let cache = InMemoryNormalizedCache()
        // For persistent cache, use:
        // let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
        // let databaseURL = URL(fileURLWithPath: documentsPath).appendingPathComponent("apollo_cache.sqlite")
        // let cache = try! SQLNormalizedCache(fileURL: databaseURL)
        
        let store = ApolloStore(cache: cache)
        
        let client = ApolloClient(
            networkTransport: RequestChainNetworkTransport(
                interceptorProvider: DefaultInterceptorProvider(store: store),
                endpointURL: URL(string: "https://api.example.com/graphql")!
            ),
            store: store
        )
        
        return client
    }()
    
    private init() {}
}
```

### Step 3: Configure Cache Key Resolution

For effective caching, configure how Apollo identifies unique objects. This is crucial for normalization:

```swift
extension ApolloManager {
    private func createApolloClient() -> ApolloClient {
        let cache = InMemoryNormalizedCache()
        let store = ApolloStore(cache: cache)
        
        // Configure cache key resolution
        store.cacheKeyForObject = { object, variables in
            if let id = object["id"] as? String {
                return "\(object["__typename"] as? String ?? "Unknown"):\(id)"
            }
            
            // Handle objects without IDs (see handling section below)
            if let email = object["email"] as? String,
               let typename = object["__typename"] as? String,
               typename == "User" {
                return "User:email:\(email)"
            }
            
            return nil
        }
        
        let networkTransport = RequestChainNetworkTransport(
            interceptorProvider: DefaultInterceptorProvider(store: store),
            endpointURL: URL(string: "https://api.example.com/graphql")!
        )
        
        return ApolloClient(networkTransport: networkTransport, store: store)
    }
}
```

## Step-by-Step Integration Guide for Different Caching Strategies

### Custom Cache Policy Abstraction

Since our project architecture uses Kit Controllers that call APICoreKit GraphQL functions (which abstract Apollo GraphQL client), we need to create our own cache policy enum and map it to Apollo's cache policies:

#### 1. Define Kit-Level Cache Policy

```swift
// In your Kit layer (e.g., NetworkKit or APIKit)
public enum KitCachePolicy: CaseIterable {
    case cacheFirst         // Check cache first, network if not found  
    case networkOnly        // Always fetch from network, update cache
    case cacheOnly          // Only return cached data, don't network
    case cacheAndNetwork    // Return cache immediately, then fetch and update
}

extension KitCachePolicy {
    var apolloCachePolicy: Apollo.CachePolicy {
        switch self {
        case .cacheFirst:
            return .returnCacheDataElseFetch
        case .networkOnly:
            return .fetchIgnoringCacheData
        case .cacheOnly:
            return .returnCacheDataDontFetch
        case .cacheAndNetwork:
            return .returnCacheDataAndFetch
        }
    }
}
```

#### 2. Update APICoreKit GraphQL Fetch Function

```swift
// In APICoreKit
public class GraphQLService {
    private let apolloClient: ApolloClient
    
    public init(apolloClient: ApolloClient) {
        self.apolloClient = apolloClient
    }
    
    public func fetch<Query: GraphQLQuery>(
        query: Query,
        cachePolicy: KitCachePolicy = .cacheFirst,
        completion: @escaping (Result<GraphQLResult<Query.Data>, Error>) -> Void
    ) {
        apolloClient.fetch(
            query: query,
            cachePolicy: cachePolicy.apolloCachePolicy
        ) { result in
            completion(result)
        }
    }
    
    // Async/await version
    public func fetch<Query: GraphQLQuery>(
        query: Query,
        cachePolicy: KitCachePolicy = .cacheFirst
    ) async throws -> GraphQLResult<Query.Data> {
        return try await withCheckedThrowingContinuation { continuation in
            apolloClient.fetch(
                query: query,
                cachePolicy: cachePolicy.apolloCachePolicy
            ) { result in
                continuation.resume(with: result)
            }
        }
    }
}
```

#### 3. Kit Controller Implementation

```swift
// In your specific Kit (e.g., UserKit)
public class UserController {
    private let graphQLService: GraphQLService
    
    public init(graphQLService: GraphQLService) {
        self.graphQLService = graphQLService
    }
    
    public func fetchUserProfile(
        userId: String,
        cachePolicy: KitCachePolicy = .networkOnly,
        completion: @escaping (Result<UserProfile, Error>) -> Void
    ) {
        let query = GetUserProfileQuery(userId: userId)
        
        graphQLService.fetch(
            query: query,
            cachePolicy: cachePolicy
        ) { result in
            switch result {
            case .success(let graphQLResult):
                if let user = graphQLResult.data?.user {
                    let userProfile = self.mapToUserProfile(user)
                    completion(.success(userProfile))
                } else if let errors = graphQLResult.errors {
                    completion(.failure(GraphQLError.serverErrors(errors)))
                } else {
                    completion(.failure(GraphQLError.noData))
                }
                
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // Async/await version
    public func fetchUserProfile(
        userId: String,
        cachePolicy: KitCachePolicy = .networkOnly
    ) async throws -> UserProfile {
        let query = GetUserProfileQuery(userId: userId)
        let result = try await graphQLService.fetch(query: query, cachePolicy: cachePolicy)
        
        guard let user = result.data?.user else {
            if let errors = result.errors {
                throw GraphQLError.serverErrors(errors)
            }
            throw GraphQLError.noData
        }
        
        return mapToUserProfile(user)
    }
    
    private func mapToUserProfile(_ user: GetUserProfileQuery.Data.User) -> UserProfile {
        // Map GraphQL response to your domain model
        return UserProfile(
            id: user.id,
            name: user.name,
            email: user.email
            // ... other mappings
        )
    }
}
```

### Implementation Examples with Kit Architecture

#### 1. Network-First Request (Initial Load)

```swift
// In your ViewController or View Model
class HomeViewController: UIViewController {
    private let userController: UserController
    
    override func viewDidLoad() {
        super.viewDidLoad()
        loadInitialData()
    }
    
    private func loadInitialData() {
        // Always fetch fresh data on app launch using networkOnly
        userController.fetchUserProfile(
            userId: currentUserId,
            cachePolicy: .networkOnly
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let userProfile):
                    self?.displayUserProfile(userProfile)
                case .failure(let error):
                    self?.handleError(error)
                }
            }
        }
        
        // Async/await version
        Task {
            do {
                let userProfile = try await userController.fetchUserProfile(
                    userId: currentUserId,
                    cachePolicy: .networkOnly
                )
                await MainActor.run {
                    displayUserProfile(userProfile)
                }
            } catch {
                await MainActor.run {
                    handleError(error)
                }
            }
        }
    }
}
```

#### 2. Cache-First Request (Navigation to Detail)

```swift
class UserDetailViewController: UIViewController {
    private let userController: UserController
    var userId: String!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        loadUserDetails()
    }
    
    private func loadUserDetails() {
        // Use cache-first for navigation between screens
        userController.fetchUserDetails(
            userId: userId,
            cachePolicy: .cacheFirst
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let userDetails):
                    self?.displayUserDetails(userDetails)
                case .failure(let error):
                    self?.handleError(error)
                }
            }
        }
    }
}
```

#### 3. Cache-Only Request (Offline Mode)

```swift
extension UserController {
    public func getCachedUserData(
        userId: String,
        completion: @escaping (Result<UserProfile?, Error>) -> Void
    ) {
        fetchUserProfile(
            userId: userId,
            cachePolicy: .cacheOnly
        ) { result in
            switch result {
            case .success(let userProfile):
                completion(.success(userProfile))
            case .failure:
                // Cache miss - return nil instead of error for offline scenarios
                completion(.success(nil))
            }
        }
    }
}

// Usage in ViewController
private func loadOfflineData() {
    userController.getCachedUserData(userId: currentUserId) { [weak self] result in
        DispatchQueue.main.async {
            switch result {
            case .success(let userProfile):
                if let profile = userProfile {
                    self?.displayCachedUser(profile)
                } else {
                    self?.showNoDataMessage()
                }
            case .failure(let error):
                self?.handleError(error)
            }
        }
    }
}
```

## Handling Objects Without Unique IDs

When GraphQL objects don't have unique identifiers, you need custom cache key strategies:

### Strategy 1: Use Alternative Unique Fields

```swift
store.cacheKeyForObject = { object, variables in
    if let id = object["id"] as? String {
        return "\(object["__typename"] as? String ?? "Unknown"):\(id)"
    }
    
    // Handle User objects with email as unique identifier
    if let email = object["email"] as? String,
       let typename = object["__typename"] as? String,
       typename == "User" {
        return "User:email:\(email)"
    }
    
    // Handle Setting objects with key as unique identifier
    if let key = object["key"] as? String,
       let typename = object["__typename"] as? String,
       typename == "Setting" {
        return "Setting:key:\(key)"
    }
    
    // Objects without unique identifiers won't be normalized
    return nil
}
```

### Strategy 2: Composite Keys

```swift
store.cacheKeyForObject = { object, variables in
    let typename = object["__typename"] as? String ?? "Unknown"
    
    if let id = object["id"] as? String {
        return "\(typename):\(id)"
    }
    
    // For objects like UserPreference that might have userId + preferenceType
    if typename == "UserPreference",
       let userId = object["userId"] as? String,
       let prefType = object["preferenceType"] as? String {
        return "UserPreference:\(userId):\(prefType)"
    }
    
    return nil
}
```

### Strategy 3: Query-Specific Caching

For objects that truly can't be uniquely identified, consider query-specific caching:

```swift
// This won't be normalized but will be cached per query
func fetchRecentActivity() {
    ApolloManager.shared.apollo.fetch(
        query: GetRecentActivityQuery(),
        cachePolicy: .returnCacheDataElseFetch
    ) { result in
        // Handle result
        // Note: Individual activity items without IDs won't be normalized,
        // but the entire query result will be cached
    }
}
```

## Flow-Based Caching Scenarios

### Scenario 1: App Launch / Initial Screen

**Recommendation**: Always fetch fresh data using `networkOnly`

```swift
class HomeViewController: UIViewController {
    private let dashboardController: DashboardController
    private let userController: UserController
    
    override func viewDidLoad() {
        super.viewDidLoad()
        loadInitialData()
    }
    
    private func loadInitialData() {
        // Always fetch fresh data on app launch
        Task {
            async let dashboardTask = dashboardController.fetchDashboard(cachePolicy: .networkOnly)
            async let userTask = userController.fetchCurrentUser(cachePolicy: .networkOnly)
            
            do {
                let (dashboard, user) = try await (dashboardTask, userTask)
                await MainActor.run {
                    displayDashboard(dashboard)
                    displayUserInfo(user)
                }
            } catch {
                await MainActor.run {
                    handleError(error)
                }
            }
        }
    }
}
```

### Scenario 2: Pull-to-Refresh

**Recommendation**: Always fetch from network using `networkOnly`

```swift
@objc private func refreshData() {
    refreshControl.beginRefreshing()
    
    dashboardController.fetchDashboard(cachePolicy: .networkOnly) { [weak self] result in
        DispatchQueue.main.async {
            self?.refreshControl.endRefreshing()
            
            switch result {
            case .success(let dashboard):
                self?.displayDashboard(dashboard)
            case .failure(let error):
                self?.handleError(error)
            }
        }
    }
}
```

### Scenario 3: Navigation to Detail Screens

**Recommendation**: Cache-first approach using `cacheFirst`

```swift
func navigateToUserDetail(userId: String) {
    let detailVC = UserDetailViewController()
    detailVC.userId = userId
    detailVC.userController = userController
    
    navigationController?.pushViewController(detailVC, animated: true)
}

// In UserDetailViewController
class UserDetailViewController: UIViewController {
    var userController: UserController!
    var userId: String!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        loadUserDetails()
    }
    
    private func loadUserDetails() {
        // Pre-load with cache-first policy
        userController.fetchUserDetails(
            userId: userId,
            cachePolicy: .cacheFirst
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let userDetails):
                    self?.displayUserDetails(userDetails)
                case .failure(let error):
                    self?.handleError(error)
                }
            }
        }
    }
}
```

### Scenario 4: Background App Return

**Recommendation**: Cache-first with background refresh using `cacheAndNetwork`

```swift
func applicationDidBecomeActive(_ application: UIApplication) {
    // Show cached data immediately, then refresh in background
    loadDashboard(cachePolicy: .cacheAndNetwork)
}

private func loadDashboard(cachePolicy: KitCachePolicy) {
    dashboardController.fetchDashboard(cachePolicy: cachePolicy) { [weak self] result in
        DispatchQueue.main.async {
            switch result {
            case .success(let dashboard):
                self?.displayDashboard(dashboard)
            case .failure(let error):
                // Handle error, but don't show to user if we already have cached data
                if cachePolicy == .cacheAndNetwork {
                    print("Background refresh failed: \(error)")
                } else {
                    self?.handleError(error)
                }
            }
        }
    }
}

## Cache Management

### Exposing Cache Management in APICoreKit

```swift
// In APICoreKit
public class GraphQLService {
    private let apolloClient: ApolloClient
    
    // ... existing code ...
    
    public func clearCache(completion: @escaping (Result<Void, Error>) -> Void) {
        apolloClient.clearCache { result in
            completion(result)
        }
    }
    
    public func clearCache() async throws {
        try await withCheckedThrowingContinuation { continuation in
            apolloClient.clearCache { result in
                continuation.resume(with: result)
            }
        }
    }
    
    public func removeObject(forKey key: String, completion: @escaping (Result<Void, Error>) -> Void) {
        apolloClient.store.removeObject(forKey: key) { result in
            completion(result)
        }
    }
}
```

### Kit-Level Cache Management

```swift
// In your Auth/Session Kit
public class AuthController {
    private let graphQLService: GraphQLService
    
    public init(graphQLService: GraphQLService) {
        self.graphQLService = graphQLService
    }
    
    public func logout() async throws {
        // Clear authentication tokens
        try AuthTokenManager.shared.clearTokens()
        
        // Clear Apollo cache
        try await graphQLService.clearCache()
        
        // Navigate to login
        await MainActor.run {
            NotificationCenter.default.post(name: .userDidLogout, object: nil)
        }
    }
}

// In your User Kit
public class UserController {
    private let graphQLService: GraphQLService
    
    public func clearUserCache(userId: String) async throws {
        let userKey = "User:\(userId)"
        try await graphQLService.removeObject(forKey: userKey)
    }
}
```

### Clearing Cache on Logout

```swift
// In your main app coordinator or scene delegate
class AppCoordinator {
    private let authController: AuthController
    
    init() {
        // Initialize with shared GraphQL service
        let apolloManager = ApolloManager.shared
        self.authController = AuthController(graphQLService: apolloManager.graphQLService)
        
        setupNotifications()
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLogout),
            name: .userDidLogout,
            object: nil
        )
    }
    
    @objc private func handleLogout() {
        // Navigate to login screen
        DispatchQueue.main.async {
            self.showLoginScreen()
        }
    }
}

// Usage in logout flow
class SettingsViewController: UIViewController {
    private let authController: AuthController
    
    @IBAction private func logoutTapped() {
        Task {
            do {
                try await authController.logout()
                // Navigation handled by notification
            } catch {
                await MainActor.run {
                    showError("Logout failed: \(error.localizedDescription)")
                }
            }
        }
    }
}
```

### Selective Cache Clearing

```swift
// Extend UserController for selective cache management
extension UserController {
    public func clearUserCache(userId: String) async throws {
        let userKey = "User:\(userId)"
        try await graphQLService.removeObject(forKey: userKey)
    }
    
    public func clearAllUserCaches(userIds: [String]) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for userId in userIds {
                group.addTask {
                    try await self.clearUserCache(userId: userId)
                }
            }
            
            try await group.waitForAll()
        }
    }
}
```

## Advanced Considerations

### What We're Not Covering (But Available for Advanced Use Cases)

This guide focuses on normalized caching for queries. Apollo iOS also supports advanced caching features that can be implemented when your app requirements grow beyond basic query caching:

#### Mutation Caching

Handle cache updates during mutations with optimistic updates and automatic cache synchronization:

```swift
// In APICoreKit - extend GraphQLService
public func perform<Mutation: GraphQLMutation>(
    mutation: Mutation,
    optimisticResponse: Mutation.Data? = nil,
    completion: @escaping (Result<GraphQLResult<Mutation.Data>, Error>) -> Void
) {
    apolloClient.perform(
        mutation: mutation,
        optimisticResponse: optimisticResponse
    ) { result in
        completion(result)
    }
}

// Usage in Kit Controller
func updateUserProfile(
    userId: String,
    name: String,
    optimistic: Bool = true
) async throws -> UserProfile {
    let mutation = UpdateUserProfileMutation(userId: userId, name: name)
    
    let optimisticResponse = optimistic ? 
        UpdateUserProfileMutation.Data(
            updateUser: .init(id: userId, name: name, __typename: "User")
        ) : nil
    
    let result = try await graphQLService.perform(
        mutation: mutation,
        optimisticResponse: optimisticResponse
    )
    
    guard let updatedUser = result.data?.updateUser else {
        throw GraphQLError.noData
    }
    
    return mapToUserProfile(updatedUser)
}
```

#### Direct Cache Access

Read and write specific objects directly to/from cache without network requests:

```swift
// In APICoreKit - extend GraphQLService
public func readCache<Query: GraphQLQuery>(
    query: Query
) throws -> Query.Data? {
    return try apolloClient.store.load(query: query).get()
}

public func writeCache<Query: GraphQLQuery>(
    query: Query,
    data: Query.Data
) throws {
    try apolloClient.store.publish(records: RecordSet(records: []), context: nil).get()
}

// Usage in Kit Controller
func getCachedUserProfile(userId: String) throws -> UserProfile? {
    let query = GetUserProfileQuery(userId: userId)
    
    guard let cachedData = try graphQLService.readCache(query: query),
          let user = cachedData.user else {
        return nil
    }
    
    return mapToUserProfile(user)
}

func updateCachedUserProfile(_ userProfile: UserProfile) throws {
    let query = GetUserProfileQuery(userId: userProfile.id)
    let userData = GetUserProfileQuery.Data.User(
        id: userProfile.id,
        name: userProfile.name,
        email: userProfile.email
    )
    let data = GetUserProfileQuery.Data(user: userData)
    
    try graphQLService.writeCache(query: query, data: data)
}
```

#### Cache Transactions

Perform batch operations for complex cache updates atomically:

```swift
// In APICoreKit - extend GraphQLService
public func performCacheTransaction<T>(
    operation: @escaping (inout RecordSet) throws -> T
) throws -> T {
    return try apolloClient.store.withinReadWriteTransaction { transaction in
        var recordSet = RecordSet()
        let result = try operation(&recordSet)
        try transaction.addRecords(from: recordSet)
        return result
    }.get()
}

// Usage in Kit Controller for bulk operations
func updateMultipleUsers(_ users: [UserProfile]) throws {
    try graphQLService.performCacheTransaction { recordSet in
        for user in users {
            let userRecord = Record(
                key: "User:\(user.id)",
                fields: [
                    "id": user.id,
                    "name": user.name,
                    "email": user.email,
                    "__typename": "User"
                ]
            )
            recordSet.merge(record: userRecord)
        }
    }
}
```

#### Custom Cache Implementations

Build your own cache storage layer for specific requirements:

```swift
// Custom cache implementation
public class HybridNormalizedCache: NormalizedCache {
    private let memoryCache: InMemoryNormalizedCache
    private let persistentCache: SQLNormalizedCache
    
    public init(persistentCacheURL: URL) throws {
        self.memoryCache = InMemoryNormalizedCache()
        self.persistentCache = try SQLNormalizedCache(fileURL: persistentCacheURL)
    }
    
    public func loadRecords(forKeys keys: Set<CacheKey>) throws -> [CacheKey: Record] {
        // Try memory first, fallback to persistent
        let memoryRecords = try memoryCache.loadRecords(forKeys: keys)
        let missingKeys = Set(keys.filter { memoryRecords[$0] == nil })
        
        if !missingKeys.isEmpty {
            let persistentRecords = try persistentCache.loadRecords(forKeys: missingKeys)
            // Update memory cache with persistent data
            try memoryCache.merge(records: persistentRecords)
            return memoryRecords.merging(persistentRecords) { $1 }
        }
        
        return memoryRecords
    }
    
    public func merge(records: RecordSet) throws -> Set<CacheKey> {
        // Write to both caches
        let memoryKeys = try memoryCache.merge(records: records)
        let persistentKeys = try persistentCache.merge(records: records)
        return memoryKeys.union(persistentKeys)
    }
}

// Usage in ApolloManager
private func createCustomCache() -> NormalizedCache {
    let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
    let databaseURL = URL(fileURLWithPath: documentsPath).appendingPathComponent("hybrid_cache.sqlite")
    
    return try! HybridNormalizedCache(persistentCacheURL: databaseURL)
}
```

#### Subscription Caching

Handle real-time data updates through subscriptions with automatic cache updates:

```swift
// In APICoreKit - extend GraphQLService
public func subscribe<Subscription: GraphQLSubscription>(
    subscription: Subscription,
    completion: @escaping (Result<GraphQLResult<Subscription.Data>, Error>) -> Void
) -> Cancellable {
    return apolloClient.subscribe(subscription: subscription) { result in
        completion(result)
    }
}

// Usage in Kit Controller
private var subscriptionCancellable: Cancellable?

func subscribeToUserUpdates(userId: String) {
    let subscription = UserUpdatedSubscription(userId: userId)
    
    subscriptionCancellable = graphQLService.subscribe(subscription: subscription) { result in
        switch result {
        case .success(let graphQLResult):
            if let updatedUser = graphQLResult.data?.userUpdated {
                // Cache is automatically updated by Apollo
                DispatchQueue.main.async {
                    self.handleUserUpdate(updatedUser)
                }
            }
        case .failure(let error):
            print("Subscription error: \(error)")
        }
    }
}

deinit {
    subscriptionCancellable?.cancel()
}
```

#### Cache Eviction Policies

Implement custom cache eviction strategies for memory management:

```swift
// Custom cache with LRU eviction
public class LRUNormalizedCache: NormalizedCache {
    private let maxSize: Int
    private var accessOrder: [CacheKey] = []
    private let baseCache: InMemoryNormalizedCache
    
    public init(maxSize: Int = 1000) {
        self.maxSize = maxSize
        self.baseCache = InMemoryNormalizedCache()
    }
    
    public func loadRecords(forKeys keys: Set<CacheKey>) throws -> [CacheKey: Record] {
        let records = try baseCache.loadRecords(forKeys: keys)
        
        // Update access order
        for key in keys {
            if let index = accessOrder.firstIndex(of: key) {
                accessOrder.remove(at: index)
            }
            accessOrder.append(key)
        }
        
        return records
    }
    
    public func merge(records: RecordSet) throws -> Set<CacheKey> {
        let changedKeys = try baseCache.merge(records: records)
        
        // Evict least recently used items if over limit
        while accessOrder.count > maxSize {
            let oldestKey = accessOrder.removeFirst()
            try baseCache.removeRecord(for: oldestKey)
        }
        
        return changedKeys
    }
}
```

These advanced features provide powerful capabilities for complex caching scenarios, optimistic UI updates, real-time data synchronization, and custom cache behaviors. They can be gradually adopted as your application's caching requirements become more sophisticated.

### Performance Tips

1. **Use Persistent Cache for Production**: SQLite cache survives app restarts
2. **Monitor Cache Size**: Implement cache size limits for memory management
3. **Strategic Cache Clearing**: Clear cache selectively rather than entirely when possible
4. **Background Refresh**: Use `returnCacheDataAndFetch` for perceived performance

### Debugging Cache Issues

```swift
// Enable Apollo debug logging
#if DEBUG
apollo.store.cacheKeyForObject = { object, variables in
    let key = // your cache key logic
    print("Cache key for \(object): \(key ?? "nil")")
    return key
}
#endif
```

## Best Practices Summary

- **Start flows with network-first** requests for fresh data
- **Use cache-first for navigation** between screens
- **Always use network-only for refresh** actions
- **Clear cache completely on logout**
- **Implement proper cache key resolution** for all cached objects
- **Handle objects without IDs** using alternative unique fields
- **Keep normalized caching simple** - avoid complex cache transactions initially
- **Monitor and debug cache behavior** during development

This approach provides excellent user experience with fast navigation while ensuring data freshness when needed.
