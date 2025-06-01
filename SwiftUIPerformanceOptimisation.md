# SwiftUI: Stored vs Computed Properties

## Rule
Use stored properties for expensive operations (>1ms). Computed properties run on **every** `body` evaluation.

## **✅ Do This**

```swift
struct DataView: View {
    let items: [Item]
    
    // Calculate once during init
    private let sortedItems: [Item]
    private let statistics: Statistics
    
    init(items: [Item]) {
        self.items = items
        self.sortedItems = items.sorted { $0.date < $1.date }
        self.statistics = Self.calculateStats(from: items)
    }
    
    var body: some View {
        VStack {
            Text("Total: \(statistics.total)")
            ForEach(sortedItems) { item in
                ItemRow(item: item)
            }
        }
    }
}
```

## **❌ Avoid This**

```swift
struct DataView: View {
    let items: [Item]
    
    // Runs on EVERY body evaluation!
    private var sortedItems: [Item] {
        items.sorted { $0.date < $1.date }  // 🔥 Performance killer
    }
    
    private var statistics: Statistics {
        Self.calculateStats(from: items)     // 🔥 Recalculates constantly
    }
    
    var body: some View {
        VStack {
            Text("Total: \(statistics.total)")
            ForEach(sortedItems) { item in
                ItemRow(item: item)
            }
        }
    }
}
```

## Quick Reference

| Computation Time | Approach |
|-----------------|----------|
| < 1ms | Computed property OK |
| 1-16ms | Use stored property |
| > 16ms | Use stored property + async Task |

**Remember**: Body can evaluate 60+ times/second during animations. A 10ms computed property = 600ms CPU time per second!
