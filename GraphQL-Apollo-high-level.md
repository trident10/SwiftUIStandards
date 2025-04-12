# Apollo iOS Integration with API Core Kit

## 1. Introduction

This document outlines the architectural approach for integrating Apollo iOS, a strongly-typed GraphQL client, into our existing API Core Kit. The primary goal is to add GraphQL support while maintaining the current architecture's abstraction layers and modularity. By implementing this integration properly, we will:

- Support both REST and GraphQL API requests through a unified interface
- Hide Apollo implementation details from Feature API Kits
- Maintain our existing separation of concerns
- Enable type-safe GraphQL operations with code generation
- Ensure the system remains testable and maintainable

This document provides the high-level architecture and data flow, not the actual implementation code. Once the architecture is finalized, we will proceed with code generation.

## 2. Apollo iOS Integration Steps

### 2a. Adding Apollo iOS to the Project

1. Add Apollo iOS via Swift Package Manager
2. Install Apollo CLI for code generation
3. Add a build script to run code generation when .graphql files change

### 2b. Setting up Apollo Client Within API Core Kit

**High-Level Architecture:**

```
┌───────────────────┐     ┌───────────────────┐     ┌───────────────────┐
│                   │     │                   │     │                   │
│   Feature API Kit │     │    API Core Kit   │     │  Apollo Client    │
│                   │     │                   │     │                   │
└─────────┬─────────┘     └─────────┬─────────┘     └─────────┬─────────┘
          │                         │                         │
          │                         │                         │
          │                         │                         │
          │  GraphQLRequest        │   GraphQLOperation      │
          ├────────────────────────►│                        │
          │                         ├────────────────────────►│
          │                         │                         │
          │                         │   Apollo Response       │
          │    API Response         │◄────────────────────────┤
          │◄────────────────────────┤                         │
          │                         │                         │
          │                         │                         │
```

The Apollo client is encapsulated within the API Core Kit and not directly exposed to Feature API Kits. A wrapper class will be created to manage the Apollo client instance and handle Apollo-specific configurations:

## 3. Maintaining Abstraction

### 3a. Hiding Apollo Client Types and Interfaces

**Architectural Approach:**

We'll use the adapter pattern to isolate Apollo-specific code and provide a clean abstraction layer:

```
┌───────────────────────────────────────────────────────────┐
│                        API Core Kit                        │
│                                                           │
│  ┌─────────────────┐       ┌─────────────────────────┐    │
│  │                 │       │                         │    │
│  │ GraphQLRequest  │       │  GraphQLOperation       │    │
│  │   (Public)      │───────│    (Internal)           │    │
│  │                 │       │                         │    │
│  └─────────────────┘       └─────────────┬───────────┘    │
│                                          │                │
│                                          │                │
│                               ┌──────────▼──────────┐     │
│                               │                     │     │
│                               │  Apollo Client      │     │
│                               │    (Internal)       │     │
│                               │                     │     │
│                               └─────────────────────┘     │
└───────────────────────────────────────────────────────────┘
```

Key Components:
1. Public protocols that Feature API Kits will implement:
   - `GraphQLRequest`: A public protocol extending the existing Request protocol
   - Each request will specify its operation type and response data type

2. Internal adapter layer:
   - `GraphQLOperation`: An internal protocol that bridges to Apollo's types
   - Adapters to convert between Apollo types and our internal types

### 3b. Creating Wrapper Classes or Protocols

**Architectural Approach:**

We'll extend the existing Repository/Service pattern to support GraphQL operations:

```
┌─────────────────────┐     
│                     │     
│  Repository Protocol│     
│  (+ GraphQL Method) │     
└──────────┬──────────┘     
           │                
           │ implements    
           │                
┌──────────▼──────────────────────────────────────────┐
│                                                     │
│                   Service Class                     │
│                                                     │
│  ┌─────────────────┐       ┌─────────────────────┐  │
│  │                 │       │                     │  │
│  │   HTTPClient    │       │   GraphQLClient     │  │
│  │  (For REST)     │       │  (For GraphQL)      │  │
│  └─────────────────┘       └─────────────────────┘  │
│                                       △             │
│  ┌─────────────────────────────────────────────┐    │
│  │                                             │    │
│  │           Error Mapping Functions           │    │
│  │         (Reused for both REST/GraphQL)      │    │
│  └─────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────┘
                              │
                              │ conforms to
                              ▼
                  ┌─────────────────────┐
                  │                     │
                  │  ApolloClient      │
                  │  (Implementation)   │
                  │                     │
                  └─────────────────────┘
```

Key Components:
1. Update the Repository protocol with a new method for GraphQL operations:
   - Add a method to handle GraphQL requests
   - Maintain compatibility with existing REST methods

2. Extend the Service class implementation:
   - Service currently has a private HTTPClient property for REST calls
   - Add a new private GraphQLClient property to handle GraphQL operations
   - Inject an ApolloClient instance as the GraphQLClient implementation
   - Reuse existing error mapping functions for both REST and GraphQL errors

3. Create a GraphQLClient protocol:
   - Define a protocol that the ApolloClient will conform to
   - Implement the protocol with Apollo-specific code
   - This enables easy substitution of Apollo with alternative implementations

## 4. Handling GraphQL Requests and Responses

### 4a. Creating GraphQL Requests in Feature API Kits

**Architectural Flow:**

```
┌──────────────────────────────────────────────────────────┐
│                    Feature API Kit                        │
│                                                          │
│  ┌─────────────────┐       ┌─────────────────────────┐   │
│  │                 │       │                         │   │
│  │ Domain Request  │───────│  GraphQLRequest         │   │
│  │                 │       │  Implementation         │   │
│  └─────────────────┘       └─────────────┬───────────┘   │
│                                          │               │
└──────────────────────────────────────────┼───────────────┘
                                           │
                                           │
                                           ▼
┌──────────────────────────────────────────────────────────┐
│                     API Core Kit                         │
└──────────────────────────────────────────────────────────┘
```

Feature API Kits will:
1. Define GraphQL operations in .graphql files
2. Implement the `GraphQLRequest` protocol:
   - Specify the operation type (generated by Apollo)
   - Define mapping logic from GraphQL types to domain models
3. Hide Apollo-generated types from their public interfaces

### 4b. Processing Requests Using Apollo Client

**Request Flow:**

```
┌───────────────┐     ┌───────────────┐     ┌───────────────┐     ┌───────────┐
│               │     │               │     │               │     │           │
│  Feature      │     │  Repository/  │     │  GraphQL      │     │  Apollo   │
│  API Kit      │     │  Service      │     │  Client       │     │  Client   │
│               │     │               │     │               │     │           │
└─────┬─────────┘     └───────┬───────┘     └───────┬───────┘     └─────┬─────┘
      │                       │                     │                   │
      │ 1. Feature creates    │                     │                   │
      │ GraphQLRequest        │                     │                   │
      ├───────────────────────►                     │                   │
      │                       │                     │                   │
      │                       │ 2. Apply Request    │                   │
      │                       │ Interceptors        │                   │
      │                       ├────────────────────►│                   │
      │                       │                     │                   │
      │                       │                     │ 3. Convert to     │
      │                       │                     │ Apollo Operation  │
      │                       │                     ├───────────────────►
      │                       │                     │                   │
      │                       │                     │ 4. Apollo Result  │
      │                       │                     │◄───────────────────
      │                       │                     │                   │
      │                       │ 5. Response with    │                   │
      │                       │ mapped data         │                   │
      │                       │◄────────────────────┤                   │
      │                       │                     │                   │
      │                       │ 6. Apply Response   │                   │
      │                       │ Interceptors        │                   │
      │                       │                     │                   │
      │ 7. Domain Response    │                     │                   │
      │◄───────────────────────                     │                   │
      │                       │                     │                   │
```

**Detailed Process Flow:**

1. **GraphQL Request Creation in Feature Kit**:
   - Feature Kit defines GraphQL operations in `.graphql` files
   - Apollo codegen generates Swift types for these operations during build
   - Feature Kit creates a request that conforms to `GraphQLRequest` protocol
   - This request encapsulates:
     - Input parameters for the GraphQL operation
     - Reference to generated Apollo operation type
     - Mapping logic from GraphQL response to domain model

2. **Request Submission to Repository/Service**:
   - Feature Kit calls the GraphQL method on Repository interface
   - Service implementation receives the request

3. **Request Interceptor Processing**:
   - Request interceptors are applied in sequence to the GraphQL request
   - Common interceptors include:
     - Authentication: Adding authorization headers
     - Logging: Recording request details for debugging
     - Caching: Setting cache policies for the request
     - Metrics: Adding timing and performance tracking
   - Each interceptor can modify the request before it proceeds

4. **GraphQL Client Processing**:
   - Service delegates to the GraphQLClient (Apollo wrapper)
   - GraphQLClient extracts the operation from the request
   - Converts our domain request to Apollo-specific operation format

5. **Apollo Client Execution**:
   - Apollo client executes the GraphQL operation against the server
   - Handles network communication and protocol details
   - Applies any Apollo-specific settings (caching, retry logic, etc.)
   - Returns a typed GraphQL result with data and/or errors

6. **Response Processing**:
   - GraphQLClient receives Apollo response
   - Checks for GraphQL-specific errors
   - Maps Apollo data to domain model using request's mapping function
   - Creates a standardized Response object with:
     - Mapped domain data
     - Metadata (cache status, operation details, etc.)

7. **Response Interceptor Processing**:
   - Response interceptors are applied in sequence
   - Common interceptors include:
     - Error processing: Standardizing error formats
     - Logging: Recording response details
     - Analytics: Tracking API response patterns
     - Validation: Ensuring response meets expected format

8. **Return to Feature Kit**:
   - Feature Kit receives the fully processed domain response
   - Works directly with domain objects, completely isolated from GraphQL/Apollo details

### 4c. Converting Apollo Responses

**Response Mapping Flow:**

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│                 │     │                 │     │                 │
│ Apollo Response │     │  GraphQL Data   │     │ Domain Response │
│                 │     │                 │     │                 │
└────────┬────────┘     └────────┬────────┘     └────────┬────────┘
         │                       │                       │
         │                       │                       │
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│                     Response Mapping Process                    │
│                                                                 │
│  1. Extract data from Apollo response                           │
│  2. Check for GraphQL-specific errors                           │
│  3. Apply request's mapping function to convert to domain model │
│  4. Create Response object with metadata                        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

The mapping process will:
1. Extract data from Apollo's response
2. Apply the request's mapping function to convert to domain models
3. Include relevant metadata (cache status, etc.)

### 4d. Error Handling and Conversion

**Error Mapping Flow:**

```
┌─────────────────────┐
│                     │
│    Apollo Error     │
│                     │
└──────────┬──────────┘
           │
           │
           ▼
┌─────────────────────────────────────────────┐
│                                             │
│            Error Classification             │
│                                             │
│  ┌───────────┐  ┌───────────┐  ┌──────────┐ │
│  │           │  │           │  │          │ │
│  │ GraphQL   │  │ Network   │  │ Other    │ │
│  │ Errors    │  │ Errors    │  │ Errors   │ │
│  │           │  │           │  │          │ │
│  └─────┬─────┘  └─────┬─────┘  └────┬─────┘ │
│        │              │             │       │
└────────┼──────────────┼─────────────┼───────┘
         │              │             │
         │              │             │
         ▼              ▼             ▼
┌─────────────────────────────────────────────┐
│                                             │
│        API Core Kit Error Hierarchy         │
│                                             │
└─────────────────────────────────────────────┘
```

The error handling system will:
1. Classify Apollo errors by type
2. Map to corresponding API Core Kit error types
3. Preserve relevant error details for debugging

## 5. Apollo Script Usage

### 5a. Using Apollo Codegen

**Code Generation Workflow:**

```
┌───────────────────┐     ┌───────────────────┐     ┌───────────────────┐
│                   │     │                   │     │                   │
│  Schema Definition│     │  GraphQL          │     │  Apollo CLI       │
│  (.graphql)       ├────►│  Operations       ├────►│  Code Generator   │
│                   │     │  (.graphql)       │     │                   │
└───────────────────┘     └───────────────────┘     └─────────┬─────────┘
                                                              │
                                                              │
                                                              ▼
                                                   ┌───────────────────┐
                                                   │                   │
                                                   │  Generated Swift  │
                                                   │  Types            │
                                                   │                   │
                                                   └───────────────────┘
```

The code generation process will:
1. Use a configuration file to define input/output settings
2. Generate Swift types from GraphQL schema and operations
3. Support Swift Package Manager for modular organization

### 5b. Placement of Generated Files

**Project Structure:**

```
ProjectRoot/
├── APICoreKit/
│   ├── Common/
│   │   ├── Protocols/
│   │   │   ├── Repository.swift          # Protocol with both REST and GraphQL methods
│   │   │   ├── Request.swift             # Base request protocol
│   │   │   └── Response.swift            # Response structure definitions
│   │   ├── Interceptors/
│   │   │   ├── RequestInterceptor.swift  # Request modification before execution
│   │   │   └── ResponseInterceptor.swift # Response processing after execution
│   │   └── Errors/
│   │       └── APIError.swift            # Unified error types for REST and GraphQL
│   ├── REST/
│   │   ├── HTTPClient.swift              # Client for REST API calls
│   │   └── RESTRequest.swift             # REST-specific request implementation
│   ├── GraphQL/
│   │   ├── Client/
│   │   │   ├── GraphQLClient.swift       # Protocol defining GraphQL client interface
│   │   │   └── ApolloClientWrapper.swift # Apollo implementation of GraphQLClient
│   │   ├── Infrastructure/
│   │   │   ├── ApolloProvider.swift      # Direct Apollo client wrapper
│   │   │   └── GraphQLErrorMapper.swift  # Maps Apollo errors to API errors
│   │   ├── Requests/
│   │   │   └── GraphQLRequest.swift      # GraphQL request protocol
│   │   └── GeneratedSchema/              # Apollo-generated schema types
│   │       ├── SchemaMetadata.swift      # Generated schema information
│   │       ├── Objects.swift             # Generated object types
│   │       ├── InputObjects.swift        # Generated input object types
│   │       ├── Enums.swift               # Generated enum types
│   │       └── Interfaces.swift          # Generated interface types
│   └── Services/
│       └── Service.swift                 # Implements Repository with both clients
├── FeatureKits/
│   └── UserKit/                          # Example feature kit
│       ├── Repository/
│       │   └── UserRepository.swift      # Feature-specific repository interface
│       ├── Service/
│       │   └── UserService.swift         # Feature-specific service implementation
│       ├── Models/
│       │   └── User.swift                # Domain models
│       └── GraphQL/
│           ├── Operations/
│           │   └── User.graphql          # GraphQL operation definitions
│           ├── Generated/                # Feature-specific generated operation code
│           │   └── UserOperations.swift  # Generated from User.graphql
│           └── Requests/
│               └── GetUserRequest.swift  # GraphQL request implementations
└── schema.graphql                        # Main GraphQL schema
```

**Apollo Generated Files Explained:**

Apollo's code generation creates two types of Swift files:

1. **Schema Type Definitions** (in APICoreKit):
   - Generated from your main `schema.graphql` file
   - Shared across all Feature Kits
   - Placed in `APICoreKit/GraphQL/GeneratedSchema/`

2. **Operation-Specific Files** (in Feature Kits):
   - Generated from individual `.graphql` files in each Feature Kit
   - Specific to that Feature Kit's queries/mutations
   - Placed in each Feature Kit's `GraphQL/Generated/` directory

**Example: Schema Type Definitions**

For this GraphQL schema snippet:

```graphql
# schema.graphql
type User {
  id: ID!
  name: String!
  email: String!
  role: UserRole!
}

enum UserRole {
  ADMIN
  EDITOR
  VIEWER
}

input UserInput {
  name: String!
  email: String!
  role: UserRole!
}
```

Apollo would generate these types in `APICoreKit/GraphQL/GeneratedSchema/`:

```swift
// Objects.swift
public struct User: GraphQLObject {
  public static let typename = "User"
  public static let possibleTypes = ["User"]
  
  public var id: GraphQLID { __data["id"] }
  public var name: String { __data["name"] }
  public var email: String { __data["email"] }
  public var role: UserRole { __data["role"] }
  
  // Internal implementation details...
}

// Enums.swift
public enum UserRole: String, GraphQLEnum {
  case admin = "ADMIN"
  case editor = "EDITOR"
  case viewer = "VIEWER"
}

// InputObjects.swift
public struct UserInput: GraphQLInputObject {
  public var name: String
  public var email: String
  public var role: UserRole
  
  public init(name: String, email: String, role: UserRole) {
    self.name = name
    self.email = email
    self.role = role
  }
  
  // Internal conversion methods...
}
```

**Example: Operation-Specific Generated Code**

For a GraphQL operation in a Feature Kit:

```graphql
# UserKit/GraphQL/Operations/User.graphql
query GetUser($id: ID!) {
  user(id: $id) {
    id
    name
    email
    role
  }
}

mutation CreateUser($input: UserInput!) {
  createUser(input: $input) {
    id
    name
    email
  }
}
```

Apollo would generate this code in `UserKit/GraphQL/Generated/UserOperations.swift`:

```swift
// UserOperations.swift
public final class GetUserQuery: GraphQLQuery {
  public static let operationName: String = "GetUser"
  public static let document: DocumentType = .notPersisted(
    definition: "query GetUser($id: ID!) { user(id: $id) { id name email role } }"
  )
  
  public var id: GraphQLID
  
  public init(id: GraphQLID) {
    self.id = id
  }
  
  public var variables: GraphQLMap? {
    return ["id": id]
  }
  
  public struct Data: GraphQLSelectionSet {
    public var user: User?
    
    // Selection set implementation...
  }
}

public final class CreateUserMutation: GraphQLMutation {
  public static let operationName: String = "CreateUser"
  public static let document: DocumentType = .notPersisted(
    definition: "mutation CreateUser($input: UserInput!) { createUser(input: $input) { id name email } }"
  )
  
  public var input: UserInput
  
  public init(input: UserInput) {
    self.input = input
  }
  
  public var variables: GraphQLMap? {
    return ["input": input]
  }
  
  public struct Data: GraphQLSelectionSet {
    public var createUser: User
    
    // Selection set implementation...
  }
}
```

**Using Generated Code in Feature Kit Requests:**

```swift
// UserKit/GraphQL/Requests/GetUserRequest.swift
import APICoreKit
// This import gives access to the schema types and the repository pattern
import UserKitGenerated 
// This import gives access to the operation-specific generated code

public struct GetUserRequest: GraphQLRequest {
    public typealias Operation = GetUserQuery
    public typealias ResponseData = UserDomainModel
    
    private let userId: String
    
    public init(userId: String) {
        self.userId = userId
    }
    
    public var operation: Operation {
        return GetUserQuery(id: userId)
    }
    
    public func map(data: Operation.Data) throws -> UserDomainModel {
        guard let userData = data.user else {
            throw APIError.responseMappingFailed("User data not found")
        }
        
        return UserDomainModel(
            id: userData.id,
            name: userData.name,
            email: userData.email,
            role: mapRole(userData.role)
        )
    }
    
    private func mapRole(_ graphQLRole: UserRole) -> UserDomainModel.Role {
        switch graphQLRole {
        case .admin: return .administrator
        case .editor: return .contentEditor
        case .viewer: return .readOnlyUser
        }
    }
}
```

This approach provides a clean separation between:
1. **Schema Types**: Shared, reusable types based on your GraphQL schema (in APICoreKit)
2. **Operation Code**: Feature-specific query/mutation classes (in each Feature Kit)
3. **Request Implementations**: Your custom code that connects Apollo operations to your domain models

To configure Apollo codegen for this structure, use:

```json
{
  "schemaNamespace": "GraphQLAPI",
  "input": {
    "operationSearchPaths": ["**/*.graphql"],
    "schemaSearchPaths": ["schema.graphql"]
  },
  "output": {
    "schemaTypes": {
      "path": "./APICoreKit/GraphQL/GeneratedSchema",
      "moduleType": {
        "swiftPackageManager": {}
      }
    },
    "operations": {
      "relative": true,
      "relativeOutputPath": "./Generated"
    }
  }
}
```

## 6. Future-proofing Considerations

### 6a. Minimizing Impact of Client Changes

**Abstraction Layers:**

```
┌─────────────────────────────────────────────────────────┐
│                  Application Layer                      │
│                                                         │
│  ┌─────────────────────────────────────────────────┐    │
│  │              Feature API Kits                   │    │
│  └─────────────────────────────────────────────────┘    │
│                         │                               │
│                         │ Uses                          │
│                         ▼                               │
│  ┌─────────────────────────────────────────────────┐    │
│  │              API Core Kit Public API            │    │
│  └─────────────────────────────────────────────────┘    │
└─────────────────────────┬───────────────────────────────┘
                          │
                          │ Implements
                          ▼
┌─────────────────────────────────────────────────────────┐
│               Implementation Layer                      │
│                                                         │
│  ┌─────────────────────────────────────────────────┐    │
│  │        GraphQL Client Provider Protocol         │    │
│  └─────────────────────────────────────────────────┘    │
│                         │                               │
│                         │ Implements                    │
│                         ▼                               │
│  ┌─────────────────────────────────────────────────┐    │
│  │         Apollo-Specific Implementation          │    │
│  └─────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
```

Key strategies:
1. Use a façade pattern for all Apollo interactions
   - Define a client-agnostic GraphQL provider protocol
   - Implement the protocol with Apollo-specific code internally

2. Compile-time configuration options
   - Allow switching between different GraphQL client implementations
   - Keep all client-specific code isolated

### 6b. Best Practices for Separation

**Separation of Concerns:**

```
┌─────────────────────────────────────────────────────────┐
│                  Domain Layer                           │
│                                                         │
│  ┌─────────────────────┐     ┌─────────────────────┐    │
│  │                     │     │                     │    │
│  │   Domain Models     │     │   Business Logic    │    │
│  │                     │     │                     │    │
│  └─────────────────────┘     └─────────────────────┘    │
└─────────────────────────────────────────────────────────┘
                 ▲                       ▲
                 │                       │
                 │                       │
┌────────────────┼───────────────────────┼────────────────┐
│                │    Mapping Layer      │                │
│                │                       │                │
│  ┌─────────────┼───────────────────────┼─────────────┐  │
│  │             │                       │             │  │
│  │        Request/Response Mappers                   │  │
│  │                                                   │  │
│  └───────────────────────────────────────────────────┘  │
└─────────────────────────┬───────────────────────────────┘
                          │
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│               GraphQL Layer                             │
│                                                         │
│  ┌─────────────────────┐     ┌─────────────────────┐    │
│  │                     │     │                     │    │
│  │ Generated GraphQL   │     │  Apollo Client      │    │
│  │ Types               │     │                     │    │
│  └─────────────────────┘     └─────────────────────┘    │
└─────────────────────────────────────────────────────────┘
```

Best practices:
1. Clear separation between domain and GraphQL-specific code:
   - Domain models should be free of GraphQL-specific annotations
   - Use mapper classes to convert between GraphQL types and domain models
   - Never expose generated GraphQL types in public APIs

2. Dependency injection for client implementations:
   - Inject the GraphQL client provider into the API Client
   - Support mock implementations for testing

3. Testing strategy:
   - Create mock providers that don't depend on Apollo
   - Enable unit testing without GraphQL infrastructure

## 7. Implementation Examples

### 7a. Apollo Client Wrapper

**High-Level Design:**

```
┌───────────────────────────────────────────────────────────┐
│                      ApolloProvider                       │
│                                                           │
│  ┌─────────────────┐       ┌─────────────────────────┐    │
│  │                 │       │                         │    │
│  │ Apollo Client   │       │  Cache Configuration    │    │
│  │ Configuration   │       │                         │    │
│  └─────────────────┘       └─────────────────────────┘    │
│                                                           │
│  ┌─────────────────────────────────────────────────────┐  │
│  │                                                     │  │
│  │                Query Execution                      │  │
│  │                                                     │  │
│  └─────────────────────────────────────────────────────┘  │
│                                                           │
│  ┌─────────────────────────────────────────────────────┐  │
│  │                                                     │  │
│  │              Mutation Execution                     │  │
│  │                                                     │  │
│  └─────────────────────────────────────────────────────┘  │
│                                                           │
└───────────────────────────────────────────────────────────┘
```

Key components:
1. Apollo client instance with proper configuration
2. Cache implementation and configuration
3. Methods to execute GraphQL operations (queries, mutations)
4. Async/await adapters for Apollo's callback-based API

### 7b. GraphQL Request Implementation

**Component Structure:**

```
┌───────────────────────────────────────────────────────────┐
│                   Feature API Kit                         │
│                                                           │
│  ┌─────────────────────────────────────────────────────┐  │
│  │               GraphQL Operation File                │  │
│  │                                                     │  │
│  │  query GetUser($id: ID!) {                         │  │
│  │    user(id: $id) {                                 │  │
│  │      id                                            │  │
│  │      name                                          │  │
│  │      email                                         │  │
│  │    }                                               │  │
│  │  }                                                 │  │
│  └─────────────────────────────────────────────────────┘  │
│                                                           │
│  ┌─────────────────────────────────────────────────────┐  │
│  │               Request Implementation                │  │
│  │                                                     │  │
│  │  - Implements GraphQLRequest protocol               │  │
│  │  - References generated operation                   │  │
│  │  - Provides mapping logic to domain models          │  │
│  │                                                     │  │
│  └─────────────────────────────────────────────────────┘  │
│                                                           │
│  ┌─────────────────────────────────────────────────────┐  │
│  │               Domain Model                          │  │
│  │                                                     │  │
│  │  - Clean, GraphQL-agnostic model                    │  │
│  │  - Used by the rest of the application              │  │
│  │                                                     │  │
│  └─────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────┘
```

Flow:
1. GraphQL queries defined in .graphql files
2. Apollo generates Swift types for these operations
3. Feature Kit implements GraphQLRequest protocol
4. Request provides mapping from GraphQL data to domain models

### 7c. Response Mapping Architecture

**Data Flow:**

```
┌───────────────────┐     ┌───────────────────┐     ┌───────────────────┐
│                   │     │                   │     │                   │
│ Apollo Response   │────►│ Response Mapping  │────►│ Domain Response   │
│                   │     │                   │     │                   │
└───────────────────┘     └───────────────────┘     └───────────────────┘
        │                         │                         │
        │                         │                         │
        ▼                         ▼                         ▼
┌───────────────────┐     ┌───────────────────┐     ┌───────────────────┐
│                   │     │                   │     │                   │
│ GraphQL Errors    │────►│ Error Mapping     │────►│ Domain Errors     │
│                   │     │                   │     │                   │
└───────────────────┘     └───────────────────┘     └───────────────────┘
```

Key processes:
1. Extract data from Apollo response
2. Handle GraphQL-specific errors
3. Map to domain models using request's mapping function
4. Create standardized Response object with metadata
5. Apply response interceptors

---

This architectural document provides a high-level approach to integrating Apollo iOS with the existing API Core Kit while maintaining the current architecture's integrity. It outlines the key components, data flows, and design patterns without getting into implementation details. Once this architecture is finalized, we can proceed with actual code implementation.
