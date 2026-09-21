import SwiftUI

struct TimerPanelView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isTimerMode = false
    @State private var minutes = 25

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Button("Stopwatch") { isTimerMode = false }
                    .accessibilityIdentifier("timer.mode.stopwatch")
                    .buttonStyle(.borderedProminent)
                Button("Timer") { isTimerMode = true }
                    .accessibilityIdentifier("timer.mode.timer")
            }
            if isTimerMode {
                Stepper("Duration: \(minutes) minutes", value: $minutes, in: 1...1_440)
                    .accessibilityIdentifier("timer.duration")
                HStack {
                    ForEach([5, 25, 50], id: \.self) { preset in
                        Button("\(preset)m") { minutes = preset }
                    }
                }
            }
            Text(durationText(model.displayedDuration))
                .font(.system(size: 46, design: .monospaced))
                .accessibilityIdentifier("timer.duration.display")
            HStack {
                Button(primaryTitle) { primaryAction() }
                    .accessibilityIdentifier("timer.primary")
                    .disabled(model.activeSession == nil && model.selectedActivityID == nil)
                Button("Reset") { try? model.reset() }
                    .accessibilityIdentifier("timer.reset")
                    .disabled(model.activeSession == nil)
                Button("Cancel") { try? model.cancel() }
                    .accessibilityIdentifier("timer.cancel")
                    .disabled(model.activeSession == nil)
            }
        }
        .padding(32)
        .onAppear { model.setCounterVisible(true) }
        .onDisappear { model.setCounterVisible(false) }
    }

    private var primaryTitle: String {
        switch model.activeSession?.state {
        case .running: "Pause"
        case .paused: "Resume"
        default: "Start"
        }
    }

    private func primaryAction() {
        do {
            switch model.activeSession?.state {
            case .running: try model.pause()
            case .paused: try model.resume()
            default:
                guard let activityID = model.selectedActivityID else { return }
                if isTimerMode { try model.startTimer(for: activityID, duration: .seconds(minutes * 60)) }
                else { try model.startStopwatch(for: activityID) }
            }
        } catch {}
    }

    private func durationText(_ duration: Duration) -> String {
        let total = max(0, Int(duration.timeInterval.rounded(.down)))
        return String(format: "%02d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
    }
}
