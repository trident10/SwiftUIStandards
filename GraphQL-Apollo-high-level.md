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
├── APICore/
│   └── GraphQL/
│       ├── GeneratedSchema/        # Apollo-generated schema files
│       └── Infrastructure/         # Apollo client wrapper classes
├── FeatureKits/
│   └── UserKit/
│       ├── GraphQL/                # Feature-specific GraphQL files
│       │   ├── Operations/         # GraphQL queries and mutations
│       │   └── Requests/           # Request implementations
│       └── Models/                 # Domain models
└── schema.graphql                  # GraphQL schema
```

**Modular Design:**
1. Core GraphQL infrastructure and generated schema types in API Core Kit
2. Feature-specific operations and requests in Feature API Kits
3. Clear separation between generated code and hand-written code

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
