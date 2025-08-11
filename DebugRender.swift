// Alternative, more stable debug renderer implementation
// Replace the DebugRenderer struct in the main project with this version

// MARK: - Debug Renderer System (Stable Version)

/// A debug view that tracks render counts
struct DebugRenderView: View {
    let label: String
    let showStats: Bool
    @State private var renderCount = 0
    @State private var lastRenderTime = Date()
    @State private var renderTimes: [TimeInterval] = []
    
    var body: some View {
        // This print will fire every time the body is evaluated
        let _ = Self._printChanges()
        let _ = trackRender()
        
        ZStack {
            // Background that changes color based on render count
            RoundedRectangle(cornerRadius: 8)
                .fill(colorForRenderCount.opacity(0.3))
                .animation(.easeInOut(duration: 0.3), value: renderCount)
            
            // Stats overlay
            if showStats {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Renders: \(renderCount)")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(renderCount > 5 ? Color.red : Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(4)
                    
                    if let avgTime = averageRenderTime {
                        Text("\(String(format: "%.1f", avgTime))ms")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(4)
                    }
                }
                .padding(4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
    }
    
    private func trackRender() {
        DispatchQueue.main.async {
            let now = Date()
            let elapsed = now.timeIntervalSince(lastRenderTime) * 1000
            
            // Only count if sufficient time has passed (avoid double-counting)
            if elapsed > 5 {
                renderCount += 1
                lastRenderTime = now
                
                print("🎨 [\(label)] Render #\(renderCount) (after \(String(format: "%.1f", elapsed))ms)")
                
                if elapsed < 16 && renderCount > 1 {
                    print("   ⚠️ WARNING: Rendering too frequently for 60fps!")
                }
                
                if renderCount > 1 {
                    renderTimes.append(elapsed)
                    if renderTimes.count > 10 {
                        renderTimes.removeFirst()
                    }
                }
            }
        }
    }
    
    private var colorForRenderCount: Color {
        // Cycle through colors based on render count
        let colors: [Color] = [.blue, .green, .orange, .red, .purple, .pink, .yellow, .cyan]
        return colors[renderCount % colors.length]
    }
    
    private var averageRenderTime: Double? {
        guard !renderTimes.isEmpty else { return nil }
        return renderTimes.reduce(0, +) / Double(renderTimes.count)
    }
}

/// Simpler modifier that just overlays the debug view
struct SimpleDebugRenderer: ViewModifier {
    let label: String
    let showStats: Bool
    
    func body(content: Content) -> some View {
        content
            .background(
                DebugRenderView(label: label, showStats: showStats)
            )
    }
}

/// Even simpler approach using preference keys
struct RenderCountKey: PreferenceKey {
    static var defaultValue: Int = 0
    static func reduce(value: inout Int, nextValue: () -> Int) {
        value = nextValue()
    }
}

struct MinimalDebugRenderer: ViewModifier {
    let label: String
    @State private var renderCount = 0
    @State private var displayColor = Color.blue
    
    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { _ in
                    Color.clear
                        .preference(key: RenderCountKey.self, value: renderCount + 1)
                        .onPreferenceChange(RenderCountKey.self) { value in
                            if value != renderCount {
                                renderCount = value
                                displayColor = Color.random
                                print("🎨 [\(label)] Render #\(renderCount)")
                            }
                        }
                }
            )
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(displayColor.opacity(0.3))
            )
            .overlay(alignment: .topTrailing) {
                Text("\(renderCount)")
                    .font(.caption2)
                    .padding(4)
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(4)
                    .padding(4)
            }
    }
}

// Extension for using the debug renderers
extension View {
    /// Use this version for more stable behavior
    func stableDebugRenderer(_ label: String = "View", showStats: Bool = true) -> some View {
        self.modifier(SimpleDebugRenderer(label: label, showStats: showStats))
    }
    
    /// Use this for minimal overhead
    func minimalDebugRenderer(_ label: String = "View") -> some View {
        self.modifier(MinimalDebugRenderer(label: label))
    }
}

// USAGE EXAMPLE:
// Replace .debugRenderer("Label") with .stableDebugRenderer("Label") 
// throughout the project for more stable behavior
