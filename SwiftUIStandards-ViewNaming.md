# SwiftUI Development Guidelines and Standards

## 1. Naming Conventions

Consistent naming conventions improve code readability, maintainability, and team collaboration. After careful consideration of industry standards and practical experience, the following guidelines should be applied to all SwiftUI components:

### 1.1 View Type Suffixes

#### 1.1.1 Screen vs. Component Distinction

- **Screen Views**: Views that represent entire screens in the application must be suffixed with `Screen`.
  ```swift
  struct HomeScreen: View {
      var body: some View {
          // Screen content
      }
  }
  
  struct ProfileScreen: View {
      var body: some View {
          // Screen content
      }
  }
  ```

- **Component Views**: Reusable components or sub-views should be suffixed with `View`.
  ```swift
  struct UserAvatarView: View {
      var body: some View {
          // Component content
      }
  }
  
  struct ProductCardView: View {
      var body: some View {
          // Component content
      }
  }
  ```

#### 1.1.2 Naming Convention Rationale

This naming convention provides several benefits:

- **Clear Hierarchy**: Immediately communicates the scope and purpose of each component
- **Navigation Clarity**: Makes screen transitions more obvious in code
- **Organization**: Helps group related files in the project navigator

It's worth noting that this approach differs from Apple's own naming conventions, which typically omit the `View` suffix (e.g., `Text`, `Button`, not `TextView`, `ButtonView`). Our team convention prioritizes explicit role definition over brevity.

#### 1.1.3 Special Considerations

- **Evolving Components**: If a component view evolves to become a screen, ensure its name is updated accordingly
- **Container Views**: Views that serve as containers but aren't full screens should follow the component naming convention with the `View` suffix
- **Modal Presentations**: Sheet or popover views that present significant content but aren't full navigation destinations should be suffixed with `SheetView` or `PopoverView` respectively

### 1.2 Other View-Related Elements

- **ViewModels**: Classes that provide data to views should be suffixed with `ViewModel`.
  ```swift
  class ProfileViewModel: ObservableObject {
      // ViewModel content
  }
  ```

- **ViewBuilders**: Methods using `@ViewBuilder` should use the prefix `build` or `make`.
  ```swift
  @ViewBuilder
  private func buildProfileHeader() -> some View {
      // Header view content
  }
  ```

### 1.3 Modifiers and Extensions

- **View Modifiers**: Custom view modifiers should be suffixed with `Modifier`.
  ```swift
  struct RoundedBackgroundModifier: ViewModifier {
      func body(content: Content) -> some View {
          content
              .background(Color.secondary.opacity(0.2))
              .cornerRadius(8)
      }
  }
  ```

- **Extension Functions**: View extension functions should be descriptive of their purpose.
  ```swift
  extension View {
      func roundedBackground() -> some View {
          self.modifier(RoundedBackgroundModifier())
      }
  }
  ```

### 1.4 Implementation and Enforcement

To ensure consistency across the codebase:

- All team members must adhere to these naming conventions
- Code reviews should verify proper naming
- Consider implementing SwiftLint rules to automatically enforce these conventions
- Project templates should include properly named example files

While these conventions may initially seem verbose compared to Apple's native naming, the clarity and organization benefits outweigh the additional characters, particularly in large-scale applications with multiple developers.
