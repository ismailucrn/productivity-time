import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "timer")
                .font(.system(size: 40))
            Text("Productivity Time")
                .font(.title)
            Text("Create an activity to begin.")
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 360, minHeight: 240)
        .padding()
    }
}
