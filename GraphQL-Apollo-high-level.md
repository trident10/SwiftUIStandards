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

## 8. Implementation Considerations for Domain-Specific Schema 

### 8a. Schema Splitting Script Example

To create domain-specific schema files, we can implement a script that:

```javascript
// schema-splitter.js
const fs = require('fs');
const { parse, print } = require('graphql');

// Read the main schema
const mainSchema = fs.readFileSync('./schema.graphql', 'utf8');
const parsedSchema = parse(mainSchema);

// Analyze type dependencies
const typeDependencies = {};
const domainTypes = {
  user: [],
  product: [],
  shared: []
};

// Analyze the schema to determine domain ownership
// This could be based on naming conventions, directives, or manual mapping
parsedSchema.definitions.forEach(definition => {
  const typeName = definition.name?.value;
  
  if (!typeName) return;
  
  // Determine domain based on naming prefix, directive, or mapping table
  let domain = 'shared'; // Default domain
  
  if (typeName.startsWith('User') || typeName.match(/User|Auth|Permission/)) {
    domain = 'user';
  } else if (typeName.startsWith('Product') || typeName.match(/Product|Inventory|Catalog/)) {
    domain = 'product';
  }
  
  domainTypes[domain].push(definition);
});

// Generate domain-specific schemas
Object.keys(domainTypes).forEach(domain => {
  if (domain === 'shared') {
    // Create shared schema
    const sharedSchema = print({
      kind: 'Document',
      definitions: domainTypes.shared
    });
    fs.writeFileSync('./SharedKit/GraphQL/Schema/shared-schema.graphql', sharedSchema);
  } else {
    // Create domain-specific schema with imports of shared types
    const domainSchema = print({
      kind: 'Document',
      definitions: domainTypes[domain]
    });
    
    // Add import directive for shared types if the GraphQL implementation supports it
    // or simply note the dependency
    const schemaWithImports = `# This schema depends on shared-schema.graphql\n\n${domainSchema}`;
    fs.writeFileSync(`./${domain.charAt(0).toUpperCase() + domain.slice(1)}Kit/GraphQL/Schema/${domain}-schema.graphql`, schemaWithImports);
  }
});

console.log('Schema splitting complete!');
```

### 8b. Schema Dependencies Management

To handle cross-domain type references:

1. **Explicit Import Statements**:
   ```graphql
   # UserKit/GraphQL/Schema/user-schema.graphql
   # import Role from "shared-schema.graphql"
   
   type User {
     id: ID!
     name: String!
     role: Role! # Reference to a shared type
   }
   ```

2. **Dependency Documentation**:
   ```graphql
   # ProductKit/GraphQL/Schema/product-schema.graphql
   # Dependencies:
   # - Currency (SharedKit)
   # - Inventory (SharedKit)
   
   type Product {
     id: ID!
     price: Currency! # From shared schema
     inventory: Inventory! # From shared schema
   }
   ```

### 8c. Apollo Codegen Run Script

A script to run codegen for all kits:

```bash
#!/bin/bash
# run-apollo-codegen.sh

# Run schema splitter first
node scripts/schema-splitter.js

# Run Apollo codegen for each kit
echo "Generating code for UserKit..."
apollo client:codegen --config=apollo-codegen-config/userkit-config.json

echo "Generating code for ProductKit..."
apollo client:codegen --config=apollo-codegen-config/productkit-config.json

echo "Generating code for shared types..."
apollo client:codegen --config=apollo-codegen-config/shared-config.json

echo "Code generation complete!"
```

### 8d. Managing Schema Evolution

For evolving the schema while maintaining domain boundaries:

1. **Version Control**:
   * Keep all schema files version controlled
   * Establish review processes for schema changes
   * Use pull requests to propose and review schema modifications

2. **Schema Change Workflow**:
   * Developer proposes schema change to main schema
   * Run schema splitter script to update domain-specific schemas
   * Run codegen to verify compatibility with current code
   * Review impacts across Feature Kits

3. **Breaking Change Management**:
   * Use deprecation directives before removing fields
   * Add versioning comments to track schema evolution
   * Communicate schema changes to all Feature Kit owners

---

This architectural document provides a comprehensive approach to integrating Apollo iOS with the existing API Core Kit while maintaining the current architecture's integrity and introducing domain-specific schema organization. It outlines the key components, data flows, and design patterns for a modular, maintainable implementation that scales across multiple Feature Kits.
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

## 5. Apollo Code Generation for Domain-Specific Feature Kits

### 5a. Schema Splitting Strategy

Instead of using a centralized schema approach, we'll split our schema by domain to support modular code generation for each Feature Kit:

**Schema Splitting Architecture:**

```
┌───────────────────────────────────────────────────────────┐
│                  Schema Splitting Process                 │
│                                                           │
│  ┌─────────────────────┐                                  │
│  │                     │                                  │
│  │  Global Schema      │                                  │
│  │  (schema.graphql)   │                                  │
│  │                     │                                  │
│  └──────────┬──────────┘                                  │
│             │                                             │
│             │ Schema Splitter Script                      │
│             │                                             │
│             ▼                                             │
│  ┌──────────────────────────────────────────────────┐     │
│  │                                                  │     │
│  │               Domain Schema Files                │     │
│  │                                                  │     │
│  └──────────────────────────────────────────────────┘     │
│                                                           │
└───────────────────────────────────────────────────────────┘
                          │
                          │
          ┌───────────────┼───────────────┐
          │               │               │
          ▼               ▼               ▼
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│                 │ │                 │ │                 │
│ UserKit Schema  │ │ ProductKit      │ │ Other Feature   │
│                 │ │ Schema          │ │ Kit Schemas     │
│                 │ │                 │ │                 │
└─────────────────┘ └─────────────────┘ └─────────────────┘
```

**Implementation Steps for Schema Splitting:**

1. **Create a Schema Splitter Script**:
   * Parse the full `schema.graphql`
   * Extract User-related types into `UserKit/GraphQL/Schema/user-schema.graphql`
   * Extract Product-related types into `ProductKit/GraphQL/Schema/product-schema.graphql`
   * Ensure references between types are maintained

2. **Handle Shared Types**:
   * Identify types used across multiple domains (e.g., common enums, interfaces)
   * Create a `SharedKit/GraphQL/Schema/shared-schema.graphql` for reused types
   * Import shared types in Feature Kit-specific schema files

3. **Schema Management Guidelines**:
   * Use schema directives to mark domain ownership (e.g., `@domain(name: "user")`)
   * Create documentations for type ownership and dependencies
   * Establish governance process for schema changes that affect multiple domains

### 5b. Kit-Specific Apollo Configurations

Each Feature Kit will have its own Apollo configuration to generate domain-specific code:

**Apollo Configuration Structure:**

```
ProjectRoot/
├── apollo-codegen-config/
│   ├── userkit-config.json         # User Kit specific config
│   ├── productkit-config.json      # Product Kit specific config
│   └── shared-config.json          # Configuration for shared types
└── scripts/
    └── run-apollo-codegen.sh       # Script to run codegen for all kits
```

**Example Configuration for UserKit:**

```json
{
  "schemaNamespace": "UserGraphQL",
  "input": {
    "operationSearchPaths": ["UserKit/GraphQL/Operations/**/*.graphql"],
    "schemaSearchPaths": [
      "UserKit/GraphQL/Schema/user-schema.graphql",
      "SharedKit/GraphQL/Schema/shared-schema.graphql"
    ]
  },
  "output": {
    "schemaTypes": {
      "path": "./UserKit/GraphQL/Generated/Schema",
      "moduleType": {
        "swiftPackageManager": {
          "name": "UserKitSchema"
        }
      }
    },
    "operations": {
      "path": "./UserKit/GraphQL/Generated/Operations",
      "moduleType": {
        "swiftPackageManager": {
          "name": "UserKitOperations"
        }
      }
    }
  }
}
```

### 5c. Generated Code Structure

With this approach, code generation will produce domain-specific types for each kit:

**Project Structure with Domain-Specific Generated Code:**

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
│   └── GraphQL/
│       ├── Client/
│       │   ├── GraphQLClient.swift       # Protocol defining GraphQL client interface
│       │   └── ApolloClientWrapper.swift # Apollo implementation of GraphQLClient
│       └── Infrastructure/
│           ├── ApolloProvider.swift      # Apollo client provider
│           └── GraphQLErrorMapper.swift  # Maps Apollo errors to API errors
├── SharedKit/
│   └── GraphQL/
│       ├── Schema/
│       │   └── shared-schema.graphql     # Shared GraphQL types
│       └── Generated/
│           └── SharedTypes.swift         # Generated code for shared types
├── UserKit/
│   ├── Repository/
│   │   └── UserRepository.swift          # User-specific repository interface
│   ├── Service/
│   │   └── UserService.swift             # User-specific service implementation
│   ├── Models/
│   │   └── User.swift                    # Domain models for users
│   └── GraphQL/
│       ├── Schema/
│       │   └── user-schema.graphql       # User-specific schema types
│       ├── Operations/
│       │   └── User.graphql              # User GraphQL operations
│       └── Generated/
│           ├── Schema/                   # User-specific generated schema types
│           │   ├── UserObjects.swift     # Generated User types
│           │   └── UserEnums.swift       # Generated User enums
│           └── Operations/               # User-specific generated operations
│               └── UserOperations.swift  # Generated User queries/mutations
├── ProductKit/
│   ├── Repository/
│   │   └── ProductRepository.swift       # Product-specific repository
│   ├── Service/
│   │   └── ProductService.swift          # Product-specific service
│   ├── Models/
│   │   └── Product.swift                 # Domain models for products
│   └── GraphQL/
│       ├── Schema/
│       │   └── product-schema.graphql    # Product-specific schema
│       ├── Operations/
│       │   └── Product.graphql           # Product GraphQL operations
│       └── Generated/
│           ├── Schema/                   # Product-specific generated schema types
│           │   ├── ProductObjects.swift  # Generated Product types
│           │   └── ProductEnums.swift    # Generated Product enums
│           └── Operations/               # Product-specific generated operations
│               └── ProductOperations.swift # Generated Product queries/mutations
└── scripts/
    ├── schema-splitter.js                # Script to split schema by domain
    └── run-apollo-codegen.sh             # Script to run code generation
```

### 5d. Using Domain-Specific Generated Code

**Example: Implementing a GraphQL Request in UserKit:**

```swift
// UserKit/GraphQL/Requests/GetUserRequest.swift
import APICoreKit
import UserKitSchema      // Domain-specific schema imports
import UserKitOperations  // Domain-specific operation imports

public struct GetUserRequest: GraphQLRequest {
    public typealias Operation = UserKitOperations.GetUserQuery
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
    
    private func mapRole(_ graphQLRole: UserKitSchema.UserRole) -> UserDomainModel.Role {
        switch graphQLRole {
        case .admin: return .administrator
        case .editor: return .contentEditor
        case .viewer: return .readOnlyUser
        }
    }
}
```

**Benefits of Domain-Specific Code Generation:**

1. **Modularity**:
   - Each Feature Kit contains only the schema types and operations it needs
   - Clearer ownership of GraphQL types and operations
   - Reduced coupling between different domain areas

2. **Build Performance**:
   - Smaller, focused code generation steps
   - Parallel code generation for different Feature Kits
   - Changes to one domain don't trigger regeneration for all kits

3. **Team Collaboration**:
   - Domain teams can own their schema portions
   - Reduced merge conflicts when multiple teams modify the schema
   - Clear boundaries for API responsibilities

4. **Scalability**:
   - Easier to scale as the schema grows
   - New Feature Kits can be added without affecting existing ones
   - Better control over generated code size in each module

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
