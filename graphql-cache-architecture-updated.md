# GraphQL Cache Management Architecture
## MIB Native iOS

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Current State Analysis](#current-state-analysis)
3. [GraphQL vs REST Caching](#graphql-vs-rest-caching)
4. [Apollo Query-Based Caching](#apollo-query-based-caching)
5. [MIB Integration with Feature Kits](#mib-integration-with-feature-kits)
6. [Cache Timeout Implementation](#cache-timeout-implementation)
7. [Mutation Handling Strategies](#mutation-handling-strategies)
8. [Normalized Cache with Custom Keys](#normalized-cache-with-custom-keys)
9. [Cache Clearing Scenarios](#cache-clearing-scenarios)
10. [Unified Cache Manager](#unified-cache-manager)
11. [Recommendations](#recommendations)

---

## Executive Summary

**Purpose:** This document gathers current cache management practices in MIB Native iOS under REST APIs, defines requirements for GraphQL cache management, and provides architectural options to help stakeholders make informed decisions on how to move forward.

**What This Document Covers:**
- Analysis of existing REST API cache implementation
- GraphQL cache behavior and requirements
- Apollo's query-based caching mechanism
- MIB to Feature Kit integration with caching policies
- Cache timeout strategies (global and per-query)
- Mutation handling with refetch strategies
- Normalized cache implementation with custom keys
- Cache clearing scenarios and strategies
- Architectural recommendations for unified cache management
- Security and compliance considerations
- Implementation roadmap

**Key Findings:**
- Current implementation uses NSCache for REST with 15+ granular cache clearing methods
- GraphQL (Apollo iOS 1.21.0) uses query-based caching by default without custom configuration
- Each query is cached independently - updating one query doesn't automatically update others
- MIB will call use cases in Feature Kits with configurable caching policies
- Financial data security requires clearing all caches on logout
- Two mutation strategies available: automatic refetch and optimized refetch with normalized cache

**Decision Points for Stakeholders:**
1. Mutation cache strategy: Basic refetch vs. normalized cache with optimized updates
2. Cache timeout policy: Global default vs. per-query configuration
3. Custom key implementation: Enable normalized object-based caching
4. Cache manager design: Unified interface for REST and GraphQL
5. Implementation timeline and rollout approach

---

## Current State Analysis

> **📄 Detailed Analysis:** For comprehensive implementation details, code examples, and flow diagrams of the current REST cache system, see the separate **[Current State Analysis Document](current-state-analysis.md)**.

This section provides a high-level overview of existing cache architecture patterns.

---

### Architecture Overview

MIB Native iOS uses a **multi-layered caching architecture** across two systems:

**1. NABAPICoreKit Cache System** (Technical Implementation)
```
Feature Kits (CardsKit, PaymentKit, etc.)
    ↓ defines cache requirements
Repository/Service Layer
    ↓ checks cache, stores responses
Cache Managers (CacheManager, CachedRequestStateManager)
    ↓ NSCache storage, expiry checking
Network Layer (HTTPClient)
    (no caching logic)
```

**2. App-Level CacheManager** (UI Cache Clearing)
```
Controllers/ViewModels
    ↓ trigger cache clearing
CacheManager (15+ specific methods)
    ↓ coordinates clearing
Various Caches
    ↓ actual clear operations
```

---

### Key Components

#### NABAPICoreKit Cache (Technical)

**Core Infrastructure:**
- `CacheManager` - NSCache-based storage with expiry mechanism
- `CachedRequestStateManager` - In-flight request deduplication
- `Caching` protocol - Standard cache operations

**Per-Request Configuration:**
```swift
struct CardListRequest: RequestType {
    let cache: Cache?
    
    struct Cache: Cacheable {
        let key: String               // "cardsExperienceV3.page_1.key"
        let timeout: Timeout          // .seconds(300) or .never
        let isUpliftedCache: Bool     // false (regular cache)
    }
}
```

**Service Layer Pattern:**
```swift
// Service checks cache before network
public func perform<T>(with request: T) async -> Result<T.Response, API<T.Error>> {
    // 1. Check cache
    if let response = cache.getCache(for: request) {
        return .success(response)
    }
    
    // 2. Network call
    let result = await client.performTask(with: request)
    
    // 3. Store on success
    if case .success(let response) = result {
        cache.store(response: response, for: request)
    }
    
    return result
}
```

#### App-Level CacheManager (UI Clearing)

```swift
protocol CacheManaging {
    func clearCache()
    func clearCache(forAccountToken: String)
    func clearCache(forAccountId: String)
    func clearBalancesCache()
    func clearCacheForPaymentListOnly()
    // ... 15+ controller-specific methods
}
```

**Key Point:** This handles **UI-level cache clearing triggers** (logout, refresh) but doesn't manage the actual REST response caching.

---

### Current Logout Flow

```swift
func cleanup() {
    // Clear UI-level caches
    cacheManager.clearCache()
    
    // Clear WebView caches
    internetBankingCacheManager.clearCache()
    internetBankingCacheManager.clearCookie()
    
    // ⚠️ Problem: GraphQL cache NOT cleared
}
```

---

### Settings.bundle Configuration

**Developer Controls (Non-Release Builds):**
```
Settings.bundle/Cache.plist:
├── Account Summary: [Never, Always, Custom, Default]
├── Balances: [Never, Always, Custom, Default]
├── Transaction History: [Never, Always, Custom, Default]
├── Cards Experience: [Never, Always, Custom, Default]
└── ... 15+ feature-specific cache settings

Options:
- Never: Always fetch from network
- Always: Cache indefinitely
- Custom: Expiry in seconds (e.g., 300)
- Default: Application-defined default
```

---

### Current GraphQL Implementation

**Apollo Setup:**
```swift
let cache = InMemoryNormalizedCache()
let store = ApolloStore(cache: cache)
let client = ApolloClient(networkTransport: transport, store: store)
```

**Current Configuration:**
- Library: Apollo iOS 1.21.0
- Cache: InMemoryNormalizedCache
- Default Policy: `.returnCacheDataElseFetch` (cache first)
- No timeout mechanism
- No logout integration
- No mutation strategies
- No custom cache keys configured

---

### Identified Gaps

| Gap | Impact | Priority |
|-----|--------|----------|
| GraphQL cache not cleared on logout | **Critical** | **P0** |
| No timeout/staleness policy | High | P0 |
| No mutation cache invalidation | High | P0 |
| Query-based caching causes duplication | Medium | P1 |
| No per-query cache policies | Medium | P1 |
| No unified cache clearing interface | High | P0 |
| No custom cache keys for normalization | High | P1 |

---

### Cache Characteristics Comparison

| Aspect | REST (NABAPICoreKit) | GraphQL (Apollo) |
|--------|---------------------|------------------|
| **Storage** | NSCache (in-memory) | InMemoryNormalizedCache |
| **Location** | Repository/Service layer | Apollo Client |
| **Configuration** | Per-request via `Cacheable` | Default (no customization) |
| **Expiry** | Timeout-based checking | None configured |
| **Cache Key** | `"feature.identifier.key"` | Query + variables (default) |
| **Normalization** | Not applicable | Possible with custom keys |
| **Deduplication** | ✅ In-flight tracking | ✅ Built-in |
| **Logout Clearing** | ✅ Integrated | ❌ **Missing** |
| **Persistence** | None (memory only) | None (memory only) |

---

## GraphQL vs REST Caching

Understanding the fundamental differences between REST and GraphQL caching is crucial for implementing an effective cache strategy in MIB Native iOS.

---

### REST API Caching Model

**How REST Caching Works:**

REST APIs cache responses based on **URL + HTTP method + headers**. Each endpoint represents a specific resource or collection.

```swift
// Example: REST endpoint caching
GET /api/accounts/123/balance
Response: { "accountId": "123", "balance": 5000.00 }
Cache Key: "accounts.123.balance"

GET /api/accounts/123
Response: { "accountId": "123", "name": "Savings", "balance": 5000.00 }
Cache Key: "accounts.123.details"
```

**REST Characteristics:**
- ✅ Simple URL-based cache keys
- ✅ One endpoint = one cache entry
- ✅ Easy to implement cache invalidation by URL
- ❌ Over-fetching (getting more data than needed)
- ❌ Multiple endpoints for related data
- ❌ No automatic data relationships

---

### GraphQL Caching Model

**How GraphQL Caching Works:**

GraphQL can cache in two ways:

1. **Query-Based Caching (Apollo Default)**
   - Each unique query + variables combination is cached as a complete unit
   - Similar to REST URL-based caching
   - Simple but can lead to data duplication

2. **Normalized Object Caching (With Custom Keys)**
   - Individual objects are cached by their unique identifiers
   - Queries reference cached objects
   - Updating an object updates all queries that reference it

```swift
// Example: GraphQL query caching
query GetAccountBalance($accountId: ID!) {
  account(id: $accountId) {
    id
    balance
  }
}
Cache Key (Query-Based): "GetAccountBalance:{"accountId":"123"}"
Cache Key (Normalized): "Account:123"
```

**GraphQL Characteristics:**
- ✅ Fetch exactly what you need
- ✅ Single endpoint for all queries
- ✅ Flexible data fetching
- ✅ Built-in caching support
- ❌ More complex cache invalidation
- ❌ Requires cache key configuration for normalization
- ⚠️ Query-based caching can duplicate data across queries

---

### Key Differences Summary

| Aspect | REST | GraphQL (Query-Based) | GraphQL (Normalized) |
|--------|------|----------------------|---------------------|
| **Cache Granularity** | Per endpoint | Per query + variables | Per object |
| **Data Duplication** | High (separate endpoints) | Medium (separate queries) | Low (shared objects) |
| **Cache Key** | URL | Query name + variables | Type + ID |
| **Invalidation** | Clear by URL pattern | Clear specific queries | Update object once |
| **Setup Complexity** | Low | Low | Medium |
| **Query Relationship** | None | Independent | Shared objects |

---

### Why This Matters for MIB

**Current Challenge:**
```swift
// Scenario: User checks balance, then views account details

// Query 1: Balance
query GetBalance($id: ID!) {
  account(id: $id) { balance }
}
// Cached as: "GetBalance:{"id":"123"}" → { balance: 5000 }

// Query 2: Account details
query GetAccount($id: ID!) {
  account(id: $id) { id, name, balance, type }
}
// Cached as: "GetAccount:{"id":"123"}" → { id, name, balance, type }

// Problem: Balance is now stored in TWO separate cache entries
// If balance updates, both queries need separate invalidation
```

**Solution Options:**

**Option 1: Query-Based Caching (Current/Simple)**
- Pros: Works out of the box, easy to understand
- Cons: Data duplication, manual invalidation needed
- Use Case: Quick implementation, simpler data models

**Option 2: Normalized Caching (Recommended)**
- Pros: No duplication, automatic updates, efficient
- Cons: Requires custom key configuration
- Use Case: Complex data models, frequent updates

---

## Apollo Query-Based Caching

### Understanding Apollo's Default Behavior

Apollo GraphQL uses **query-based caching** by default (without custom cache key configuration). This means each GraphQL query result is cached as a complete, independent unit - similar to how REST APIs cache responses by URL.

**Critical Concept:** Unlike normalized object caching, query-based caching treats each query as a separate cache entry. **Updating one query does NOT automatically update other queries**, even if they fetch overlapping data.

---

### How Query-Based Caching Works

When Apollo caches a query, it creates a cache key by combining:
1. The query operation name
2. The query variables
3. A hash of the query structure

```swift
// Cache key formula
cacheKey = "\(queryName):\(variables.sorted().jsonString)"

// Example
query: GetAccountBalance
variables: { "accountId": "123" }
cacheKey: "GetAccountBalance:{"accountId":"123"}"
```

---

### Detailed Example: Account Balance Queries

Let's examine what happens when multiple queries fetch related data:

#### Example 1: Independent Query Caching

```swift
// ==========================================
// Query A: Get account balance only
// ==========================================
let queryA = GetAccountBalanceQuery(accountId: "123")

apollo.fetch(query: queryA, cachePolicy: .returnCacheDataElseFetch) { result in
    // Result: { account: { balance: 5000 } }
    // 
    // Cache Entry Created:
    // Key: "GetAccountBalanceQuery:{"accountId":"123"}"
    // Value: { account: { balance: 5000 } }
}

// ==========================================
// Query B: Get account details (includes balance)
// ==========================================
let queryB = GetAccountDetailsQuery(accountId: "123")

apollo.fetch(query: queryB, cachePolicy: .returnCacheDataElseFetch) { result in
    // Result: { account: { id: "123", name: "Savings", balance: 5000, type: "SAVINGS" } }
    // 
    // Cache Entry Created:
    // Key: "GetAccountDetailsQuery:{"accountId":"123"}"
    // Value: { account: { id: "123", name: "Savings", balance: 5000, type: "SAVINGS" } }
}

// ⚠️ PROBLEM: Balance is now cached in TWO separate locations
// Query A cache: { balance: 5000 }
// Query B cache: { balance: 5000 }
```

#### Example 2: Why Updates Don't Propagate

```swift
// ==========================================
// User makes a payment - balance changes
// ==========================================
let mutation = MakePaymentMutation(amount: 1000)

apollo.perform(mutation: mutation) { result in
    // Server response: { newBalance: 4000 }
    
    // ❌ PROBLEM: Cached queries are NOT automatically updated
    
    // Query A cache still shows: { balance: 5000 }
    // Query B cache still shows: { balance: 5000 }
    // 
    // Even though the actual balance is now 4000!
}

// ==========================================
// Fetching Query A again
// ==========================================
apollo.fetch(query: queryA, cachePolicy: .returnCacheDataElseFetch) { result in
    // Returns STALE data from cache: { balance: 5000 }
    // Does NOT fetch from server because cache exists
}

// ==========================================
// To get fresh data, must use different cache policy
// ==========================================
apollo.fetch(query: queryA, cachePolicy: .fetchIgnoringCacheData) { result in
    // Ignores cache, fetches from server
    // Returns fresh data: { balance: 4000 }
    // Updates cache entry for Query A
    // 
    // ⚠️ But Query B cache is STILL showing: { balance: 5000 }
}
```

#### Example 3: Multiple Queries with Same Data

```swift
// Dashboard screen shows multiple components
// Each fetches account data independently

// Component 1: Balance widget
let balanceQuery = GetBalanceQuery(accountId: "123")
// Cache: "GetBalanceQuery:{"accountId":"123"}" → { balance: 5000 }

// Component 2: Account card
let accountQuery = GetAccountQuery(accountId: "123")
// Cache: "GetAccountQuery:{"accountId":"123"}" → { id, name, balance: 5000 }

// Component 3: Transaction list (also shows balance)
let transactionsQuery = GetTransactionsQuery(accountId: "123")
// Cache: "GetTransactionsQuery:{"accountId":"123"}" → { transactions: [...], balance: 5000 }

// ⚠️ RESULT: Balance is cached in THREE different places
// Any update requires invalidating ALL three cache entries
```

---

### Why This Behavior Exists

Query-based caching is Apollo's **default** for several reasons:

1. **Zero Configuration Required**
   - Works immediately without custom setup
   - No need to define cache keys

2. **Predictable Behavior**
   - Each query is self-contained
   - Easy to reason about cache state

3. **No Assumptions About Data Structure**
   - Works with any GraphQL schema
   - Doesn't require knowledge of object relationships

---

### The Problem for MIB

Query-based caching creates challenges for financial applications:

**1. Data Inconsistency Risk**
```swift
// User sees different balances in different parts of the app
// Dashboard: 5000 (from cached Query A)
// Detail page: 4000 (fresh from Query B)
// ⚠️ Confusing and potentially misleading for users
```

**2. Manual Cache Management Burden**
```swift
// After every mutation, must explicitly refetch ALL related queries
apollo.perform(mutation: paymentMutation) { _ in
    apollo.fetch(query: balanceQuery, cachePolicy: .fetchIgnoringCacheData)
    apollo.fetch(query: accountQuery, cachePolicy: .fetchIgnoringCacheData)
    apollo.fetch(query: transactionsQuery, cachePolicy: .fetchIgnoringCacheData)
    apollo.fetch(query: dashboardQuery, cachePolicy: .fetchIgnoringCacheData)
    // Must remember ALL queries that show this data
}
```

**3. Cache Memory Overhead**
```swift
// Same account data cached multiple times
// Memory usage: 3× (or more) for frequently accessed data
```

---

### Cache Policy Impact

Apollo provides different cache policies that control how query-based caching behaves:

```swift
// 1. returnCacheDataElseFetch (Default - Cache First)
//    Returns cached data if available, otherwise fetches
//    ✅ Fast for repeated queries
//    ❌ May return stale data

// 2. fetchIgnoringCacheData (Network Only)
//    Always fetches from server, ignores cache
//    ✅ Always fresh data
//    ❌ Slower, uses more network

// 3. returnCacheDataAndFetch (Cache Then Network)
//    Returns cache immediately, then fetches and updates
//    ✅ Fast initial response + fresh data
//    ❌ UI may update twice

// 4. returnCacheDataDontFetch (Cache Only)
//    Only returns cached data, never fetches
//    ✅ Instant, no network usage
//    ❌ Never updates

// 5. fetchIgnoringCacheCompletely (No Cache)
//    Fetches from server and doesn't cache result
//    ✅ Always fresh, no cache pollution
//    ❌ No benefit from caching
```

---

### Real-World Scenario

```swift
// Timeline of events:

// 1. User opens app → Dashboard loads
apollo.fetch(query: GetDashboardQuery(), cachePolicy: .returnCacheDataElseFetch)
// Cache: "GetDashboardQuery:{}" → { accounts: [...], totalBalance: 50000 }

// 2. User navigates to account details
apollo.fetch(query: GetAccountQuery(accountId: "123"), cachePolicy: .returnCacheDataElseFetch)
// Cache: "GetAccountQuery:{"accountId":"123"}" → { account details... balance: 5000 }

// 3. User makes a payment of $1000
apollo.perform(mutation: MakePaymentMutation(amount: 1000))
// Server updates balance to 4000

// 4. User navigates back to dashboard
apollo.fetch(query: GetDashboardQuery(), cachePolicy: .returnCacheDataElseFetch)
// ⚠️ Returns CACHED data showing totalBalance: 50000 (STALE!)
// ⚠️ Should show 49000 but cache wasn't invalidated

// 5. User pulls to refresh
apollo.fetch(query: GetDashboardQuery(), cachePolicy: .fetchIgnoringCacheData)
// ✅ Fetches fresh data, updates cache to show 49000
// But other queries (e.g., GetAccountQuery) still show old balance!
```

---

### Summary: Key Takeaways

1. **Apollo's default caching is query-based** - each query is cached independently
2. **Queries don't share data** - even if they fetch the same objects
3. **Updates require manual propagation** - changing one query doesn't affect others
4. **Cache invalidation must be explicit** - need to refetch or clear related queries
5. **Memory overhead** - same data may be cached multiple times
6. **Risk of inconsistent UI** - different parts of the app may show different values

**Next Steps:**
- Implement proper cache invalidation strategy (see Mutation Handling section)
- Consider normalized caching with custom keys (see Normalized Cache section)
- Define cache policies for different query types (see MIB Integration section)

---

## MIB Integration with Feature Kits

This section explains how MIB (Mobile Integration Bridge) coordinates GraphQL requests between the application layer and Feature Kits, including how caching policies are determined and applied.

---

### Architecture Flow

```
UI Layer (ViewModels/Controllers)
    ↓ Initiates action
MIB (Mobile Integration Bridge)
    ↓ Calls use case with cache policy
Feature Kit Use Case (e.g., AccountsKit, CardsKit)
    ↓ Executes GraphQL query via APICoreKit
APICoreKit
    ↓ Applies cache policy
Apollo Client
    ↓ Checks cache or fetches from network
GraphQL Server
```

---

### How MIB Calls Feature Kits

MIB acts as the coordination layer that calls use cases in Feature Kits. Each use case represents a specific business operation.

#### Basic Call Pattern

```swift
// MIB initiates a use case call
class DashboardViewModel {
    let accountsUseCase: GetAccountBalanceUseCase
    
    func loadBalance() async {
        // MIB calls Feature Kit use case
        let result = await accountsUseCase.execute(accountId: "123")
        
        switch result {
        case .success(let balance):
            updateUI(with: balance)
        case .failure(let error):
            handleError(error)
        }
    }
}
```

#### Feature Kit Use Case Implementation

```swift
// Feature Kit: AccountsKit
public protocol GetAccountBalanceUseCase {
    func execute(
        accountId: String,
        cachePolicy: GraphQLCachePolicy?
    ) async -> Result<AccountBalance, Error>
}

public class DefaultGetAccountBalanceUseCase: GetAccountBalanceUseCase {
    private let apiClient: GraphQLClient
    
    public init(apiClient: GraphQLClient) {
        self.apiClient = apiClient
    }
    
    public func execute(
        accountId: String,
        cachePolicy: GraphQLCachePolicy? = nil
    ) async -> Result<AccountBalance, Error> {
        let query = GetAccountBalanceQuery(accountId: accountId)
        
        // Use provided cache policy or fall back to default
        let policy = cachePolicy ?? .returnCacheDataElseFetch
        
        return await apiClient.fetch(
            query: query,
            cachePolicy: policy
        )
    }
}
```

---

### Cache Policy Configuration

#### Default Cache Policy: Cache First

By default, all GraphQL queries use the **cache-first** policy (`.returnCacheDataElseFetch`):

```swift
// Default behavior
public extension GraphQLCachePolicy {
    static var `default`: GraphQLCachePolicy {
        return .returnCacheDataElseFetch
    }
}

// Feature Kit use case uses default
public func execute(accountId: String) async -> Result<AccountBalance, Error> {
    // Implicitly uses .returnCacheDataElseFetch
    return await apiClient.fetch(query: query)
}
```

**Cache First Behavior:**
1. Check if query result exists in cache
2. If cached and not expired → return cached data (fast)
3. If not cached → fetch from network, cache result, return

**Benefits:**
- ✅ Fast response for repeated queries
- ✅ Reduces network calls
- ✅ Works offline (if data was previously cached)

**Trade-offs:**
- ⚠️ May return stale data
- ⚠️ Requires explicit refresh for fresh data

---

### When MIB Overrides Cache Policy

MIB can pass a different cache policy when fresh data is required:

#### Scenario 1: User-Initiated Refresh

```swift
class AccountDetailViewModel {
    let getAccountUseCase: GetAccountBalanceUseCase
    
    func loadBalance() async {
        // Initial load: use default cache policy (fast)
        let result = await getAccountUseCase.execute(
            accountId: "123"
            // cachePolicy is nil, uses default .returnCacheDataElseFetch
        )
        updateUI(with: result)
    }
    
    func refreshBalance() async {
        // Pull-to-refresh: force fresh data from network
        let result = await getAccountUseCase.execute(
            accountId: "123",
            cachePolicy: .fetchIgnoringCacheData  // ← MIB passes network-only policy
        )
        updateUI(with: result)
    }
}
```

#### Scenario 2: After Mutation

```swift
class PaymentViewModel {
    let makePaymentUseCase: MakePaymentUseCase
    let getBalanceUseCase: GetAccountBalanceUseCase
    
    func makePayment(amount: Decimal) async {
        // 1. Execute mutation
        let paymentResult = await makePaymentUseCase.execute(amount: amount)
        
        guard case .success = paymentResult else {
            handleError()
            return
        }
        
        // 2. Refetch balance with fresh data
        let balanceResult = await getBalanceUseCase.execute(
            accountId: "123",
            cachePolicy: .fetchIgnoringCacheData  // ← Ensure fresh data after mutation
        )
        
        updateUI(with: balanceResult)
    }
}
```

#### Scenario 3: Critical Operations

```swift
class TransferViewModel {
    let getAccountBalanceUseCase: GetAccountBalanceUseCase
    
    func validateSufficientFunds(amount: Decimal) async -> Bool {
        // For financial validation, always fetch fresh data
        let result = await getAccountBalanceUseCase.execute(
            accountId: sourceAccountId,
            cachePolicy: .fetchIgnoringCacheData  // ← Critical: must be accurate
        )
        
        guard case .success(let balance) = result else {
            return false
        }
        
        return balance.available >= amount
    }
}
```

---

### Complete Cache Policy Options

MIB can pass any of these policies based on requirements:

```swift
public enum GraphQLCachePolicy {
    // 1. returnCacheDataElseFetch (DEFAULT - Cache First)
    //    Use Case: Normal queries, dashboard loads
    //    Behavior: Return cache if available, else fetch
    case returnCacheDataElseFetch
    
    // 2. fetchIgnoringCacheData (Network Only)
    //    Use Case: Pull-to-refresh, after mutations, critical data
    //    Behavior: Always fetch from network, update cache
    case fetchIgnoringCacheData
    
    // 3. returnCacheDataAndFetch (Cache Then Network)
    //    Use Case: Show cache immediately, update in background
    //    Behavior: Return cache, then fetch and update
    case returnCacheDataAndFetch
    
    // 4. returnCacheDataDontFetch (Cache Only)
    //    Use Case: Offline mode, static data
    //    Behavior: Only return cached data, never fetch
    case returnCacheDataDontFetch
    
    // 5. fetchIgnoringCacheCompletely (No Cache)
    //    Use Case: Temporary data, one-time queries
    //    Behavior: Fetch without caching
    case fetchIgnoringCacheCompletely
}
```

---

### MIB Cache Policy Decision Matrix

This table helps MIB determine which cache policy to use:

| Scenario | Cache Policy | Reason |
|----------|-------------|--------|
| **Initial screen load** | `.returnCacheDataElseFetch` (default) | Fast response, reduce network calls |
| **User pulls to refresh** | `.fetchIgnoringCacheData` | User explicitly wants fresh data |
| **After successful mutation** | `.fetchIgnoringCacheData` | Ensure data reflects mutation result |
| **Background sync** | `.returnCacheDataAndFetch` | Update cache without blocking UI |
| **Offline mode** | `.returnCacheDataDontFetch` | Only show cached data |
| **Critical validation** | `.fetchIgnoringCacheData` | Accuracy is paramount |
| **Transient queries** | `.fetchIgnoringCacheCompletely` | Don't pollute cache |
| **Subsequent navigations** | `.returnCacheDataElseFetch` (default) | Use cache for speed |

---

### Implementation Example

```swift
// MIB Layer
class AccountCoordinator {
    let getAccountUseCase: GetAccountBalanceUseCase
    
    // Use case 1: Normal navigation (use cache)
    func showAccountDetails(accountId: String) async {
        let balance = await getAccountUseCase.execute(
            accountId: accountId
            // No cache policy = uses default cache-first
        )
        // Fast: Returns cached data if available
    }
    
    // Use case 2: User refresh (ignore cache)
    func refreshAccountDetails(accountId: String) async {
        let balance = await getAccountUseCase.execute(
            accountId: accountId,
            cachePolicy: .fetchIgnoringCacheData
        )
        // Fresh: Always fetches from server
    }
    
    // Use case 3: After payment (ignore cache)
    func handlePaymentCompletion(accountId: String) async {
        let balance = await getAccountUseCase.execute(
            accountId: accountId,
            cachePolicy: .fetchIgnoringCacheData
        )
        // Accurate: Reflects payment result
    }
}
```

---

### Feature Kit Responsibilities

Feature Kits must:

1. **Accept optional cache policy parameter**
   ```swift
   func execute(
       accountId: String,
       cachePolicy: GraphQLCachePolicy? = nil
   ) async -> Result<Data, Error>
   ```

2. **Use default policy when not specified**
   ```swift
   let policy = cachePolicy ?? .returnCacheDataElseFetch
   ```

3. **Pass policy to APICoreKit**
   ```swift
   return await apiClient.fetch(query: query, cachePolicy: policy)
   ```

4. **Document expected cache behavior**
   ```swift
   /// Fetches account balance.
   /// - Parameters:
   ///   - accountId: The account identifier
   ///   - cachePolicy: Cache policy to use. Defaults to `.returnCacheDataElseFetch`
   /// - Returns: Account balance or error
   /// - Note: Use `.fetchIgnoringCacheData` after mutations for fresh data
   ```

---

### APICoreKit Integration

APICoreKit wraps Apollo Client and applies the cache policy:

```swift
public protocol GraphQLClient {
    func fetch<Query: GraphQLQuery>(
        query: Query,
        cachePolicy: GraphQLCachePolicy?
    ) async -> Result<Query.Data, Error>
}

public class ApolloGraphQLClient: GraphQLClient {
    private let apollo: ApolloClient
    
    public func fetch<Query: GraphQLQuery>(
        query: Query,
        cachePolicy: GraphQLCachePolicy? = nil
    ) async -> Result<Query.Data, Error> {
        let policy = cachePolicy ?? .returnCacheDataElseFetch
        
        // Convert to Apollo cache policy
        let apolloPolicy: CachePolicy = policy.toApolloCachePolicy()
        
        return await withCheckedContinuation { continuation in
            apollo.fetch(
                query: query,
                cachePolicy: apolloPolicy
            ) { result in
                continuation.resume(returning: result.toResult())
            }
        }
    }
}
```

---

### Summary: MIB-Feature Kit Integration

1. **MIB initiates calls** to Feature Kit use cases
2. **Default cache policy** is cache-first (`.returnCacheDataElseFetch`)
3. **MIB can override** cache policy when fresh data is required
4. **Feature Kits accept** optional cache policy parameter
5. **APICoreKit applies** the cache policy to Apollo Client
6. **Common overrides:**
   - Pull-to-refresh → `.fetchIgnoringCacheData`
   - After mutations → `.fetchIgnoringCacheData`
   - Critical validations → `.fetchIgnoringCacheData`

This architecture provides flexibility while maintaining a sensible default that optimizes for performance.

---

## Cache Timeout Implementation

Cache timeout ensures that cached data doesn't become stale over time. This section explains how to implement both global and per-query timeout strategies for GraphQL queries.

---

### Why Cache Timeouts Matter

**Problem Without Timeouts:**
```swift
// Day 1: User checks account balance
// Cache: { balance: 5000 }

// Day 2: User opens app again
// Cache still shows: { balance: 5000 }
// ⚠️ But actual balance might be 3000 after recent transactions!
```

**Solution With Timeouts:**
```swift
// Cache with timestamp
Cache: {
    data: { balance: 5000 },
    timestamp: 1704024000,
    timeout: 300  // 5 minutes
}

// When fetching:
if (currentTime - timestamp) > timeout {
    // Cache expired → fetch from network
} else {
    // Cache valid → return cached data
}
```

---

### Option 1: Global Default Timeout

Simplest approach: apply the same timeout to all GraphQL queries.

#### Implementation

```swift
// APICoreKit - Global timeout configuration
public class GraphQLCacheConfig {
    /// Global cache timeout in seconds
    /// Default: 300 seconds (5 minutes)
    public static var defaultTimeout: TimeInterval = 300
    
    /// Enable/disable timeout checking
    public static var isTimeoutEnabled: Bool = true
}
```

#### Cache Entry with Timestamp

```swift
struct CachedQueryResult<Data: Codable>: Codable {
    let data: Data
    let timestamp: TimeInterval
    let cacheKey: String
    
    var isExpired: Bool {
        guard GraphQLCacheConfig.isTimeoutEnabled else {
            return false
        }
        
        let currentTime = Date().timeIntervalSince1970
        let age = currentTime - timestamp
        return age > GraphQLCacheConfig.defaultTimeout
    }
}
```

#### APICoreKit Client Implementation

```swift
public class ApolloGraphQLClient: GraphQLClient {
    private let apollo: ApolloClient
    private let timestampCache: NSCache<NSString, TimestampEntry>
    
    public init(apollo: ApolloClient) {
        self.apollo = apollo
        self.timestampCache = NSCache()
    }
    
    public func fetch<Query: GraphQLQuery>(
        query: Query,
        cachePolicy: GraphQLCachePolicy? = nil
    ) async -> Result<Query.Data, Error> {
        let policy = cachePolicy ?? .returnCacheDataElseFetch
        let cacheKey = generateCacheKey(for: query)
        
        // Check if cache is expired
        if policy == .returnCacheDataElseFetch {
            if let timestamp = timestampCache.object(forKey: cacheKey as NSString) {
                if timestamp.isExpired {
                    // Cache expired → force network fetch
                    return await fetchFromNetwork(query: query, cacheKey: cacheKey)
                }
            }
        }
        
        // Proceed with Apollo fetch
        return await withCheckedContinuation { continuation in
            apollo.fetch(query: query, cachePolicy: policy.toApolloCachePolicy()) { result in
                // Store timestamp on successful fetch
                if case .success = result {
                    let timestamp = TimestampEntry(time: Date().timeIntervalSince1970)
                    self.timestampCache.setObject(timestamp, forKey: cacheKey as NSString)
                }
                continuation.resume(returning: result.toResult())
            }
        }
    }
    
    private func fetchFromNetwork<Query: GraphQLQuery>(
        query: Query,
        cacheKey: String
    ) async -> Result<Query.Data, Error> {
        return await withCheckedContinuation { continuation in
            apollo.fetch(
                query: query,
                cachePolicy: .fetchIgnoringCacheData
            ) { result in
                // Update timestamp
                if case .success = result {
                    let timestamp = TimestampEntry(time: Date().timeIntervalSince1970)
                    self.timestampCache.setObject(timestamp, forKey: cacheKey as NSString)
                }
                continuation.resume(returning: result.toResult())
            }
        }
    }
}

class TimestampEntry: NSObject {
    let time: TimeInterval
    
    init(time: TimeInterval) {
        self.time = time
    }
    
    var isExpired: Bool {
        let currentTime = Date().timeIntervalSince1970
        let age = currentTime - time
        return age > GraphQLCacheConfig.defaultTimeout
    }
}
```

#### Usage

```swift
// Set global timeout (typically in AppDelegate or dependency setup)
GraphQLCacheConfig.defaultTimeout = 300  // 5 minutes

// All queries automatically use this timeout
let balance = await getBalanceUseCase.execute(accountId: "123")
// If cached data is older than 5 minutes, fetches fresh data
```

---

### Option 2: Per-Query Timeout (Recommended)

More flexible approach: configure timeout per query type based on data freshness requirements.

#### Implementation

```swift
// Protocol for queries with custom timeout
public protocol CacheableQuery {
    /// Cache timeout in seconds
    /// Return nil to use global default
    static var cacheTimeout: TimeInterval? { get }
}

// Example query with custom timeout
extension GetAccountBalanceQuery: CacheableQuery {
    static var cacheTimeout: TimeInterval? {
        return 30  // 30 seconds - balance changes frequently
    }
}

extension GetUserProfileQuery: CacheableQuery {
    static var cacheTimeout: TimeInterval? {
        return 900  // 15 minutes - profile changes rarely
    }
}

extension GetStaticContentQuery: CacheableQuery {
    static var cacheTimeout: TimeInterval? {
        return 86400  // 24 hours - static content
    }
}
```

#### Cache Configuration Model

```swift
public enum QueryCacheTimeout {
    case never                          // Cache indefinitely
    case seconds(TimeInterval)          // Specific timeout
    case useDefault                     // Use global default
    
    var timeInterval: TimeInterval? {
        switch self {
        case .never:
            return nil
        case .seconds(let interval):
            return interval
        case .useDefault:
            return GraphQLCacheConfig.defaultTimeout
        }
    }
}
```

#### Enhanced APICoreKit Client

```swift
public class ApolloGraphQLClient: GraphQLClient {
    private let apollo: ApolloClient
    private let timestampCache: NSCache<NSString, QueryTimestamp>
    
    public func fetch<Query: GraphQLQuery>(
        query: Query,
        cachePolicy: GraphQLCachePolicy? = nil,
        cacheTimeout: TimeInterval? = nil
    ) async -> Result<Query.Data, Error> {
        let policy = cachePolicy ?? .returnCacheDataElseFetch
        let cacheKey = generateCacheKey(for: query)
        
        // Determine timeout for this query
        let timeout = determineTimeout(
            explicit: cacheTimeout,
            query: query
        )
        
        // Check if cache is expired
        if policy == .returnCacheDataElseFetch, let timeout = timeout {
            if let cached = timestampCache.object(forKey: cacheKey as NSString) {
                if cached.isExpired(timeout: timeout) {
                    // Cache expired → force network fetch
                    return await fetchFromNetwork(query: query, cacheKey: cacheKey, timeout: timeout)
                }
            }
        }
        
        // Proceed with Apollo fetch
        return await withCheckedContinuation { continuation in
            apollo.fetch(query: query, cachePolicy: policy.toApolloCachePolicy()) { result in
                if case .success = result {
                    self.storeTimestamp(cacheKey: cacheKey, timeout: timeout)
                }
                continuation.resume(returning: result.toResult())
            }
        }
    }
    
    private func determineTimeout<Query: GraphQLQuery>(
        explicit: TimeInterval?,
        query: Query
    ) -> TimeInterval? {
        // 1. Explicit timeout provided
        if let explicit = explicit {
            return explicit
        }
        
        // 2. Query conforms to CacheableQuery protocol
        if let cacheableQuery = query as? CacheableQuery.Type {
            if let queryTimeout = cacheableQuery.cacheTimeout {
                return queryTimeout
            }
        }
        
        // 3. Fall back to global default
        return GraphQLCacheConfig.defaultTimeout
    }
    
    private func storeTimestamp(cacheKey: String, timeout: TimeInterval?) {
        let timestamp = QueryTimestamp(
            time: Date().timeIntervalSince1970,
            timeout: timeout
        )
        timestampCache.setObject(timestamp, forKey: cacheKey as NSString)
    }
}

class QueryTimestamp: NSObject {
    let time: TimeInterval
    let timeout: TimeInterval?
    
    init(time: TimeInterval, timeout: TimeInterval?) {
        self.time = time
        self.timeout = timeout
    }
    
    func isExpired(timeout: TimeInterval) -> Bool {
        let currentTime = Date().timeIntervalSince1970
        let age = currentTime - time
        return age > timeout
    }
}
```

---

### Timeout Configuration Guidelines

Recommended timeout values based on data type:

| Data Type | Timeout | Rationale |
|-----------|---------|-----------|
| **Account Balance** | 30-60 seconds | Changes frequently with transactions |
| **Transaction List** | 2-5 minutes | Updates with new transactions |
| **User Profile** | 15 minutes | Changes rarely |
| **Card List** | 5 minutes | Occasional changes |
| **Payment Recipients** | 10 minutes | Moderate change frequency |
| **Static Content** | 24 hours | Rarely changes |
| **Feature Flags** | 1 hour | Moderate change frequency |
| **Default** | 5 minutes | Safe middle ground |

---

### Settings.bundle Configuration

Extend existing Settings.bundle to include timeout configuration:

```swift
// Settings.bundle/GraphQLCache.plist
GraphQL Cache Settings:
├── Enable Cache Timeout: [ON/OFF]
├── Global Default Timeout: [Slider: 0-3600 seconds]
└── Per-Query Timeouts:
    ├── Account Balance: [30s / 1min / 5min / Custom]
    ├── Transactions: [1min / 5min / 15min / Custom]
    ├── Profile: [5min / 15min / 1hr / Custom]
    └── Custom (seconds): [Text field]
```

#### Reading Settings

```swift
extension GraphQLCacheConfig {
    static func loadFromSettings() {
        let defaults = UserDefaults.standard
        
        // Global timeout
        if let timeout = defaults.object(forKey: "graphql_cache_default_timeout") as? TimeInterval {
            GraphQLCacheConfig.defaultTimeout = timeout
        }
        
        // Enable/disable
        isTimeoutEnabled = defaults.bool(forKey: "graphql_cache_timeout_enabled")
    }
}
```

---

### Feature Kit Integration

Feature Kits can specify timeout when calling APICoreKit:

```swift
// Feature Kit use case with explicit timeout
public class GetAccountBalanceUseCase {
    private let apiClient: GraphQLClient
    
    public func execute(
        accountId: String,
        cachePolicy: GraphQLCachePolicy? = nil
    ) async -> Result<AccountBalance, Error> {
        let query = GetAccountBalanceQuery(accountId: accountId)
        
        return await apiClient.fetch(
            query: query,
            cachePolicy: cachePolicy,
            cacheTimeout: 30  // ← Balance expires after 30 seconds
        )
    }
}
```

Or let query define its own timeout:

```swift
// Query implements CacheableQuery
extension GetAccountBalanceQuery: CacheableQuery {
    static var cacheTimeout: TimeInterval? {
        return 30
    }
}

// Use case doesn't need to specify timeout
public func execute(accountId: String) async -> Result<AccountBalance, Error> {
    return await apiClient.fetch(query: query)
    // Automatically uses 30 second timeout from query definition
}
```

---

### Timeout Logging (Debug Only)

For non-release builds, log cache timeout events:

```swift
#if DEBUG
private func logCacheTimeout(cacheKey: String, age: TimeInterval, timeout: TimeInterval) {
    print("""
        [GraphQL Cache] Cache expired
        Key: \(cacheKey)
        Age: \(Int(age))s
        Timeout: \(Int(timeout))s
        Action: Fetching fresh data
        """)
}
#endif
```

---

### Summary: Timeout Implementation

**Option 1: Global Timeout (Simpler)**
- ✅ Easy to implement and configure
- ✅ Consistent behavior across all queries
- ❌ Not optimized for different data types
- **Best for:** Quick implementation, simple requirements

**Option 2: Per-Query Timeout (Recommended)**
- ✅ Optimized timeout per data type
- ✅ More flexible and efficient
- ✅ Better cache hit rates
- ⚠️ Requires timeout configuration per query
- **Best for:** Production applications, varied data freshness needs

**Implementation Priority:**
1. Start with global timeout (Phase 1)
2. Add per-query timeout support (Phase 2)
3. Migrate queries to optimal timeouts (Phase 3)

---

## Mutation Handling Strategies

When a GraphQL mutation is performed (e.g., making a payment, updating profile), the cached data must be updated to reflect the change. This section presents two strategies for handling cache updates after mutations.

---

### The Mutation Cache Problem

```swift
// Initial state: User has $5000 in account
let balance = await getBalanceUseCase.execute(accountId: "123")
// Cache: { balance: 5000 }
// UI shows: $5000

// User makes a $1000 payment
let result = await makePaymentUseCase.execute(amount: 1000)
// Server processes payment successfully
// Server balance is now: $4000

// ⚠️ PROBLEM: Cache still shows { balance: 5000 }
// ⚠️ UI still shows: $5000 (WRONG!)
```

**The Challenge:**
After a mutation, multiple queries may need to be updated:
- Balance query
- Transaction list query
- Dashboard summary query
- Account details query

---

### Strategy 1: Manual Refetch After Mutations

**Concept:** After each mutation, MIB explicitly refetches all affected queries using the network-only cache policy.

#### Implementation in MIB

```swift
class PaymentViewModel {
    let makePaymentUseCase: MakePaymentUseCase
    let getBalanceUseCase: GetAccountBalanceUseCase
    let getTransactionsUseCase: GetTransactionsUseCase
    let getDashboardUseCase: GetDashboardUseCase
    
    func makePayment(amount: Decimal, accountId: String) async {
        // 1. Execute mutation
        let paymentResult = await makePaymentUseCase.execute(
            amount: amount,
            fromAccountId: accountId
        )
        
        guard case .success(let paymentDetails) = paymentResult else {
            handleError()
            return
        }
        
        // 2. Refetch all affected queries with fresh data
        await refetchAffectedQueries(accountId: accountId)
        
        // 3. Update UI
        updateUI(with: paymentDetails)
    }
    
    private func refetchAffectedQueries(accountId: String) async {
        // Fetch balance with network-only policy
        let _ = await getBalanceUseCase.execute(
            accountId: accountId,
            cachePolicy: .fetchIgnoringCacheData  // ← Force network fetch
        )
        
        // Fetch transactions with network-only policy
        let _ = await getTransactionsUseCase.execute(
            accountId: accountId,
            cachePolicy: .fetchIgnoringCacheData  // ← Force network fetch
        )
        
        // Fetch dashboard with network-only policy
        let _ = await getDashboardUseCase.execute(
            cachePolicy: .fetchIgnoringCacheData  // ← Force network fetch
        )
    }
}
```

#### Advantages

✅ **Simple Implementation**
- No changes to APICoreKit required
- MIB has explicit control over what to refetch
- Easy to understand and debug

✅ **Guaranteed Fresh Data**
- Always fetches latest state from server
- No risk of stale cache

✅ **Flexible**
- Can selectively refetch only relevant queries
- Can add delay or retry logic if needed

#### Disadvantages

❌ **Manual Maintenance Required**
- MIB must know which queries are affected by each mutation
- Easy to forget to refetch a query
- Coupling between mutations and queries

❌ **Multiple Network Calls**
- Each refetch is a separate network request
- May impact performance with many affected queries

❌ **MIB Logic Burden**
- Business logic about query dependencies lives in MIB
- Not in Feature Kits where domain logic should be

#### Mutation-to-Query Mapping

MIB maintains a mapping of which queries to refetch for each mutation:

```swift
enum MutationType {
    case makePayment
    case updateProfile
    case addPayee
    case deleteCard
    // ... other mutations
}

struct MutationRefetchPolicy {
    let mutationType: MutationType
    let queriesToRefetch: [RefetchQuery]
    
    enum RefetchQuery {
        case balance(accountId: String)
        case transactions(accountId: String)
        case dashboard
        case profile
        case cards
        // ... other queries
    }
}

class MutationRefetchManager {
    func refetchAfterMutation(_ type: MutationType, context: [String: Any]) async {
        let policy = getPolicy(for: type)
        
        await withTaskGroup(of: Void.self) { group in
            for query in policy.queriesToRefetch {
                group.addTask {
                    await self.refetchQuery(query, context: context)
                }
            }
        }
    }
    
    private func refetchQuery(_ query: MutationRefetchPolicy.RefetchQuery, context: [String: Any]) async {
        switch query {
        case .balance(let accountId):
            await getBalanceUseCase.execute(
                accountId: accountId,
                cachePolicy: .fetchIgnoringCacheData
            )
            
        case .transactions(let accountId):
            await getTransactionsUseCase.execute(
                accountId: accountId,
                cachePolicy: .fetchIgnoringCacheData
            )
            
        case .dashboard:
            await getDashboardUseCase.execute(
                cachePolicy: .fetchIgnoringCacheData
            )
            
        // ... other cases
        }
    }
}
```

#### Usage Example

```swift
class PaymentViewModel {
    let makePaymentUseCase: MakePaymentUseCase
    let refetchManager: MutationRefetchManager
    
    func makePayment(amount: Decimal, accountId: String) async {
        // 1. Execute mutation
        let result = await makePaymentUseCase.execute(
            amount: amount,
            fromAccountId: accountId
        )
        
        guard case .success = result else {
            handleError()
            return
        }
        
        // 2. Refetch using centralized manager
        await refetchManager.refetchAfterMutation(
            .makePayment,
            context: ["accountId": accountId]
        )
        
        // 3. UI automatically updates from refreshed cache
    }
}
```

---

### Strategy 2: Optimized Refetch with Smart Dependencies

**Concept:** Enhance Strategy 1 by introducing smarter refetch logic that:
1. Understands query dependencies
2. Batches network requests when possible
3. Uses `returnCacheDataAndFetch` for non-critical updates

#### Implementation with Smart Refetch

```swift
protocol MutationResultProvider {
    /// Queries that must be refetched immediately with network-only policy
    var criticalRefetchQueries: [QueryDescriptor] { get }
    
    /// Queries that can be refetched in background with cache-then-network policy
    var backgroundRefetchQueries: [QueryDescriptor] { get }
}

struct QueryDescriptor {
    let queryType: String
    let variables: [String: Any]
    let priority: RefetchPriority
    
    enum RefetchPriority {
        case critical    // User must see updated data immediately
        case high        // Update soon, but can show cache first
        case background  // Update when convenient
    }
}
```

#### Enhanced MIB Integration

```swift
class SmartMutationRefetchManager {
    func refetchAfterMutation(
        _ mutation: MutationResultProvider,
        accountId: String
    ) async {
        // 1. Critical refetches (blocking, network-only)
        await refetchCriticalQueries(mutation.criticalRefetchQueries, accountId: accountId)
        
        // 2. Background refetches (non-blocking, cache-then-network)
        Task.detached {
            await self.refetchBackgroundQueries(mutation.backgroundRefetchQueries, accountId: accountId)
        }
    }
    
    private func refetchCriticalQueries(_ queries: [QueryDescriptor], accountId: String) async {
        // Execute in parallel for speed
        await withTaskGroup(of: Void.self) { group in
            for query in queries {
                group.addTask {
                    await self.executeRefetch(
                        query,
                        accountId: accountId,
                        policy: .fetchIgnoringCacheData  // Network-only for critical
                    )
                }
            }
        }
    }
    
    private func refetchBackgroundQueries(_ queries: [QueryDescriptor], accountId: String) async {
        // Execute sequentially to avoid overloading network
        for query in queries {
            await executeRefetch(
                query,
                accountId: accountId,
                policy: .returnCacheDataAndFetch  // Cache-then-network for background
            )
        }
    }
}
```

#### Mutation Configuration Example

```swift
struct MakePaymentMutationResult: MutationResultProvider {
    let accountId: String
    
    var criticalRefetchQueries: [QueryDescriptor] {
        return [
            // User must see updated balance immediately
            QueryDescriptor(
                queryType: "GetAccountBalance",
                variables: ["accountId": accountId],
                priority: .critical
            ),
            // Recent transactions should show new payment
            QueryDescriptor(
                queryType: "GetRecentTransactions",
                variables: ["accountId": accountId, "limit": 10],
                priority: .critical
            )
        ]
    }
    
    var backgroundRefetchQueries: [QueryDescriptor] {
        return [
            // Dashboard can update in background
            QueryDescriptor(
                queryType: "GetDashboard",
                variables: [:],
                priority: .background
            ),
            // Full transaction history can update later
            QueryDescriptor(
                queryType: "GetAllTransactions",
                variables: ["accountId": accountId],
                priority: .background
            )
        ]
    }
}
```

#### Feature Kit Integration

```swift
// Feature Kit mutation use case provides refetch configuration
public protocol MakePaymentUseCase {
    func execute(
        amount: Decimal,
        fromAccountId: String
    ) async -> (Result<PaymentDetails, Error>, MutationResultProvider)
    //                                         ↑ Returns refetch info
}

public class DefaultMakePaymentUseCase: MakePaymentUseCase {
    public func execute(
        amount: Decimal,
        fromAccountId: String
    ) async -> (Result<PaymentDetails, Error>, MutationResultProvider) {
        let result = await apiClient.performMutation(...)
        
        // Return result + refetch configuration
        let refetchInfo = MakePaymentMutationResult(accountId: fromAccountId)
        return (result, refetchInfo)
    }
}
```

#### MIB Usage

```swift
class PaymentViewModel {
    let makePaymentUseCase: MakePaymentUseCase
    let refetchManager: SmartMutationRefetchManager
    
    func makePayment(amount: Decimal, accountId: String) async {
        showLoading()
        
        // 1. Execute mutation and get refetch configuration
        let (result, refetchInfo) = await makePaymentUseCase.execute(
            amount: amount,
            fromAccountId: accountId
        )
        
        guard case .success(let details) = result else {
            hideLoading()
            handleError()
            return
        }
        
        // 2. Smart refetch (critical queries block, background queries don't)
        await refetchManager.refetchAfterMutation(refetchInfo, accountId: accountId)
        
        hideLoading()
        showSuccess()
        // UI shows updated balance and recent transactions
        // Dashboard updates in background
    }
}
```

---

### Comparison: Strategy 1 vs Strategy 2

| Aspect | Strategy 1: Manual Refetch | Strategy 2: Optimized Refetch |
|--------|---------------------------|------------------------------|
| **Complexity** | Low | Medium |
| **Maintenance** | High (manual mapping) | Medium (declarative config) |
| **Performance** | All queries fetched immediately | Critical first, background later |
| **Network Usage** | Higher (all queries network-only) | Lower (cache-then-network for some) |
| **User Experience** | Can be slower (blocking) | Faster (non-blocking background) |
| **Error Handling** | Simple (all or nothing) | More complex (partial success) |
| **Feature Kit Coupling** | Looser (MIB controls logic) | Tighter (Feature Kit declares needs) |
| **Recommended For** | Phase 1 implementation | Phase 2 optimization |

---

### Implementation Recommendation

**Phase 1: Start with Strategy 1**
- Implement manual refetch pattern in MIB
- Create `MutationRefetchManager` with explicit mappings
- Focus on correctness over optimization

**Phase 2: Evolve to Strategy 2**
- Add `MutationResultProvider` protocol
- Enhance manager with priority-based refetch
- Migrate mutations to declarative configuration
- Add background refetch support

**Critical Success Factors:**
1. ✅ Document which queries each mutation affects
2. ✅ Test that all affected queries are refetched
3. ✅ Monitor network usage and cache hit rates
4. ✅ Add logging for debugging refetch behavior

---

### Summary: Mutation Handling

Both strategies ensure cache consistency after mutations, with trade-offs between simplicity and optimization:

**Strategy 1 (Manual Refetch):**
- MIB explicitly refetches affected queries
- All refetches use network-only policy
- Simple to implement and understand
- **Recommended for initial implementation**

**Strategy 2 (Optimized Refetch):**
- Feature Kits declare query dependencies
- Critical queries refetch immediately, others in background
- Better performance and user experience
- **Recommended for optimization phase**

**Next:** See "Normalized Cache with Custom Keys" section for an alternative approach that can reduce the need for explicit refetching.

---

## Normalized Cache with Custom Keys

This section introduces an advanced caching strategy using Apollo's normalized cache with custom cache keys. This approach eliminates many manual refetch requirements by enabling automatic cache updates.

---

### The Problem with Query-Based Caching

As demonstrated earlier, query-based caching stores each query result independently:

```swift
// Query A
GetAccountBalance(accountId: "123")
Cache: "GetAccountBalance:123" → { balance: 5000 }

// Query B
GetAccountDetails(accountId: "123")
Cache: "GetAccountDetails:123" → { id: "123", name: "Savings", balance: 5000 }

// Problem: Balance is stored twice!
// When balance changes, both cache entries must be manually updated
```

---

### Solution: Normalized Object-Based Cache

**Concept:** Instead of caching complete query results, cache individual objects with unique identifiers. Queries reference these cached objects.

```swift
// With normalized cache:

// Cache storage (objects)
Objects: {
    "Account:123": { id: "123", name: "Savings", balance: 5000, type: "SAVINGS" }
}

// Query A references the object
GetAccountBalance(accountId: "123")
References: ["Account:123"]
Returns: { balance: 5000 }

// Query B also references the same object
GetAccountDetails(accountId: "123")
References: ["Account:123"]
Returns: { id: "123", name: "Savings", balance: 5000, type: "SAVINGS" }

// ✅ When Account:123 updates, BOTH queries automatically see the change!
```

---

### How Apollo's Normalized Cache Works

Apollo normalizes objects by extracting them from query responses and storing them by unique keys:

```
Query Response (nested):
{
  user: {
    id: "user-1",
    name: "John",
    accounts: [
      { id: "123", name: "Savings", balance: 5000 },
      { id: "456", name: "Checking", balance: 2000 }
    ]
  }
}

Normalized Storage (flat):
{
  "User:user-1": { id: "user-1", name: "John", accounts: [REF("Account:123"), REF("Account:456")] },
  "Account:123": { id: "123", name: "Savings", balance: 5000 },
  "Account:456": { id: "456", name: "Checking", balance: 2000 }
}
```

---

### Configuring Custom Cache Keys

Apollo needs to know how to generate cache keys for each GraphQL type. Feature Kits provide this configuration to APICoreKit.

#### Step 1: Define Cache Key Configuration

```swift
// Protocol for Feature Kits to implement
public protocol GraphQLCacheKeyProvider {
    /// Returns the cache key for a given GraphQL type and object
    /// - Parameters:
    ///   - typename: The GraphQL __typename (e.g., "Account", "Transaction")
    ///   - object: The object data as JSON
    /// - Returns: A unique cache key (e.g., "Account:123") or nil to disable caching for this type
    func cacheKey(forTypename typename: String, object: [String: Any]) -> String?
}
```

#### Step 2: Feature Kit Implementation

```swift
// AccountsKit provides cache key configuration
public class AccountsCacheKeyProvider: GraphQLCacheKeyProvider {
    public func cacheKey(forTypename typename: String, object: [String: Any]) -> String? {
        switch typename {
        case "Account":
            // Cache accounts by their ID
            guard let id = object["id"] as? String else { return nil }
            return "Account:\(id)"
            
        case "Transaction":
            // Cache transactions by their ID
            guard let id = object["transactionId"] as? String else { return nil }
            return "Transaction:\(id)"
            
        case "AccountBalance":
            // Cache balance by account ID
            guard let accountId = object["accountId"] as? String else { return nil }
            return "AccountBalance:\(accountId)"
            
        case "User":
            // Cache user by their ID
            guard let id = object["userId"] as? String else { return nil }
            return "User:\(id)"
            
        default:
            // No caching for unknown types
            return nil
        }
    }
}
```

#### Step 3: APICoreKit Configuration

```swift
public class GraphQLCacheConfiguration {
    private var cacheKeyProviders: [GraphQLCacheKeyProvider] = []
    
    /// Register a cache key provider from a Feature Kit
    public func registerCacheKeyProvider(_ provider: GraphQLCacheKeyProvider) {
        cacheKeyProviders.append(provider)
    }
    
    /// Get cache key for an object (checks all registered providers)
    func cacheKey(forTypename typename: String, object: [String: Any]) -> String? {
        for provider in cacheKeyProviders {
            if let key = provider.cacheKey(forTypename: typename, object: object) {
                return key
            }
        }
        return nil
    }
}
```

#### Step 4: Apollo Client Setup

```swift
public class ApolloClientFactory {
    public static func create(
        cacheConfig: GraphQLCacheConfiguration
    ) -> ApolloClient {
        // Create normalized cache with custom key resolution
        let cache = InMemoryNormalizedCache()
        
        let store = ApolloStore(cache: cache) { (object, variables) -> CacheKey in
            // Extract __typename from object
            guard let typename = object["__typename"] as? String else {
                return nil
            }
            
            // Get cache key from configuration
            if let key = cacheConfig.cacheKey(forTypename: typename, object: object) {
                return CacheKey(key)
            }
            
            return nil
        }
        
        let client = ApolloClient(
            networkTransport: networkTransport,
            store: store
        )
        
        return client
    }
}
```

---

### Registration Flow

```swift
// In app initialization (e.g., AppDelegate or DI container)
class GraphQLClientInitializer {
    func initialize() -> ApolloClient {
        // 1. Create cache configuration
        let cacheConfig = GraphQLCacheConfiguration()
        
        // 2. Register cache key providers from Feature Kits
        cacheConfig.registerCacheKeyProvider(AccountsCacheKeyProvider())
        cacheConfig.registerCacheKeyProvider(CardsCacheKeyProvider())
        cacheConfig.registerCacheKeyProvider(PaymentsCacheKeyProvider())
        // ... other Feature Kits
        
        // 3. Create Apollo client with normalized cache
        let apolloClient = ApolloClientFactory.create(cacheConfig: cacheConfig)
        
        return apolloClient
    }
}
```

---

### How Normalized Cache Transforms Queries

#### Before: Query-Based Caching

```swift
// Query 1: Get balance
query GetBalance($accountId: ID!) {
  account(id: $accountId) {
    balance
  }
}
// Cache: "GetBalance:{"accountId":"123"}" → { account: { balance: 5000 } }

// Query 2: Get account details
query GetAccount($accountId: ID!) {
  account(id: $accountId) {
    id
    name
    balance
    type
  }
}
// Cache: "GetAccount:{"accountId":"123"}" → { account: { id, name, balance: 5000, type } }

// ⚠️ Balance stored twice
```

#### After: Normalized Caching

```swift
// Query 1: Get balance
query GetBalance($accountId: ID!) {
  account(id: $accountId) {
    __typename  # ← Must include __typename for normalization
    id          # ← Must include id for cache key
    balance
  }
}

// Normalized storage:
// Objects: { "Account:123": { __typename: "Account", id: "123", balance: 5000 } }
// Query: "GetBalance:{"accountId":"123"}" → References ["Account:123"]

// Query 2: Get account details
query GetAccount($accountId: ID!) {
  account(id: $accountId) {
    __typename  # ← Must include __typename
    id          # ← Must include id
    name
    balance
    type
  }
}

// Normalized storage:
// Objects: { "Account:123": { __typename: "Account", id: "123", name: "Savings", balance: 5000, type: "SAVINGS" } }
// Query: "GetAccount:{"accountId":"123"}" → References ["Account:123"]

// ✅ Balance stored once, shared by both queries
```

---

### Automatic Cache Updates After Mutations

With normalized cache, mutations can automatically update all related queries:

#### Example: Payment Mutation

```swift
// Before payment
Cache Objects: {
    "Account:123": { id: "123", balance: 5000 }
}

Queries referencing Account:123:
- GetBalance → shows 5000
- GetAccount → shows 5000
- GetDashboard → shows 5000

// User makes $1000 payment
mutation MakePayment($accountId: ID!, $amount: Decimal!) {
  makePayment(accountId: $accountId, amount: $amount) {
    account {
      __typename
      id
      balance  # ← Server returns updated balance: 4000
    }
  }
}

// After mutation
// Apollo automatically updates the cache object
Cache Objects: {
    "Account:123": { id: "123", balance: 4000 }  # ← Updated!
}

// ✅ ALL queries automatically see new balance:
- GetBalance → now shows 4000
- GetAccount → now shows 4000
- GetDashboard → now shows 4000

// No manual refetch needed!
```

---

### Complete Cache Mechanism Flow

#### 1. Query Execution Flow

```
User Action
    ↓
MIB calls Feature Kit use case
    ↓
Feature Kit calls APICoreKit
    ↓
APICoreKit queries Apollo Client
    ↓
Apollo checks cache:
    ├─ Cache Key: "GetBalance:{"accountId":"123"}"
    ├─ References: ["Account:123"]
    ├─ Object exists? → Return cached data
    └─ Object missing? → Fetch from network
    ↓
Apollo normalizes response:
    ├─ Extracts objects from response
    ├─ Generates cache keys using Feature Kit config
    │   └─ AccountsCacheKeyProvider.cacheKey(typename: "Account", object: {...})
    │       returns "Account:123"
    └─ Stores in cache:
        Cache["Account:123"] = { id: "123", balance: 5000 }
    ↓
Returns data to Feature Kit
    ↓
Returns to MIB
    ↓
UI updates
```

#### 2. Mutation Execution Flow

```
User Action (Payment)
    ↓
MIB calls Feature Kit mutation use case
    ↓
Feature Kit calls APICoreKit
    ↓
APICoreKit executes mutation on Apollo Client
    ↓
Server processes mutation
    ↓
Server returns updated object:
    {
      makePayment: {
        account: {
          __typename: "Account",
          id: "123",
          balance: 4000  // ← Updated
        }
      }
    }
    ↓
Apollo normalizes mutation response:
    ├─ Extracts account object
    ├─ Generates cache key: "Account:123"
    └─ Updates cache:
        Cache["Account:123"] = { id: "123", balance: 4000 }  // ← Replaces old value
    ↓
Apollo invalidates related queries:
    ├─ "GetBalance:{"accountId":"123"}" → references Account:123 → auto-updated
    ├─ "GetAccount:{"accountId":"123"}" → references Account:123 → auto-updated
    └─ "GetDashboard:{}" → if it references Account:123 → auto-updated
    ↓
Returns mutation result to Feature Kit
    ↓
Returns to MIB
    ↓
UI observes cache change and auto-updates
    (No manual refetch needed!)
```

---

### Benefits of Normalized Cache

✅ **Automatic Query Updates**
- Mutations update objects once
- All queries referencing those objects automatically see changes
- Eliminates most manual refetch logic

✅ **Reduced Memory Usage**
- Each object stored once, regardless of how many queries use it
- Significant savings for frequently accessed data

✅ **Consistent Data**
- Single source of truth for each object
- Impossible to have stale data in one query while another is fresh

✅ **Better Performance**
- Fewer network requests needed
- Faster cache lookups (object-based instead of query-based)

✅ **Simplified MIB Logic**
- Less manual cache management
- Fewer refetch calls needed after mutations

---

### Implementation Requirements

#### Feature Kit Responsibilities

**1. Implement CacheKeyProvider**
```swift
public class AccountsCacheKeyProvider: GraphQLCacheKeyProvider {
    public func cacheKey(forTypename typename: String, object: [String: Any]) -> String? {
        // Define cache keys for all types in this domain
    }
}
```

**2. Include Required Fields in Queries**
```swift
// ✅ GOOD: Includes __typename and id
query GetAccount($id: ID!) {
  account(id: $id) {
    __typename  # Required for normalization
    id          # Required for cache key
    name
    balance
  }
}

// ❌ BAD: Missing required fields
query GetAccount($id: ID!) {
  account(id: $id) {
    name
    balance
  }
}
```

**3. Include Required Fields in Mutations**
```swift
// ✅ GOOD: Mutation returns normalized objects
mutation MakePayment($amount: Decimal!) {
  makePayment(amount: $amount) {
    transaction {
      __typename
      id
      amount
      status
    }
    account {
      __typename
      id
      balance  # ← This will auto-update cache!
    }
  }
}
```

#### APICoreKit Responsibilities

**1. Provide CacheKeyProvider Protocol**
```swift
public protocol GraphQLCacheKeyProvider {
    func cacheKey(forTypename typename: String, object: [String: Any]) -> String?
}
```

**2. Manage Provider Registration**
```swift
public class GraphQLCacheConfiguration {
    func registerCacheKeyProvider(_ provider: GraphQLCacheKeyProvider)
    func cacheKey(forTypename typename: String, object: [String: Any]) -> String?
}
```

**3. Configure Apollo with Custom Keys**
```swift
let store = ApolloStore(cache: cache) { (object, variables) in
    // Use registered providers to generate cache keys
}
```

#### MIB Responsibilities

**1. Initialize Cache Configuration**
```swift
let cacheConfig = GraphQLCacheConfiguration()
cacheConfig.registerCacheKeyProvider(AccountsCacheKeyProvider())
// Register all Feature Kit providers
```

**2. Reduced Refetch Logic**
```swift
// Before normalized cache: Manual refetch needed
func afterMutation() async {
    await refetchBalance()
    await refetchDashboard()
    await refetchTransactions()
}

// After normalized cache: Automatic updates
func afterMutation() async {
    // Mutation result auto-updates cache
    // All queries automatically see changes
    // No manual refetch needed in most cases!
}
```

**3. Selective Refetch for Special Cases**
```swift
// Only refetch queries that don't share normalized objects
// Example: Aggregate queries or queries without common objects
await refetchDashboardSummary()  // Different data structure, needs refetch
```

---

### Comparison: Query-Based vs Normalized Cache

| Aspect | Query-Based Cache | Normalized Cache |
|--------|------------------|------------------|
| **Cache Key** | Query + variables | Type + ID |
| **Object Storage** | Once per query | Once globally |
| **Query Relationships** | Independent | Shared references |
| **Mutation Updates** | Manual refetch needed | Automatic |
| **Memory Usage** | Higher (duplication) | Lower (no duplication) |
| **Setup Complexity** | Low (zero config) | Medium (key providers) |
| **Maintenance** | High (track dependencies) | Low (automatic) |
| **Consistency Risk** | Higher (manual sync) | Lower (single source) |
| **Feature Kit Changes** | Minimal | Must include __typename, id |
| **Best For** | Quick start, simple apps | Production, complex data |

---

### Migration Strategy

**Phase 1: Enable Normalized Cache Foundation**
1. Add `GraphQLCacheKeyProvider` protocol to APICoreKit
2. Add `GraphQLCacheConfiguration` to manage providers
3. Update Apollo client initialization to use custom keys
4. No Feature Kit changes yet (cache keys return nil = query-based cache)

**Phase 2: Migrate Feature Kits Incrementally**
1. Start with AccountsKit (most frequently used)
2. Implement `AccountsCacheKeyProvider`
3. Update queries to include `__typename` and `id`
4. Test cache behavior
5. Remove manual refetch logic from MIB for Account queries
6. Repeat for other Feature Kits

**Phase 3: Optimize MIB**
1. Reduce refetch logic for normalized types
2. Keep refetch only for aggregate or special queries
3. Monitor cache hit rates and performance

---

### Testing Normalized Cache

```swift
class NormalizedCacheTests: XCTestCase {
    func testObjectIsSharedBetweenQueries() async {
        // 1. Execute first query
        let balance = await getBalanceUseCase.execute(accountId: "123")
        XCTAssertEqual(balance.amount, 5000)
        
        // 2. Execute second query
        let account = await getAccountUseCase.execute(accountId: "123")
        XCTAssertEqual(account.balance, 5000)
        
        // 3. Verify both queries reference same cached object
        let cacheKey = "Account:123"
        let cachedObject = apolloCache.loadObject(forKey: cacheKey)
        XCTAssertNotNil(cachedObject)
        XCTAssertEqual(cachedObject["balance"] as? Decimal, 5000)
    }
    
    func testMutationAutoUpdatesAllQueries() async {
        // 1. Fetch initial balance
        let initialBalance = await getBalanceUseCase.execute(accountId: "123")
        XCTAssertEqual(initialBalance.amount, 5000)
        
        // 2. Execute mutation
        let _ = await makePaymentUseCase.execute(amount: 1000, accountId: "123")
        
        // 3. Fetch balance again (should be updated automatically)
        let updatedBalance = await getBalanceUseCase.execute(
            accountId: "123",
            cachePolicy: .returnCacheDataDontFetch  // ← Cache only, no network
        )
        XCTAssertEqual(updatedBalance.amount, 4000)  // ← Auto-updated from mutation!
    }
}
```

---

### Summary: Normalized Cache

**Key Concepts:**
1. Objects cached by Type + ID instead of query
2. Queries reference shared objects
3. Updating object updates all queries automatically
4. Feature Kits provide cache key configuration
5. Requires including `__typename` and `id` in queries

**Benefits:**
- ✅ Automatic cache updates after mutations
- ✅ Reduced memory usage
- ✅ Consistent data across queries
- ✅ Simplified MIB logic
- ✅ Better performance

**Requirements:**
- Feature Kits implement `CacheKeyProvider`
- Queries include `__typename` and `id`
- APICoreKit configures Apollo with custom keys
- MIB registers all cache key providers

**Recommendation:**
Implement normalized cache as Phase 2 enhancement after basic mutation handling (Strategy 1) is working. This provides the foundation for an optimal, low-maintenance caching system.

---

## Cache Clearing Scenarios

This section defines when and how to clear caches to maintain data security and prevent stale data issues.

---

### Cache Clearing Requirements

Different user actions require different levels of cache clearing to balance performance with security and data freshness.

---

### Scenario 1: Complete Logout (Clear Everything)

**Trigger:** User logs out of the application

**Requirement:** Clear ALL caches (REST and GraphQL) to prevent data leakage

**Affected Data:**
- Account information
- Transaction history
- Personal details
- Balances
- Cards
- Payment recipients
- Any cached financial data

**Implementation:**

```swift
protocol UnifiedCacheManager {
    /// Clears all caches (REST + GraphQL)
    /// Used during logout for security
    func clearAllCaches() async
}

class DefaultUnifiedCacheManager: UnifiedCacheManager {
    private let restCacheManager: CacheManaging
    private let apolloClient: ApolloClient
    
    func clearAllCaches() async {
        // 1. Clear REST caches
        restCacheManager.clearCache()
        
        // 2. Clear GraphQL cache
        await apolloClient.clearCache()
        
        // 3. Clear timestamp tracking
        timestampCache.removeAllObjects()
        
        // 4. Clear WebView caches
        internetBankingCacheManager.clearCache()
        internetBankingCacheManager.clearCookie()
        
        #if DEBUG
        print("[Cache] All caches cleared (logout)")
        #endif
    }
}
```

**Usage in Logout Flow:**

```swift
class SessionManager {
    let cacheManager: UnifiedCacheManager
    
    func logout() async {
        // 1. Clear user session
        await authService.logout()
        
        // 2. Clear ALL caches
        await cacheManager.clearAllCaches()
        
        // 3. Navigate to login
        coordinator.showLogin()
    }
}
```

**Security Priority:** ⚠️ **Critical** - This is a security requirement to prevent unauthorized access to cached financial data.

---

### Scenario 2: Account Switch

**Trigger:** User switches between multiple accounts (if supported)

**Requirement:** Clear account-specific data while retaining user-level data

**Affected Data:**
- Account balance
- Account transactions
- Account-specific cards

**Retained Data:**
- User profile
- App preferences
- Static content

**Implementation:**

```swift
protocol UnifiedCacheManager {
    /// Clears cache for specific account
    /// Used when switching accounts
    func clearCache(forAccountId accountId: String) async
}

extension DefaultUnifiedCacheManager {
    func clearCache(forAccountId accountId: String) async {
        // 1. Clear REST caches for this account
        restCacheManager.clearCache(forAccountId: accountId)
        
        // 2. Clear GraphQL cache entries for this account
        await clearGraphQLAccountCache(accountId: accountId)
        
        #if DEBUG
        print("[Cache] Cleared cache for account: \(accountId)")
        #endif
    }
    
    private func clearGraphQLAccountCache(accountId: String) async {
        // Option 1: Clear specific cache keys (normalized cache)
        let accountKey = "Account:\(accountId)"
        apolloClient.store.withinReadWriteTransaction { transaction in
            try transaction.removeObject(forKey: accountKey)
        }
        
        // Option 2: Clear queries with this account ID (query-based cache)
        // More complex, requires tracking queries by account ID
    }
}
```

---

### Scenario 3: Session Expiry

**Trigger:** User session expires (timeout or token expiry)

**Requirement:** Clear all caches, similar to logout

**Implementation:**

```swift
class SessionManager {
    let cacheManager: UnifiedCacheManager
    
    func handleSessionExpiry() async {
        // Same as logout
        await cacheManager.clearAllCaches()
        
        // Show session expired message
        coordinator.showSessionExpired()
    }
}
```

---

### Scenario 4: Pull to Refresh

**Trigger:** User explicitly requests data refresh

**Requirement:** Fetch fresh data for current screen, update cache

**Implementation:**

```swift
class AccountDetailViewModel {
    let getAccountUseCase: GetAccountBalanceUseCase
    
    func refresh() async {
        // Force network fetch, update cache
        let result = await getAccountUseCase.execute(
            accountId: accountId,
            cachePolicy: .fetchIgnoringCacheData  // Bypass cache
        )
        
        // Apollo automatically updates cache with fresh data
        updateUI(with: result)
    }
}
```

**Note:** This doesn't clear cache - it fetches fresh data and updates the cache.

---

### Scenario 5: Data Stale Timeout

**Trigger:** Cached data exceeds configured timeout

**Requirement:** Automatically fetch fresh data on next query

**Implementation:**

Handled automatically by timeout mechanism (see Cache Timeout section):

```swift
// When cache is checked:
if cachedData.isExpired(timeout: queryTimeout) {
    // Automatically fetch from network
    return await fetchFromNetwork(query)
}
// Return cached data if not expired
return cachedData
```

---

### Scenario 6: App Restart

**Trigger:** App is killed and restarted

**Requirement:** Cache is automatically cleared (in-memory only)

**Behavior:**
- InMemoryNormalizedCache is cleared when app process ends
- No persistent cache = no stale data on restart
- First queries after restart fetch from network

**Note:** This is why we use in-memory cache for financial apps - automatic security on app kill.

---

### Scenario 7: Error Recovery

**Trigger:** Network error or corrupted cache data

**Requirement:** Clear affected cache entry and retry

**Implementation:**

```swift
class ErrorRecoveryManager {
    let cacheManager: UnifiedCacheManager
    
    func handleCacheError(_ error: Error, for query: String) async {
        #if DEBUG
        print("[Cache] Error reading cache for \(query): \(error)")
        #endif
        
        // Clear potentially corrupted cache entry
        await cacheManager.clearCache(forQuery: query)
        
        // Retry with fresh fetch
        // Feature Kit will handle retry logic
    }
}
```

---

### Scenario 8: App Settings Change

**Trigger:** User changes cache settings in Settings.bundle (debug builds)

**Requirement:** Apply new cache settings

**Implementation:**

```swift
class CacheSettingsObserver {
    func observeSettings() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsChanged),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }
    
    @objc private func settingsChanged() {
        // Reload cache configuration
        GraphQLCacheConfig.loadFromSettings()
        
        // Optionally clear existing cache to apply new settings
        if UserDefaults.standard.bool(forKey: "clear_cache_on_settings_change") {
            Task {
                await cacheManager.clearAllCaches()
            }
        }
    }
}
```

---

### Cache Clearing Decision Matrix

| Scenario | Clear REST | Clear GraphQL | Clear WebView | Clear Timestamps | Security Priority |
|----------|-----------|--------------|--------------|-----------------|------------------|
| **Logout** | ✅ All | ✅ All | ✅ Yes | ✅ Yes | **Critical** |
| **Account Switch** | ✅ Account-specific | ✅ Account-specific | ❌ No | ✅ Account-specific | High |
| **Session Expiry** | ✅ All | ✅ All | ✅ Yes | ✅ Yes | **Critical** |
| **Pull to Refresh** | ❌ No (update) | ❌ No (update) | ❌ No | ✅ Yes (update) | Low |
| **Stale Timeout** | ❌ No (auto-fetch) | ❌ No (auto-fetch) | ❌ No | ⚠️ Check | Low |
| **App Restart** | ✅ Auto-cleared | ✅ Auto-cleared | ❌ No | ✅ Auto-cleared | Medium |
| **Error Recovery** | ✅ Affected entry | ✅ Affected entry | ❌ No | ✅ Affected entry | Medium |
| **Settings Change** | ⚠️ Optional | ⚠️ Optional | ❌ No | ⚠️ Optional | Low |

---

### Unified Cache Manager Interface

Complete interface for all cache clearing operations:

```swift
public protocol UnifiedCacheManager {
    // Complete clearing (logout, session expiry)
    func clearAllCaches() async
    
    // Account-specific clearing
    func clearCache(forAccountId accountId: String) async
    
    // Query-specific clearing (error recovery)
    func clearCache(forQuery query: String) async
    
    // GraphQL-only clearing
    func clearGraphQLCache() async
    
    // REST-only clearing
    func clearRESTCache() async
    
    // Timestamp clearing (for debugging)
    func clearTimestamps() async
}
```

---

### Testing Cache Clearing

```swift
class CacheClearing Tests: XCTestCase {
    func testLogoutClearsAllCaches() async {
        // 1. Populate caches
        let _ = await getBalanceUseCase.execute(accountId: "123")
        let _ = await getProfileUseCase.execute()
        
        // 2. Verify caches populated
        XCTAssertNotNil(getCachedBalance(accountId: "123"))
        XCTAssertNotNil(getCachedProfile())
        
        // 3. Logout
        await sessionManager.logout()
        
        // 4. Verify all caches cleared
        XCTAssertNil(getCachedBalance(accountId: "123"))
        XCTAssertNil(getCachedProfile())
    }
    
    func testAccountSwitchClearsOnlyAccountData() async {
        // 1. Populate caches
        let _ = await getBalanceUseCase.execute(accountId: "123")
        let _ = await getProfileUseCase.execute()
        
        // 2. Switch account
        await cacheManager.clearCache(forAccountId: "123")
        
        // 3. Verify account cache cleared, profile retained
        XCTAssertNil(getCachedBalance(accountId: "123"))
        XCTAssertNotNil(getCachedProfile())  // ← Profile should remain
    }
}
```

---

### Summary: Cache Clearing

**Critical Security Requirement:**
- ✅ Clear ALL caches on logout and session expiry
- ✅ Use in-memory cache only (auto-clears on app kill)
- ✅ Implement `clearAllCaches()` method
- ✅ Call during logout flow

**Best Practices:**
1. Document when each clearing method should be used
2. Test cache clearing in all security scenarios
3. Log cache clearing events in debug builds
4. Monitor for cache clearing errors
5. Ensure logout always clears caches (fail-safe)

---

## Unified Cache Manager

This section defines the architecture for a unified cache manager that provides a consistent interface for managing both REST and GraphQL caches.

---

### Architecture Overview

```
Application Layer (ViewModels, Controllers)
    ↓
UnifiedCacheManager (Single interface)
    ├─→ REST Cache Manager (NABAPICoreKit)
    ├─→ GraphQL Cache Manager (APICoreKit - wraps Apollo)
    ├─→ Timestamp Manager (Cache timeouts)
    └─→ WebView Cache Manager
```

**Key Architectural Note:** 
Since Apollo Client is instantiated inside APICoreKit, UnifiedCacheManager doesn't access Apollo directly. Instead, APICoreKit exposes a `GraphQLCacheManaging` protocol that UnifiedCacheManager uses for all GraphQL cache operations.

**Goals:**
1. Single entry point for all cache operations
2. Consistent behavior across REST and GraphQL
3. Centralized cache clearing logic
4. Abstraction over implementation details
5. Proper separation of concerns (MIB doesn't know about Apollo)

---

### APICoreKit Cache Management Interface

Since Apollo Client is instantiated and managed within APICoreKit, APICoreKit must expose a cache management interface that UnifiedCacheManager can use.

**APICoreKit provides:**

```swift
// APICoreKit - GraphQL Cache Management Protocol
public protocol GraphQLCacheManaging {
    /// Clears all GraphQL cache entries
    func clearCache() async
    
    /// Clears cache for a specific account
    func clearCache(forAccountId accountId: String) async
    
    /// Clears cache for a specific query
    func clearCache(forQuery query: String) async
}
```

**APICoreKit implementation:**

```swift
// APICoreKit - Implements cache management
public class GraphQLCacheManager: GraphQLCacheManaging {
    private let apolloClient: ApolloClient
    
    internal init(apolloClient: ApolloClient) {
        self.apolloClient = apolloClient
    }
    
    public func clearCache() async {
        await withCheckedContinuation { continuation in
            apolloClient.clearCache { result in
                #if DEBUG
                switch result {
                case .success:
                    print("[APICoreKit] GraphQL cache cleared successfully")
                case .failure(let error):
                    print("[APICoreKit] Error clearing GraphQL cache: \(error)")
                }
                #endif
                continuation.resume()
            }
        }
    }
    
    public func clearCache(forAccountId accountId: String) async {
        // For normalized cache: remove specific object
        let accountKey = "Account:\(accountId)"
        
        await withCheckedContinuation { continuation in
            apolloClient.store.withinReadWriteTransaction { transaction in
                do {
                    try transaction.removeObject(forKey: accountKey)
                    #if DEBUG
                    print("[APICoreKit] Cleared cache for account: \(accountId)")
                    #endif
                } catch {
                    #if DEBUG
                    print("[APICoreKit] Error clearing account cache: \(error)")
                    #endif
                }
                continuation.resume()
            }
        }
    }
    
    public func clearCache(forQuery query: String) async {
        // Clear specific query from cache
        await withCheckedContinuation { continuation in
            apolloClient.store.withinReadWriteTransaction { transaction in
                do {
                    try transaction.removeObject(forKey: query)
                    #if DEBUG
                    print("[APICoreKit] Cleared cache for query: \(query)")
                    #endif
                } catch {
                    #if DEBUG
                    print("[APICoreKit] Error clearing query cache: \(error)")
                    #endif
                }
                continuation.resume()
            }
        }
    }
}
```

**APICoreKit exposes the cache manager:**

```swift
// APICoreKit - Public interface
public class APICoreKit {
    public let graphQLCacheManager: GraphQLCacheManaging
    private let apolloClient: ApolloClient
    
    public init() {
        // Apollo is private to APICoreKit
        self.apolloClient = ApolloClientFactory.create()
        
        // Expose cache manager
        self.graphQLCacheManager = GraphQLCacheManager(apolloClient: apolloClient)
    }
}
```

**This architecture ensures:**
- ✅ Apollo Client remains encapsulated in APICoreKit
- ✅ MIB/UnifiedCacheManager doesn't need to know about Apollo
- ✅ Clear separation of concerns
- ✅ APICoreKit controls all GraphQL operations

---

### UnifiedCacheManager Protocol Definition

```swift
/// Unified interface for managing all application caches
public protocol UnifiedCacheManager {
    // MARK: - Complete Cache Clearing
    
    /// Clears all caches (REST, GraphQL, timestamps)
    /// Use during logout and session expiry
    func clearAllCaches() async
    
    // MARK: - Selective Cache Clearing
    
    /// Clears GraphQL cache only
    func clearGraphQLCache() async
    
    /// Clears REST cache only
    func clearRESTCache() async
    
    /// Clears cache for specific account
    func clearCache(forAccountId accountId: String) async
    
    /// Clears timestamp tracking (forces re-evaluation of all cache entries)
    func clearTimestamps() async
    
    // MARK: - Cache Inspection (Debug only)
    
    #if DEBUG
    /// Returns cache statistics for debugging
    func getCacheStatistics() -> CacheStatistics
    
    /// Exports cache contents for debugging
    func exportCacheContents() -> String
    #endif
}
```

---

### UnifiedCacheManager Implementation

```swift
public class DefaultUnifiedCacheManager: UnifiedCacheManager {
    
    // Dependencies
    private let restCacheManager: CacheManaging
    private let graphQLCacheManager: GraphQLCacheManaging  // ← APICoreKit's cache manager
    private let timestampCache: NSCache<NSString, QueryTimestamp>
    private let webCacheManager: InternetBankingCacheManaging
    
    public init(
        restCacheManager: CacheManaging,
        graphQLCacheManager: GraphQLCacheManaging,  // ← Not Apollo directly
        timestampCache: NSCache<NSString, QueryTimestamp>,
        webCacheManager: InternetBankingCacheManaging
    ) {
        self.restCacheManager = restCacheManager
        self.graphQLCacheManager = graphQLCacheManager
        self.timestampCache = timestampCache
        self.webCacheManager = webCacheManager
    }
    
    // MARK: - Complete Cache Clearing
    
    public func clearAllCaches() async {
        #if DEBUG
        let startTime = Date()
        print("[UnifiedCache] Starting complete cache clear...")
        #endif
        
        // 1. Clear REST caches
        restCacheManager.clearCache()
        
        // 2. Clear GraphQL cache (via APICoreKit)
        await clearGraphQLCache()
        
        // 3. Clear WebView caches
        webCacheManager.clearCache()
        webCacheManager.clearCookie()
        
        // 4. Clear timestamps
        await clearTimestamps()
        
        #if DEBUG
        let duration = Date().timeIntervalSince(startTime)
        print("[UnifiedCache] Complete cache clear finished in \(String(format: "%.2f", duration))s")
        #endif
    }
    
    // MARK: - Selective Cache Clearing
    
    public func clearGraphQLCache() async {
        await graphQLCacheManager.clearCache()
        
        #if DEBUG
        print("[UnifiedCache] GraphQL cache cleared")
        #endif
    }
    
    public func clearRESTCache() async {
        restCacheManager.clearCache()
        
        #if DEBUG
        print("[UnifiedCache] REST cache cleared")
        #endif
    }
    
    public func clearCache(forAccountId accountId: String) async {
        // 1. Clear REST cache for account
        restCacheManager.clearCache(forAccountId: accountId)
        
        // 2. Clear GraphQL cache for account (via APICoreKit)
        await graphQLCacheManager.clearCache(forAccountId: accountId)
        
        #if DEBUG
        print("[UnifiedCache] Cleared cache for account: \(accountId)")
        #endif
    }
    
    public func clearTimestamps() async {
        timestampCache.removeAllObjects()
        
        #if DEBUG
        print("[UnifiedCache] All timestamps cleared")
        #endif
    }
    
    // MARK: - Debug Methods
    
    #if DEBUG
    public func getCacheStatistics() -> CacheStatistics {
        return CacheStatistics(
            restCacheCount: restCacheManager.getCacheCount(),
            graphQLObjectCount: 0,  // Would need to query APICoreKit
            timestampCount: 0,      // NSCache doesn't expose count
            totalMemoryUsage: 0     // Estimate based on objects
        )
    }
    
    public func exportCacheContents() -> String {
        var output = "=== Cache Contents Export ===\n\n"
        
        // REST cache contents
        output += "REST Cache:\n"
        output += restCacheManager.exportContents()
        output += "\n\n"
        
        // GraphQL cache - would need APICoreKit support
        output += "GraphQL Cache:\n"
        output += "Not implemented - requires APICoreKit export method\n"
        output += "\n\n"
        
        // Timestamps
        output += "Timestamps:\n"
        output += "Not implemented - NSCache doesn't expose entries\n"
        
        return output
    }
    #endif
}

#if DEBUG
public struct CacheStatistics {
    public let restCacheCount: Int
    public let graphQLObjectCount: Int
    public let timestampCount: Int
    public let totalMemoryUsage: Int64
}
#endif
```

**Key Changes:**
1. Uses `GraphQLCacheManaging` protocol instead of `ApolloClient`
2. All GraphQL cache operations go through APICoreKit's interface
3. UnifiedCacheManager has no knowledge of Apollo implementation details

---

### Dependency Injection

```swift
// In app initialization (e.g., AppDelegate or DI container)
class CacheDependencyContainer {
    static func createUnifiedCacheManager() -> UnifiedCacheManager {
        // Initialize APICoreKit (creates Apollo client internally)
        let apiCoreKit = APICoreKit()
        
        // Get GraphQL cache manager from APICoreKit
        let graphQLCacheManager = apiCoreKit.graphQLCacheManager
        
        // Get REST cache manager
        let restCacheManager = CacheManager.shared
        
        // Create timestamp cache
        let timestampCache = NSCache<NSString, QueryTimestamp>()
        timestampCache.countLimit = 100  // Limit to 100 entries
        
        // Get WebView cache manager
        let webCacheManager = InternetBankingCacheManager.shared
        
        // Create unified manager
        let unifiedManager = DefaultUnifiedCacheManager(
            restCacheManager: restCacheManager,
            graphQLCacheManager: graphQLCacheManager,  // ← From APICoreKit
            timestampCache: timestampCache,
            webCacheManager: webCacheManager
        )
        
        return unifiedManager
    }
}
```

**Architecture Flow:**
1. APICoreKit initializes and manages Apollo Client internally
2. APICoreKit exposes `GraphQLCacheManaging` protocol
3. UnifiedCacheManager uses the protocol (doesn't know about Apollo)
4. MIB uses UnifiedCacheManager (doesn't know about APICoreKit internals)

**Benefits:**
- ✅ Clear separation of concerns
- ✅ Apollo Client remains encapsulated in APICoreKit
- ✅ MIB layer doesn't depend on Apollo or GraphQL implementation details
- ✅ Easy to test with mock implementations

---

### Usage Examples

#### Example 1: Logout Flow

```swift
class SessionManager {
    let unifiedCacheManager: UnifiedCacheManager
    let authService: AuthService
    let coordinator: AppCoordinator
    
    func logout() async {
        // 1. Logout from server
        do {
            try await authService.logout()
        } catch {
            print("Logout error: \(error)")
            // Continue with cache clearing even if logout fails
        }
        
        // 2. Clear all caches (CRITICAL for security)
        await unifiedCacheManager.clearAllCaches()
        
        // 3. Navigate to login
        await MainActor.run {
            coordinator.showLogin()
        }
    }
}
```

#### Example 2: Account Switch

```swift
class AccountSwitchCoordinator {
    let unifiedCacheManager: UnifiedCacheManager
    
    func switchToAccount(_ accountId: String) async {
        // Clear cache for previous account
        if let currentAccountId = getCurrentAccountId() {
            await unifiedCacheManager.clearCache(forAccountId: currentAccountId)
        }
        
        // Set new account
        setCurrentAccount(accountId)
        
        // Refresh UI (will fetch fresh data for new account)
        await refreshDashboard()
    }
}
```

#### Example 3: Debug Cache Inspector (Debug builds only)

```swift
#if DEBUG
class CacheDebugViewController: UIViewController {
    let unifiedCacheManager: UnifiedCacheManager
    
    @IBAction func showCacheStatistics() {
        let stats = unifiedCacheManager.getCacheStatistics()
        
        let alert = UIAlertController(
            title: "Cache Statistics",
            message: """
            REST Objects: \(stats.restCacheCount)
            GraphQL Objects: \(stats.graphQLObjectCount)
            Timestamps: \(stats.timestampCount)
            Memory: \(stats.totalMemoryUsage / 1024)KB
            """,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    @IBAction func exportCacheContents() {
        let contents = unifiedCacheManager.exportCacheContents()
        
        // Share or save to file
        let activityVC = UIActivityViewController(
            activityItems: [contents],
            applicationActivities: nil
        )
        present(activityVC, animated: true)
    }
    
    @IBAction func clearAllCaches() {
        Task {
            await unifiedCacheManager.clearAllCaches()
            showAlert("All caches cleared")
        }
    }
}
#endif
```

---

### Integration with Existing Code

#### Update Logout Flow

```swift
// Before: Existing logout
func cleanup() {
    cacheManager.clearCache()
    internetBankingCacheManager.clearCache()
    internetBankingCacheManager.clearCookie()
    // ⚠️ GraphQL cache NOT cleared
}

// After: Use unified manager
func cleanup() async {
    await unifiedCacheManager.clearAllCaches()
    // ✅ All caches (REST + GraphQL + WebView) cleared
}
```

---

### Benefits of Unified Manager

✅ **Single Responsibility**
- One component responsible for all cache operations
- Easier to maintain and test
- Clear ownership

✅ **Consistent Interface**
- Same methods work for both REST and GraphQL
- Developers don't need to know implementation details
- Reduces cognitive load

✅ **Guaranteed Completeness**
- `clearAllCaches()` ensures nothing is missed
- Security-critical for logout flow
- Single point of failure = easier to get right

✅ **Centralized Logging**
- All cache operations logged in one place
- Easier debugging and monitoring
- Consistent log format

✅ **Future-Proof**
- New cache types can be added without changing interface
- Abstraction protects consumers from changes
- Can evolve implementation independently

---

### Testing Strategy

```swift
class UnifiedCacheManagerTests: XCTestCase {
    var sut: UnifiedCacheManager!
    var mockRESTCache: MockCacheManager!
    var mockApollo: MockApolloClient!
    
    override func setUp() {
        super.setUp()
        mockRESTCache = MockCacheManager()
        mockApollo = MockApolloClient()
        sut = DefaultUnifiedCacheManager(
            restCacheManager: mockRESTCache,
            apolloClient: mockApollo,
            timestampCache: NSCache(),
            webCacheManager: MockWebCacheManager()
        )
    }
    
    func testClearAllCachesClearsRESTCache() async {
        await sut.clearAllCaches()
        XCTAssertTrue(mockRESTCache.clearCacheCalled)
    }
    
    func testClearAllCachesClearsGraphQLCache() async {
        await sut.clearAllCaches()
        XCTAssertTrue(mockApollo.clearCacheCalled)
    }
    
    func testClearAccountCacheClearsOnlyThatAccount() async {
        await sut.clearCache(forAccountId: "123")
        XCTAssertEqual(mockRESTCache.clearedAccountId, "123")
        XCTAssertFalse(mockRESTCache.clearAllCalled)
    }
}
```

---

### Summary: Unified Cache Manager

**Key Responsibilities:**
1. Provide single interface for all cache operations
2. Coordinate REST and GraphQL cache clearing
3. Ensure complete cache clearing on logout
4. Abstract implementation details from consumers

**Architectural Pattern:**
- UnifiedCacheManager uses `GraphQLCacheManaging` protocol (not Apollo directly)
- APICoreKit exposes this protocol to hide Apollo implementation details
- MIB layer has no knowledge of Apollo or GraphQL specifics
- Clear separation of concerns across layers

**Critical Methods:**
- `clearAllCaches()` - Used during logout (security-critical)
- `clearCache(forAccountId:)` - Used during account switch
- `clearGraphQLCache()` - Used for GraphQL-specific clearing

**Integration Points:**
- SessionManager (logout flow)
- AccountSwitchCoordinator (account switching)
- ErrorRecoveryManager (cache corruption)
- Debug tools (cache inspection)

**Dependencies:**
- REST cache: Via `CacheManaging` protocol
- GraphQL cache: Via `GraphQLCacheManaging` protocol (APICoreKit)
- Timestamp cache: Direct NSCache access
- WebView cache: Via `InternetBankingCacheManaging` protocol

---

## Recommendations

### Summary of Key Decisions

Based on the analysis and architecture options presented, here are the recommended decisions for GraphQL cache management:

---

### Decision 1: Mutation Cache Strategy

**Recommended: Two-Phase Approach**

**Phase 1: Manual Refetch (Strategy 1)**
- Implement manual refetch pattern for all mutations
- MIB explicitly calls affected queries with `.fetchIgnoringCacheData`
- Simple, reliable, and quick to implement

**Phase 2: Optimized Refetch + Normalized Cache (Strategy 2 + Normalized Cache)**
- Migrate to normalized cache with custom keys
- Implement optimized refetch with critical vs. background queries
- Reduce manual refetch needs through automatic cache updates

**Rationale:**
- Phase 1 delivers security and correctness quickly
- Phase 2 optimizes performance without compromising Phase 1
- Allows learning and iteration
- Lower risk than implementing everything at once

---

### Decision 2: Cache Timeout Policy

**Recommended: Per-Query Timeout (Option B)**

**Configuration:**
- Account Balance: 30 seconds
- Transactions: 5 minutes
- User Profile: 15 minutes
- Static Content: 24 hours
- Default: 5 minutes

**Implementation:**
- Start with global default (Phase 1)
- Add per-query configuration (Phase 2)
- Migrate queries to optimal timeouts (Phase 3)

**Rationale:**
- Different data types have different freshness requirements
- Optimizes balance between performance and accuracy
- Can be adjusted based on real-world data

---

### Decision 3: Cache Manager Architecture

**Recommended: Unified Manager (Option B)**

**Implementation:**
- Create `UnifiedCacheManager` protocol
- Single interface for REST and GraphQL caches
- Implement in Phase 1

**Rationale:**
- Simplifies logout flow (security-critical)
- Consistent behavior across cache types
- Easier to maintain long-term
- Future-proof for new cache types

---

### Decision 4: Cache Persistence

**Recommended: In-Memory Only (Option A)**

**Implementation:**
- Continue using `InMemoryNormalizedCache`
- No migration to `SQLiteNormalizedCache`

**Rationale:**
- Better security for financial data
- Auto-cleared on app termination
- Aligns with existing REST cache approach
- Meets PCI DSS requirements

---

### Decision 5: Implementation Approach

**Recommended: Phased Rollout (Option A)**

**Timeline:**
- Phase 1-2: Foundation + Mutation Handling (4 weeks)
- Phase 3-4: Advanced Caching + Optimization (4 weeks)
- Phase 5: Production Rollout + Monitoring (ongoing)

**Rationale:**
- Allows incremental validation and testing
- Lower risk for financial application
- Ability to adjust based on learnings
- Can deliver critical features (logout, mutations) quickly

---

### Decision 6: Normalized Cache Implementation

**Recommended: Gradual Migration**

**Approach:**
1. Implement normalized cache infrastructure (Phase 3)
2. Start with AccountsKit (most used)
3. Migrate other Feature Kits incrementally
4. Keep query-based cache as fallback

**Rationale:**
- Reduces risk of breaking existing functionality
- Allows testing with real usage patterns
- Feature Kits can migrate at their own pace
- Provides clear path forward for all teams

---

### Priority Ranking

| Priority | Feature | Reason | Timeline |
|----------|---------|--------|----------|
| **P0** | Unified Cache Manager | Security: Logout must clear all caches | Phase 1 |
| **P0** | Cache Clearing on Logout | Security: Prevent data leakage | Phase 1 |
| **P0** | Global Cache Timeout | Prevent indefinite staleness | Phase 1 |
| **P0** | Manual Refetch After Mutations | Correctness: Fresh data after changes | Phase 2 |
| **P1** | Per-Query Timeout | Performance: Optimize cache effectiveness | Phase 3 |
| **P1** | Normalized Cache Foundation | Performance: Reduce duplication | Phase 3 |
| **P1** | MIB Cache Policy Integration | Flexibility: Control cache behavior | Phase 2 |
| **P2** | Optimized Refetch Strategy | Performance: Reduce network calls | Phase 4 |
| **P2** | Complete Normalized Cache Migration | Performance: Maximum efficiency | Phase 4+ |
| **P2** | Settings.bundle Configuration | Developer Experience: Debug tools | Phase 3 |

---

### Success Metrics

Track these metrics to validate decisions:

**Security Metrics:**
- Zero data leakage incidents (Target: 0)
- Cache clear time on logout (Target: < 500ms)
- Security audit findings (Target: 0 critical)

**Performance Metrics:**
- Cache hit rate (Target: > 70% Phase 2, > 80% Phase 4)
- API call reduction (Target: 30-40%)
- Average cache response time (Target: < 100ms)
- Memory usage (Target: < 50MB for cache)

**Quality Metrics:**
- Test coverage (Target: > 80%)
- Production error rate (Target: < 1% increase)
- User-reported cache issues (Target: < 5 per month)

**Development Metrics:**
- Time to add new query with caching (Target: < 1 hour)
- Cache-related bugs per sprint (Target: < 2)
- Developer satisfaction score (Target: > 4/5)

---

### Risk Mitigation Summary

**Critical Risks:**

1. **Cache not cleared on logout**
   - Mitigation: Comprehensive testing, security audit
   - Fallback: Manual clear in app termination

2. **Stale data after mutations**
   - Mitigation: Mandatory refetch after mutations
   - Fallback: Network-only policy for critical queries

3. **Performance degradation**
   - Mitigation: Performance tests before each phase
   - Fallback: Disable caching for problematic queries

**Medium Risks:**

4. **Normalized cache complexity**
   - Mitigation: Gradual migration, keep query-based as fallback
   - Fallback: Revert to query-based caching

5. **Feature Kit migration burden**
   - Mitigation: Clear documentation, examples, support
   - Fallback: Allow indefinite use of query-based cache

---

### Next Steps for Stakeholders

**Immediate Actions (This Week):**
1. ✅ Review and approve these recommendations
2. ✅ Confirm resource allocation (1-3 engineers for 8 weeks)
3. ✅ Schedule kickoff meeting with implementation team
4. ✅ Approve Phase 1-2 immediate start

**Before Implementation Starts (Next Week):**
5. ✅ Security team review and sign-off
6. ✅ QA team review test strategy
7. ✅ Finalize Feature Kit coordination plan
8. ✅ Set up monitoring and analytics infrastructure

**Ongoing (During Implementation):**
9. ✅ Weekly progress reviews
10. ✅ Phase gate reviews (end of each phase)
11. ✅ Adjust scope/timeline based on learnings
12. ✅ Prepare for production rollout (Phase 4)

---

### Final Recommendation

**Proceed with the following approach:**

1. **Implement Phase 1-2 immediately** (Weeks 1-4)
   - Unified Cache Manager
   - Logout integration
   - Global timeout
   - Manual refetch after mutations
   - **Deliver critical security and correctness features**

2. **Evaluate after Phase 2** (Week 4)
   - Measure success metrics
   - Gather developer feedback
   - Decide on Phase 3-4 timing and scope

3. **Implement Phase 3-4 as enhancements** (Weeks 5-8)
   - Per-query timeout
   - Normalized cache
   - Optimized refetch
   - **Deliver performance optimizations**

4. **Production rollout with monitoring** (Week 8+)
   - Gradual rollout with feature flags
   - Continuous monitoring
   - Iterate based on data

This approach balances:
- ✅ **Security** (immediate cache clearing)
- ✅ **Correctness** (mutation handling)
- ✅ **Performance** (normalized cache)
- ✅ **Risk** (phased approach)
- ✅ **Flexibility** (can adjust scope)

---

## Appendix

### Quick Reference

**Clear All Caches:**
```swift
await unifiedCacheManager.clearAllCaches()
```

**Clear GraphQL Only:**
```swift
await unifiedCacheManager.clearGraphQLCache()
```

**Refetch After Mutation:**
```swift
// Option 1: Manual
let _ = await getBalanceUseCase.execute(
    accountId: "123",
    cachePolicy: .fetchIgnoringCacheData
)

// Option 2: Centralized
await mutationRefetchManager.refetchAfterMutation(
    .makePayment,
    context: ["accountId": "123"]
)
```

**Configure Cache Timeout:**
```swift
// Global
GraphQLCacheConfig.defaultTimeout = 300  // 5 minutes

// Per-Query
extension GetBalanceQuery: CacheableQuery {
    static var cacheTimeout: TimeInterval? { 30 }
}
```

**Cache Policies:**
```swift
// Cache first (default)
.returnCacheDataElseFetch

// Network only
.fetchIgnoringCacheData

// Cache then network
.returnCacheDataAndFetch

// Cache only
.returnCacheDataDontFetch

// No cache
.fetchIgnoringCacheCompletely
```

---

### Glossary

**Cache Policy:** Configuration that determines how Apollo Client fetches and caches data

**Normalized Cache:** Cache structure where objects are stored by unique identifiers and shared between queries

**Query-Based Cache:** Cache structure where each query result is stored independently

**Cache Key:** Unique identifier used to store and retrieve cached data

**Mutation:** GraphQL operation that modifies data on the server

**Refetch:** Executing a query again to get fresh data from the server

**Timeout:** Duration after which cached data is considered stale

**Unified Cache Manager:** Single interface for managing REST and GraphQL caches

---

### Useful Links

- [Apollo iOS Documentation](https://www.apollographql.com/docs/ios/)
- [Apollo Caching Guide](https://www.apollographql.com/docs/ios/caching/introduction)
- [Apollo Cache Policies](https://www.apollographql.com/docs/ios/caching/cache-policies)
- [GraphQL Best Practices](https://graphql.org/learn/best-practices/)
- [PCI DSS Requirements](https://www.pcisecuritystandards.org/)

---

**Document Version:** 2.0
**Last Updated:** October 28, 2025
**Status:** Updated with comprehensive cache strategy

---

**Document End**
