# Apollo iOS Caching Integration and Configuration

## Overview

Apollo iOS provides powerful client-side caching through a normalized cache mechanism. Normalized caching stores GraphQL query responses at the object level, improving data consistency, reducing network traffic, and significantly enhancing app performance and responsiveness.

We utilize the **ApolloSQLiteNormalizedCache** to persist cached data across application launches, providing offline support and faster data retrieval.

## Prerequisites

Ensure your project meets the following prerequisites:

* Apollo iOS installed via CocoaPods. Add these dependencies to your Podfile:

```ruby
pod 'Apollo', '~> 1.9'
pod 'Apollo/SQLite', '~> 1.9'
```

* GraphQL schema and generated Swift types are set up and integrated into your project.

## Setting Up Apollo SQLite Normalized Cache

Follow these detailed steps to enable and configure Apollo SQLite normalized caching:

### Step 1: Initialize SQLite Cache

Begin by setting up a SQLite cache to persist data across sessions:

```swift
import Apollo
import ApolloSQLite

// Locate the documents directory on the device
let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!

// Define the SQLite file URL
let sqliteFileURL = documentsURL.appendingPathComponent("apollo_cache.sqlite")

// Initialize the SQLite normalized cache
let sqliteCache = try SQLiteNormalizedCache(fileURL: sqliteFileURL)

// Create an ApolloStore with the initialized SQLite cache
let cacheStore = ApolloStore(cache: sqliteCache)
```

### Step 2: Setup Apollo Client with Cache

Configure your Apollo client to utilize the cache and network transport:

```swift
// Create a default interceptor provider, necessary for request handling
let interceptorProvider = DefaultInterceptorProvider(store: cacheStore)

// Set up the network transport layer pointing to your GraphQL endpoint
let networkTransport = RequestChainNetworkTransport(
    interceptorProvider: interceptorProvider,
    endpointURL: URL(string: "https://api.yourdomain.com/graphql")!
)

// Instantiate ApolloClient with configured network transport and cache store
let apolloClient = ApolloClient(networkTransport: networkTransport, store: cacheStore)
```

## Implementing Cache Policies

To effectively utilize Apollo's caching capabilities, expose cache policy options through your project's abstraction layer (`APICoreKit`). This approach gives developers clear control over data fetching strategies.

### Defining Cache Policies

Define custom policies that map clearly to Apollo’s cache policies:

```swift
enum DataFetchPolicy {
    case networkOnly
    case cacheFirst
    case cacheOnly
    case cacheAndNetwork
}

func fetchGraphQL<Query: GraphQLQuery>(
    query: Query,
    policy: DataFetchPolicy,
    completion: @escaping (Result<Query.Data, Error>) -> Void
) {
    // Map your custom policy to Apollo's built-in cache policies
    let apolloPolicy: CachePolicy
    switch policy {
    case .networkOnly:
        apolloPolicy = .fetchIgnoringCacheData
    case .cacheFirst:
        apolloPolicy = .returnCacheDataElseFetch
    case .cacheOnly:
        apolloPolicy = .returnCacheDataDontFetch
    case .cacheAndNetwork:
        apolloPolicy = .returnCacheDataAndFetch
    }

    // Fetch data using the Apollo client with the specified cache policy
    apolloClient.fetch(query: query, cachePolicy: apolloPolicy, resultHandler: completion)
}
```

## Recommended Caching Strategies and Scenarios

To maintain data consistency and user experience, follow these recommended cache policy scenarios:

* **Initial App Launch & Pull-to-Refresh:** Use `.networkOnly`. Ensures the latest data is retrieved from the server.
* **Navigating to Subsequent Screens:** Utilize `.cacheFirst`. Provides instant load times if data is already cached.
* **User Logout:** Clear the entire cache to prevent data leaks between user sessions:

```swift
apolloClient.store.clearCache { result in
    switch result {
    case .success:
        print("Cache cleared successfully.")
    case .failure(let error):
        print("Cache clearing failed: \(error)")
    }
}
```

## Handling Objects Without Unique Identifiers

Apollo caches objects based on unique identifiers (`id`, `__typename`). When such identifiers aren't present:

* Apollo resorts to caching based on query-path hierarchy.
* To ensure proper caching:

  * Consider updating your GraphQL schema to include unique identifiers.
  * Alternatively, explicitly define composite cache keys through Apollo's type policies for advanced scenarios.

## Advanced Caching Considerations

Advanced caching scenarios, such as mutation caching and direct cache manipulation, are powerful but complex. Currently, these methods are out of scope to maintain simplicity and clarity in caching strategies. Normalized query caching adequately addresses most performance needs without additional complexity.

---

Following this comprehensive guide ensures effective caching practices, resulting in improved app performance and a better user experience.
