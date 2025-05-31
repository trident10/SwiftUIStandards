# SwiftUI Performance Guidelines

## Core Principles

1. **View bodies are hot paths** - Execute 60-120 times per second
2. **Minimize body computations** - Move calculations outside body
3. **Stable view identity** - Prevents full re-renders
4. **Narrow dependencies** - Reduce unnecessary updates
5. **Measure before optimizing** - Use Instruments to validate

## Property Wrapper Rules

### ✅ Use Correctly
```swift
@StateObject private var viewModel = ViewModel()  // View-owned objects
@ObservedObject var injectedModel: Model         // Parent-owned objects  
@State private var isLoading = false             // Simple value types
let immutableData: String                        // No wrapper for constants
```

### ❌ Never Do
```swift
@ObservedObject var viewModel = ViewModel()       // Creates new instance each update
@State var complexObject = ComplexClass()         // Use @StateObject for reference types
```

## View Body Optimization

### ✅ Do This
```swift
struct DataView: View {
    let items: [Item]
    
    // Pre-compute expensive operations
    private var sortedItems: [Item] {
        items.sorted { $0.name < $1.name }
    }
    
    private var total: Int {
        items.reduce(0) { $0 + $1.value }
    }
    
    var body: some View {
        Text("Total: \(total)")
        ForEach(sortedItems) { item in
            ItemRow(item: item)
        }
    }
}
```

### ❌ Avoid This
```swift
var body: some View {
    Text("Total: \(items.reduce(0) { $0 + $1.value })")  // Runs every update
    ForEach(items.sorted { $0.name < $1.name }) { ... }  // Sorts every frame
}
```

## List Performance

### Required for Lists
- Use `LazyVStack` in `ScrollView` for dynamic content
- Add `.id()` modifier for stable identity
- Implement `Identifiable` or provide explicit `id` parameter
- Set frame heights for consistent performance

```swift
// Optimal list implementation
ScrollView {
    LazyVStack(spacing: 0) {
        ForEach(items) { item in
            ItemRow(item: item)
                .frame(height: 80)
                .id(item.id)
        }
    }
}
```

## Image Optimization

### Requirements
- Implement caching mechanism
- Resize images before display
- Use thumbnail APIs when available
- Cancel loads when views disappear

```swift
// Minimum viable cached image
if let cached = cache[url] {
    Image(uiImage: cached)
} else {
    ProgressView()
        .task {
            if let image = await loadAndResize(url) {
                cache[url] = image
            }
        }
}
```

## Animation Guidelines

### Rules
- Animate leaf properties, not view hierarchies
- Use `AnimatableModifier` for complex animations
- Avoid animating during scrolling
- Limit simultaneous animations

```swift
// ✅ Efficient
Text("Hello")
    .scaleEffect(scale)
    .animation(.easeInOut, value: scale)

// ❌ Inefficient
ComplexView()
    .scaleEffect(scale)
    .animation(.easeInOut, value: scale)
```

## Conditional Rendering

### Performance Comparison

#### 1. `if` Statements - Most Efficient
```swift
// ✅ Best for completely different views
if showDetails {
    DetailView()  // Only created when true
        .transition(.slide)  // Transitions work well
}

// View is completely removed from hierarchy when false
// onAppear/onDisappear called appropriately
// New instance created each time (state resets)
```

#### 2. Ternary Operator - Good for Same View Type
```swift
// ✅ Best for variations of same view
Text(isOn ? "ON" : "OFF")
    .foregroundColor(isOn ? .green : .red)

// More efficient than if/else for property changes
// Maintains view identity (smoother animations)
// ~6x faster than if/else for simple property changes
```

#### 3. `.opacity()` - Keep in Hierarchy
```swift
// ⚠️ Use only when needed
DetailView()
    .opacity(showDetails ? 1 : 0)
    .animation(.easeInOut, value: showDetails)

// View REMAINS in hierarchy (body still evaluated)
// State preserved, smooth fade animations
// Good for: preserving state, fade effects
// Bad for: expensive views that aren't visible
```

#### 4. `.hidden()` - Rarely Used
```swift
// ⚠️ Generally avoid
DetailView()
    .hidden(!showDetails)

// Still in hierarchy, no user interaction
// Layout impact unpredictable
// Prefer if statements instead
```

#### 5. `EmptyView` - Explicit Nothing
```swift
// ✅ Clear intent
if condition {
    ContentView()
} else {
    EmptyView()  // Explicitly show nothing
}
```

### Decision Matrix

| Scenario | Use | Performance Impact |
|----------|-----|-------------------|
| Different view types | `if/else` | Best - removes from hierarchy |
| Same view, different properties | Ternary `?:` | Best - maintains identity |
| Need state preservation | `.opacity()` | OK - view stays in hierarchy |
| Smooth fade animations | `.opacity()` | OK - built for animations |
| Expensive hidden views | `if/else` | Best - avoids computation |
| Simple property toggle | Ternary `?:` | Best - minimal overhead |

### Anti-Pattern: AnyView
```swift
// ❌ Avoid AnyView for conditionals
func makeView() -> AnyView {
    if condition {
        return AnyView(ViewA())
    } else {
        return AnyView(ViewB())
    }
}

// ✅ Use @ViewBuilder instead
@ViewBuilder
func makeView() -> some View {
    if condition {
        ViewA()
    } else {
        ViewB()
    }
}
```

AnyView breaks SwiftUI's diffing optimization (~30% slower)

## Declarative Code Style

### Custom ViewModifiers for Cleaner Code
```swift
// ❌ Repetitive conditionals
if showHighlight {
    Text("Message")
        .padding()
        .background(Color.yellow)
} else {
    Text("Message")
        .padding()
}

// ✅ Declarative modifier
extension View {
    func highlight(if condition: Bool) -> some View {
        modifier(HighlightModifier(active: condition))
    }
}

Text("Message")
    .highlight(if: showHighlight)  // Clean and reusable
```

### @ViewBuilder Computed Properties
```swift
// ❌ Complex nested conditions in body
var body: some View {
    VStack {
        if let user = user {
            Text("Welcome, \(user.name)")
            if user.isLoggedIn {
                if user.hasPremium {
                    Text("Premium").foregroundColor(.purple)
                } else {
                    Text("Standard")
                    Button("Upgrade") { }
                }
            }
        }
    }
}

// ✅ Extracted sections
var body: some View {
    VStack {
        greetingSection
        accountStatusSection
    }
}

@ViewBuilder
private var greetingSection: some View {
    if let user = user {
        Text("Welcome, \(user.name)")
    }
}

@ViewBuilder
private var accountStatusSection: some View {
    if let user = user, user.isLoggedIn {
        if user.hasPremium {
            Text("Premium").foregroundColor(.purple)
        } else {
            Text("Standard")
            Button("Upgrade") { }
        }
    }
}
```

### State-Driven UI with Enums
```swift
// ❌ Multiple state flags
@State private var isLoading = true
@State private var data: String? = nil
@State private var error: Error? = nil

// ✅ Single state enum
enum LoadState<T> {
    case loading
    case success(T)
    case failure(Error)
}

@State private var state: LoadState<String> = .loading

var body: some View {
    switch state {
    case .loading:
        ProgressView()
    case .success(let data):
        Text(data)
    case .failure(let error):
        ErrorView(error: error)
    }
}
```

### Conditional View Helper
```swift
// For cleaner optional content
struct ConditionalView<Content: View>: View {
    let condition: Bool
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        if condition {
            content()
        }
    }
}

// Usage
ConditionalView(if: isAdmin) {
    AdminPanel()
}
```

### When to Extract
- **Extract when**: Logic is complex, reusable, or obscures main structure
- **Keep inline when**: Simple one-line conditions, clear intent
- **Goal**: Main body should read like a table of contents

### Requirements
- Use `Task.detached` for heavy operations
- Check `Task.isCancelled` in loops
- Update UI on MainActor

```swift
.task {
    let processed = await Task.detached(priority: .userInitiated) {
        // Heavy processing off main thread
        return expensiveOperation()
    }.value
    
    // Update UI
    self.data = processed
}
```

## Quick Wins Checklist

- [ ] Replace `@ObservedObject` with `@StateObject` for owned objects
- [ ] Add `.id()` to ForEach items
- [ ] Change `VStack` to `LazyVStack` in ScrollViews
- [ ] Move calculations out of view body
- [ ] Implement image caching
- [ ] Use ternary operators instead of if/else for same view types
- [ ] Remove unnecessary `@Published` properties
- [ ] Batch state updates
- [ ] Profile with Instruments

## Code Review Checklist

### Must Check
- [ ] No object creation in view body
- [ ] Appropriate property wrappers
- [ ] Computed properties for derived data
- [ ] Lazy loading for lists
- [ ] Stable ForEach identity
- [ ] Image caching implemented
- [ ] No GeometryReader in ForEach
- [ ] Background work off main thread

### Performance Testing
```swift
// Add to debug builds
struct PerformanceCheck: ViewModifier {
    let label: String
    
    func body(content: Content) -> some View {
        let start = CFAbsoluteTimeGetCurrent()
        let result = content
        let duration = CFAbsoluteTimeGetCurrent() - start
        
        if duration > 0.008 {
            print("⚠️ Slow \(label): \(duration * 1000)ms")
        }
        
        return result
    }
}
```

## Advanced Performance Techniques

### Equatable Views - Skip Unnecessary Updates
```swift
// ❌ Always updates when parent changes
struct ExpensiveView: View {
    let data: ComplexData
    
    var body: some View {
        // Complex rendering logic
    }
}

// ✅ Only updates when data actually changes
struct ExpensiveView: View, Equatable {
    let data: ComplexData
    
    var body: some View {
        // Complex rendering logic
    }
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.data.id == rhs.data.id && 
        lhs.data.lastModified == rhs.data.lastModified
    }
}

// For non-Equatable views, use EquatableView wrapper
EquatableView(content: ExpensiveView(data: data))
```

**Impact:** Can prevent 50-90% of unnecessary view updates in complex hierarchies

### Drawing and Compositing Groups
```swift
// ❌ Each shape rendered separately
ForEach(0..<100) { i in
    Circle()
        .fill(Color.random)
        .frame(width: 20, height: 20)
        .offset(x: CGFloat(i * 10))
}

// ✅ Rendered as single layer
ForEach(0..<100) { i in
    Circle()
        .fill(Color.random)
        .frame(width: 20, height: 20)
        .offset(x: CGFloat(i * 10))
}
.drawingGroup() // Flattens to single Metal layer

// For applying effects efficiently
ComplexView()
    .compositingGroup() // Renders once, then applies effect
    .blur(radius: 10)
```

### Task Identity for Async Work
```swift
// ❌ Task continues even when ID changes
.task {
    await loadData(for: itemId)
}

// ✅ Cancels and restarts when ID changes
.task(id: itemId) {
    await loadData(for: itemId)
}
```

### Fixed Size for Known Dimensions
```swift
// ❌ Participates in full layout negotiation
Image(systemName: "star")
    .frame(width: 20, height: 20)

// ✅ Skips flexible sizing phase
Image(systemName: "star")
    .frame(width: 20, height: 20)
    .fixedSize()
```

### Custom ButtonStyle Over Modifiers
```swift
// ❌ Multiple modifiers, less efficient
Button("Tap") { }
    .padding()
    .background(Color.blue)
    .foregroundColor(.white)
    .cornerRadius(8)

// ✅ Single style application
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(8)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
    }
}

Button("Tap") { }
    .buttonStyle(PrimaryButtonStyle())
```

### Preference Keys for Child-to-Parent Communication
```swift
// ❌ Complex @Binding chains
struct Parent: View {
    @State private var childSize: CGSize = .zero
    var body: some View {
        Child(size: $childSize)
    }
}

// ✅ Preference key (more efficient for multiple children)
struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

Child()
    .background(GeometryReader { geo in
        Color.clear.preference(key: SizePreferenceKey.self, value: geo.size)
    })
    .onPreferenceChange(SizePreferenceKey.self) { size = $0 }
```

### Avoid These Hidden Performance Costs
```swift
// ❌ String interpolation in body (creates new string each time)
Text("Count: \(viewModel.count) items")

// ✅ Use separate Text views
HStack(spacing: 4) {
    Text("Count:")
    Text(viewModel.count, format: .number)
    Text("items")
}

// ❌ Date formatting in body
Text(date, formatter: DateFormatter()) // Creates formatter each time!

// ✅ Static formatter
private static let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    return formatter
}()

Text(date, formatter: Self.dateFormatter)
```

### Custom Layout for Complex Arrangements
```swift
// ❌ Nested GeometryReaders for custom layout
GeometryReader { outer in
    VStack {
        GeometryReader { inner in
            // Complex layout calculations
        }
    }
}

// ✅ Custom Layout (iOS 16+)
struct FlowLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // Efficient calculation
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        // Direct placement
    }
}
```

### Performance Rules for These Techniques

1. **Use Equatable when**:
   - View has expensive body
   - Parent updates frequently but data rarely changes
   - View is deep in hierarchy

2. **Use drawingGroup() when**:
   - Rendering many shapes/paths
   - Complex graphics with multiple layers
   - Applying transforms to groups

3. **Avoid in view body**:
   - Creating formatters
   - String interpolation for complex strings
   - Date/number formatting
   - Any object allocation

## Platform-Specific Optimizations

### iOS 17+
- Use `@Observable` macro instead of `ObservableObject`
- Leverage improved List performance

### Older Devices (iPhone 8 and below)
- Reduce shadow/blur effects
- Limit concurrent animations
- Simplify view hierarchies
- Lower image resolutions

## Final Rule

**If it's in the view body, it runs frequently. If it's expensive, move it out.**
