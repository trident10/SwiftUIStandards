

# UI Component Library: Principles for Extensible Components

The goal of this document is to ensure that our UI components can be safely extended and modified without causing regressions in existing features. By formalizing our approach, we can empower developers to add new variants and styles while maintaining a high standard of quality and consistency.

### The Core of an Extensible Component

Every component we build must be seen as a **contract**. The public API of the component should be as small and simple as possible, with all the complex, variant-specific logic encapsulated internally.

Our components will consist of three distinct parts:

1.  **The View:** The SwiftUI `View` or UIKit `UIView`. It is **"dumb"** and only responsible for layout and rendering. It should not contain any business logic or conditional statements like `if isLargeVariant`.
2.  **The Configuration:** A `struct` or `class` that acts as the single source of truth for all component logic. This is where we define the component's state, format data, and manage variants. It should be a single, `public` type that is passed into the View's initializer.
3.  **The Variant Protocol:** A **`private`** protocol that defines the unique logic and data for each variant. This protocol acts as a contract for all variant types, ensuring they provide the necessary data and functionality.

-----

### A Concrete Example: `CustomView`

Let's apply this pattern to your `CustomView` example.

#### Step 1: Define the Variant Protocol

This protocol will enforce that every variant provides the data needed by the `CustomView`. It should be `internal` or `private` to prevent client apps from creating new types that break our rules.

```swift
// Private and internal to the UI library
// Only our library should know about this
private protocol CustomViewVariantLogic {
    var formattedTitle: String { get }
    var formattedDescription: String { get }
}
```

#### Step 2: Define Concrete Variant Implementations

Each variant (`.large`, `.medium`, etc.) will have its own `struct` that conforms to the protocol. This is where you encapsulate the specific formatting rules for each variant.

```swift
// Private and internal to the UI library
private struct LargeCustomViewVariant: CustomViewVariantLogic {
    let title: String
    let description: String

    var formattedTitle: String {
        // Apply large variant-specific formatting
        return title.uppercased()
    }

    var formattedDescription: String {
        return description + " - (large)"
    }
}

private struct MediumCustomViewVariant: CustomViewVariantLogic {
    let title: String
    let description: String

    var formattedTitle: String {
        // Apply medium variant-specific formatting
        return title
    }

    var formattedDescription: String {
        return description + " - (medium)"
    }
}
```

#### Step 3: Build the Public API (The Configuration)

The `CustomViewConfiguration` `struct` is the public-facing API. It takes an `enum` as input and maps it to the correct protocol-conforming `struct`. This hides the complexity of variants from the client app.

```swift
public enum CustomViewVariant {
    case large
    case medium
}

public struct CustomViewConfiguration {
    let title: String
    let description: String
    private let variantLogic: CustomViewVariantLogic // The key to preventing regressions

    public init(title: String, description: String, variant: CustomViewVariant) {
        self.title = title
        self.description = description

        // Map the public enum to the private variant logic
        switch variant {
        case .large:
            self.variantLogic = LargeCustomViewVariant(title: title, description: description)
        case .medium:
            self.variantLogic = MediumCustomViewVariant(title: title, description: description)
        }
    }

    // Public properties that access the formatted data
    public var formattedTitle: String {
        return variantLogic.formattedTitle
    }

    public var formattedDescription: String {
        return variantLogic.formattedDescription
    }
}
```

#### Step 4: Use the Configuration in the View

Finally, the `View` simply uses the pre-formatted data from the `Configuration`. It no longer needs to know about `large` or `medium` types, making it much simpler and safer to modify.

```swift
// SwiftUI View
public struct CustomView: View {
    let configuration: CustomViewConfiguration

    public init(configuration: CustomViewConfiguration) {
        self.configuration = configuration
    }

    public var body: some View {
        VStack {
            Text(configuration.formattedTitle)
            Text(configuration.formattedDescription)
        }
    }
}
```

-----

### Key Benefits of This Approach

  * **Prevents Regression:** Adding a new variant means adding a new enum case and a new private `struct` that conforms to the `CustomViewVariantLogic` protocol. This is a local change that cannot accidentally break the logic for other variants.
  * **Encapsulation:** The details of how each variant works are hidden from the client app, providing a clean and predictable public API.
  * **Separation of Concerns:** The View remains pure UI, while the `Configuration` handles data and logic, and the `VariantLogic` protocol ensures all new variants follow the same rules.
  * **Scalability:** As the number of variants grows, this pattern keeps the code organized and manageable.
