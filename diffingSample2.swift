import SwiftUI
import Combine

// MARK: - Main Demo App
struct DiffingDemoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        TabView {
            ClosureProblemDemo()
                .tabItem {
                    Label("Closures", systemImage: "1.circle")
                }
            
            EquatableDemo()
                .tabItem {
                    Label("Equatable", systemImage: "2.circle")
                }
            
            ReferenceTypeDemo()
                .tabItem {
                    Label("Reference", systemImage: "3.circle")
                }
            
            ComputedPropertyDemo()
                .tabItem {
                    Label("Computed", systemImage: "4.circle")
                }
        }
    }
}

// MARK: - Visual Render Tracker
class RenderCounter: ObservableObject {
    @Published var count = 0
    @Published var color: Color = .blue
    private var lastUpdate = Date()
    
    func increment() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastUpdate)
        
        // Only count if enough time has passed (avoid double counting)
        if elapsed > 0.01 {
            count += 1
            color = Color.random
            lastUpdate = now
            print("🎨 Render #\(count)")
        }
    }
}

// MARK: - Demo 1: Closure Problem
struct ClosureProblemDemo: View {
    @State private var counter = 0
    @State private var timer: Timer?
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Closure Diffing Problem")
                .font(.largeTitle)
                .bold()
            
            Text("Counter: \(counter)")
                .font(.title)
            
            HStack(spacing: 20) {
                // This will re-render constantly
                VStack {
                    Text("❌ With Closure")
                        .foregroundColor(.red)
                    ViewWithClosure(
                        value: 42,  // Same value
                        action: { print("Action") }  // New closure each time!
                    )
                }
                
                // This will only render once
                VStack {
                    Text("✅ Without Closure")
                        .foregroundColor(.green)
                    ViewWithoutClosure(
                        value: 42  // Same value
                    )
                }
            }
            
            Button(timer == nil ? "Start Timer" : "Stop Timer") {
                if timer == nil {
                    timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                        counter += 1
                    }
                } else {
                    timer?.invalidate()
                    timer = nil
                }
            }
            .buttonStyle(.borderedProminent)
            
            Text("The red view re-renders on every counter update.\nThe green view doesn't.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .padding()
                .background(Color.yellow.opacity(0.2))
                .cornerRadius(8)
        }
        .padding()
        .onDisappear {
            timer?.invalidate()
        }
    }
}

struct ViewWithClosure: View {
    let value: Int
    let action: () -> Void
    @StateObject private var renderCounter = RenderCounter()
    
    var body: some View {
        // Track renders
        let _ = renderCounter.increment()
        
        VStack {
            Text("Value: \(value)")
            Text("Renders: \(renderCounter.count)")
                .font(.caption)
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(renderCounter.count > 5 ? Color.red : Color.orange)
                .cornerRadius(4)
        }
        .padding()
        .frame(width: 150, height: 100)
        .background(renderCounter.color.opacity(0.3))
        .cornerRadius(8)
    }
}

struct ViewWithoutClosure: View, Equatable {
    let value: Int
    @StateObject private var renderCounter = RenderCounter()
    
    var body: some View {
        // Track renders
        let _ = renderCounter.increment()
        
        VStack {
            Text("Value: \(value)")
            Text("Renders: \(renderCounter.count)")
                .font(.caption)
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(renderCounter.count > 5 ? Color.red : Color.green)
                .cornerRadius(4)
        }
        .padding()
        .frame(width: 150, height: 100)
        .background(renderCounter.color.opacity(0.3))
        .cornerRadius(8)
    }
}

// MARK: - Demo 2: Equatable Solution
struct EquatableDemo: View {
    @State private var counter = 0
    @State private var actualData = "Hello"
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Equatable Solution")
                .font(.largeTitle)
                .bold()
            
            Text("Updates: \(counter)")
                .font(.title)
            
            Text("Data: \(actualData)")
                .font(.title2)
            
            HStack(spacing: 20) {
                VStack {
                    Text("❌ Not Equatable")
                        .foregroundColor(.red)
                    NonEquatableView(
                        data: actualData,
                        action: { print("Action") }
                    )
                }
                
                VStack {
                    Text("✅ Equatable")
                        .foregroundColor(.green)
                    EquatableView(
                        data: actualData,
                        action: { print("Action") }
                    )
                }
            }
            
            HStack {
                Button("Update Counter") {
                    counter += 1
                }
                .buttonStyle(.bordered)
                
                Button("Change Data") {
                    actualData = ["Hello", "World", "SwiftUI"].randomElement()!
                }
                .buttonStyle(.borderedProminent)
            }
            
            Text("Equatable view ignores the closure in comparison")
                .font(.caption)
                .padding()
                .background(Color.green.opacity(0.2))
                .cornerRadius(8)
        }
        .padding()
    }
}

struct NonEquatableView: View {
    let data: String
    let action: () -> Void
    @StateObject private var renderCounter = RenderCounter()
    
    var body: some View {
        let _ = renderCounter.increment()
        
        VStack {
            Text(data)
            Text("Renders: \(renderCounter.count)")
                .font(.caption)
        }
        .padding()
        .frame(width: 150, height: 100)
        .background(renderCounter.color.opacity(0.3))
        .cornerRadius(8)
    }
}

struct EquatableView: View, Equatable {
    let data: String
    let action: () -> Void
    @StateObject private var renderCounter = RenderCounter()
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.data == rhs.data
        // Ignore action closure
    }
    
    var body: some View {
        let _ = renderCounter.increment()
        
        VStack {
            Text(data)
            Text("Renders: \(renderCounter.count)")
                .font(.caption)
        }
        .padding()
        .frame(width: 150, height: 100)
        .background(renderCounter.color.opacity(0.3))
        .cornerRadius(8)
    }
}

// MARK: - Demo 3: Reference Type Issues
class Settings: ObservableObject {
    @Published var theme: String = "Light"
    @Published var fontSize: Int = 14
}

struct ReferenceTypeDemo: View {
    @State private var counter = 0
    @StateObject private var settings = Settings()
    @State private var recreateSettings = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Reference Type Diffing")
                .font(.largeTitle)
                .bold()
            
            Text("Counter: \(counter)")
            
            Toggle("Recreate Settings Object", isOn: $recreateSettings)
                .padding(.horizontal)
            
            HStack(spacing: 20) {
                VStack {
                    Text("Current Settings")
                    Text("Theme: \(settings.theme)")
                    Text("Font: \(settings.fontSize)")
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
                
                VStack {
                    Text("Reference View")
                    if recreateSettings {
                        // Creates new instance each time
                        ReferenceView(settings: Settings())
                    } else {
                        // Same instance
                        ReferenceView(settings: settings)
                    }
                }
            }
            
            HStack {
                Button("Update Counter") {
                    counter += 1
                }
                
                Button("Modify Settings") {
                    settings.theme = settings.theme == "Light" ? "Dark" : "Light"
                    settings.fontSize = Int.random(in: 12...20)
                }
            }
            .buttonStyle(.bordered)
            
            Text(recreateSettings ? 
                 "Creating new instance - always re-renders" : 
                 "Using same instance - won't detect property changes")
                .font(.caption)
                .multilineTextAlignment(.center)
                .padding()
                .background(Color.orange.opacity(0.2))
                .cornerRadius(8)
        }
        .padding()
    }
}

struct ReferenceView: View {
    let settings: Settings
    @StateObject private var renderCounter = RenderCounter()
    
    var body: some View {
        let _ = renderCounter.increment()
        
        VStack {
            Text("Theme: \(settings.theme)")
            Text("Font: \(settings.fontSize)")
            Text("Renders: \(renderCounter.count)")
                .font(.caption)
        }
        .padding()
        .frame(width: 150, height: 100)
        .background(renderCounter.color.opacity(0.3))
        .cornerRadius(8)
    }
}

// MARK: - Demo 4: Computed Properties
struct ComputedPropertyDemo: View {
    @State private var counter = 0
    @State private var showDetail = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Computed Properties Issue")
                .font(.largeTitle)
                .bold()
            
            Text("Counter: \(counter)")
            
            HStack(spacing: 20) {
                VStack {
                    Text("❌ Computed Properties")
                        .foregroundColor(.red)
                    BadComputedView(counter: counter, showDetail: showDetail)
                }
                
                VStack {
                    Text("✅ Separate Views")
                        .foregroundColor(.green)
                    GoodSeparateView(counter: counter, showDetail: showDetail)
                }
            }
            
            Toggle("Show Detail", isOn: $showDetail)
                .padding(.horizontal)
            
            Button("Increment Counter") {
                counter += 1
            }
            .buttonStyle(.borderedProminent)
            
            Text("Computed properties are inlined and can't be diffed separately")
                .font(.caption)
                .padding()
                .background(Color.yellow.opacity(0.2))
                .cornerRadius(8)
        }
        .padding()
    }
}

struct BadComputedView: View {
    let counter: Int
    let showDetail: Bool
    @StateObject private var renderCounter = RenderCounter()
    
    var body: some View {
        let _ = renderCounter.increment()
        
        VStack {
            headerSection
            if showDetail {
                detailSection
            }
            footerSection
            
            Text("Total Renders: \(renderCounter.count)")
                .font(.caption)
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.red)
                .cornerRadius(4)
        }
        .padding()
        .background(renderCounter.color.opacity(0.3))
        .cornerRadius(8)
    }
    
    private var headerSection: some View {
        Text("Header: \(counter)")
            .padding(4)
            .background(Color.blue.opacity(0.2))
    }
    
    private var detailSection: some View {
        Text("Detail View")
            .padding(4)
            .background(Color.green.opacity(0.2))
    }
    
    private var footerSection: some View {
        Text("Footer")
            .padding(4)
            .background(Color.orange.opacity(0.2))
    }
}

struct GoodSeparateView: View {
    let counter: Int
    let showDetail: Bool
    @StateObject private var renderCounter = RenderCounter()
    
    var body: some View {
        let _ = renderCounter.increment()
        
        VStack {
            HeaderView(counter: counter)
            if showDetail {
                DetailView()
            }
            FooterView()
            
            Text("Container Renders: \(renderCounter.count)")
                .font(.caption)
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green)
                .cornerRadius(4)
        }
        .padding()
        .background(renderCounter.color.opacity(0.3))
        .cornerRadius(8)
    }
}

struct HeaderView: View, Equatable {
    let counter: Int
    @StateObject private var renderCounter = RenderCounter()
    
    var body: some View {
        let _ = renderCounter.increment()
        
        Text("Header: \(counter) (R: \(renderCounter.count))")
            .padding(4)
            .background(Color.blue.opacity(0.2))
    }
}

struct DetailView: View, Equatable {
    @StateObject private var renderCounter = RenderCounter()
    
    var body: some View {
        let _ = renderCounter.increment()
        
        Text("Detail (R: \(renderCounter.count))")
            .padding(4)
            .background(Color.green.opacity(0.2))
    }
}

struct FooterView: View, Equatable {
    @StateObject private var renderCounter = RenderCounter()
    
    var body: some View {
        let _ = renderCounter.increment()
        
        Text("Footer (R: \(renderCounter.count))")
            .padding(4)
            .background(Color.orange.opacity(0.2))
    }
}

extension Color {
    static var random: Color {
        Color(
            red: .random(in: 0...1),
            green: .random(in: 0...1),
            blue: .random(in: 0...1)
        )
    }
}
