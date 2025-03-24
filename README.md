# SwiftUI Coding Standards and Best Practices

## Introduction

This document provides comprehensive guidelines, standards, and best practices for SwiftUI development. Following these principles will help maintain code quality, consistency, and readability across your SwiftUI projects. These standards are designed to leverage SwiftUI's declarative syntax while avoiding common pitfalls.

As SwiftUI continues to evolve, adhering to established patterns becomes increasingly important for creating maintainable, performant, and scalable applications. This guide aims to serve as a reference for developers of all experience levels working with SwiftUI.

The examples provided demonstrate both recommended approaches and anti-patterns to avoid. By following these guidelines, development teams can ensure consistency in code style, improve collaboration, and reduce technical debt.


## 1. View Structure and Organization

### Overview
Proper view structure is crucial in SwiftUI projects. Well-organized views improve readability, maintainability, and performance. This section covers how to structure and organize your SwiftUI views effectively.

### Best Practices
- Keep views small and focused on a single responsibility
- Extract reusable components into separate views
- Use private extensions to organize view modifiers
- Implement computed properties for complex view elements
- Follow a consistent naming convention for views and their components
- Use ViewBuilders for reusable view compositions

### Things to Avoid
- Creating large, monolithic views with multiple responsibilities
- Duplicating view code instead of extracting reusable components
- Nesting too many views, which can impact performance
- Mixing business logic with view code

### Considerations
- Balance between small components and over-fragmentation
- Performance implications of view extraction (SwiftUI optimizes many extractions automatically)
- Readability vs. conciseness

### Good Example
```swift
struct ProductDetailView: View {
    let product: Product
    @State private var quantity = 1
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            productHeader
            productDescription
            quantitySelector
            addToCartButton
        }
        .padding()
    }
    
    private var productHeader: some View {
        HStack {
            productImage
            productTitlePrice
        }
    }
    
    private var productImage: some View {
        Image(product.imageName)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 100, height: 100)
            .cornerRadius(8)
    }
    
    private var productTitlePrice: some View {
        VStack(alignment: .leading) {
            Text(product.name)
                .font(.headline)
            Text("$\(product.price, specifier: "%.2f")")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    private var productDescription: some View {
        Text(product.description)
            .font(.body)
    }
    
    private var quantitySelector: some View {
        HStack {
            Text("Quantity:")
            Stepper("\(quantity)", value: $quantity, in: 1...10)
        }
    }
    
    private var addToCartButton: some View {
        Button(action: addToCart) {
            Text("Add to Cart")
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
        }
    }
    
    private func addToCart() {
        // Cart logic
    }
}
```

### Bad Example
```swift
struct ProductDetailView: View {
    let product: Product
    @State private var quantity = 1
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // All code in one place, making it difficult to read and maintain
            HStack {
                Image(product.imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 100, height: 100)
                    .cornerRadius(8)
                
                VStack(alignment: .leading) {
                    Text(product.name)
                        .font(.headline)
                    Text("$\(product.price, specifier: "%.2f")")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            Text(product.description)
                .font(.body)
            
            HStack {
                Text("Quantity:")
                Stepper("\(quantity)", value: $quantity, in: 1...10)
            }
            
            Button(action: {
                // Cart logic mixed directly in the view
                print("Adding \(quantity) of \(product.name) to cart")
                // More logic here...
            }) {
                Text("Add to Cart")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
        }
        .padding()
    }
}
```



## 2. State Management

### Overview
Proper state management is critical in SwiftUI applications. SwiftUI offers several property wrappers and approaches to manage state, each with specific use cases and implications.

### Best Practices
- Use the most appropriate property wrapper for each use case:
  - `@State` for simple, view-local state
  - `@Binding` for state passed from a parent
  - `@ObservedObject` for external reference types that can change
  - `@StateObject` for owned reference types that need to persist through view updates
  - `@EnvironmentObject` for dependency injection of shared objects
  - `@AppStorage` for user defaults
  - `@SceneStorage` for UI state persistence between app launches
- Keep state at the highest necessary level, not higher
- Prefer value types (structs) for modeling state where appropriate
- Use readonly computed properties for derived state

### Things to Avoid
- Using `@State` for data that should be shared across views
- Overusing `@EnvironmentObject` for data that only needs to be passed to a few views
- Creating deep property paths with multiple `@Binding` references
- Using mutable global state instead of proper state management
- Mixing different state management approaches unnecessarily

### Considerations
- Performance impact of property wrappers, especially with large objects
- Memory management and potential retain cycles
- Debugging complexity with deeply nested state
- View lifecycle and when state is initialized or reset

### Good Example
```swift
// Parent view creates and owns the state
struct ParentView: View {
    @StateObject private var viewModel = ShoppingCartViewModel()
    
    var body: some View {
        VStack {
            CartSummaryView(itemCount: viewModel.itemCount)
            CartItemsView(items: $viewModel.items)
            
            // Local state for UI elements
            CartActionsView(onCheckout: viewModel.checkout)
        }
    }
}

// Child view receives only what it needs
struct CartSummaryView: View {
    let itemCount: Int
    
    var body: some View {
        Text("Your cart contains \(itemCount) item(s)")
    }
}

// Child view that needs to modify the parent's state
struct CartItemsView: View {
    @Binding var items: [CartItem]
    
    var body: some View {
        List {
            ForEach(items) { item in
                CartItemRow(item: item)
            }
            .onDelete(perform: removeItems)
        }
    }
    
    private func removeItems(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
    }
}

// View with local actions that calls back to parent
struct CartActionsView: View {
    let onCheckout: () -> Void
    @State private var showingConfirmation = false
    
    var body: some View {
        Button("Checkout") {
            showingConfirmation = true
        }
        .alert(isPresented: $showingConfirmation) {
            Alert(
                title: Text("Confirm Checkout"),
                message: Text("Do you want to proceed with checkout?"),
                primaryButton: .default(Text("Yes"), action: onCheckout),
                secondaryButton: .cancel()
            )
        }
    }
}
```

### Bad Example
```swift
// Global state - avoid this pattern
var globalCart = ShoppingCart()

struct BadParentView: View {
    // Using @State for shared data that should be in a model
    @State private var items: [CartItem] = []
    @State private var isCheckingOut = false
    
    var body: some View {
        VStack {
            // Passing too many properties instead of a cohesive model
            BadCartSummaryView(items: items)
            BadCartItemsView(items: $items, isCheckingOut: $isCheckingOut)
            
            Button("Checkout") {
                // Directly modifying global state
                globalCart.items = items
                isCheckingOut = true
                // Business logic embedded in the view
                processCheckout()
            }
        }
    }
    
    func processCheckout() {
        // Complex business logic in the view
        print("Processing checkout...")
    }
}

struct BadCartSummaryView: View {
    // Receiving the entire array when only needing the count
    let items: [CartItem]
    
    var body: some View {
        Text("Your cart contains \(items.count) item(s)")
    }
}

struct BadCartItemsView: View {
    // Receiving state not relevant to this view
    @Binding var items: [CartItem]
    @Binding var isCheckingOut: Bool
    
    var body: some View {
        List {
            ForEach(items) { item in
                Text(item.name)
            }
            .onDelete(perform: { offsets in
                // Directly modifying global state alongside binding
                items.remove(atOffsets: offsets)
                globalCart.items.remove(atOffsets: offsets)
            })
        }
        .disabled(isCheckingOut) // Using a binding that could be a simple parameter
    }
}
```


