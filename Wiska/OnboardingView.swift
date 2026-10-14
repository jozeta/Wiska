import AppKit
import HUD
import Preferences
import SwiftUI

struct OnboardingView: View {
    let model: AppModel
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        @Bindable var settings = model.settings
        let state = model.onboarding
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Text("Wiska").foregroundStyle(AuroraTheme.gradient(model.settings.highlight))
                Text("setup")
            }
            .font(.system(size: 26, weight: .bold))
            Text("A few quick steps. Your voice never leaves this Mac.")
                .foregroundStyle(.secondary)

            ForEach(OnboardingStep.allCases) { step in
                HStack(spacing: 12) {
                    Image(systemName: state.isDone(step) ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(state.isDone(step) ? AuroraTheme.start(model.settings.highlight) : Color.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title).fontWeight(.semibold)
                        Text(step.reason).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    action(for: step, done: state.isDone(step), settings: settings)
                }
                .padding(10)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            }

            HStack {
                Text(state.canFinish ? "You're ready — hold fn anywhere to dictate."
                                     : "Microphone, Input Monitoring and Accessibility are required.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Finish") {
                    settings.onboardingCompleted = true
                    dismissWindow(id: OnboardingWindow.id)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!state.canFinish)
            }
        }
        .padding(24)
        .frame(width: 540)
    }

    @ViewBuilder
    private func action(for step: OnboardingStep, done: Bool, settings: SettingsStore) -> some View {
        switch step {
        case .microphone, .accessibility:
            if !done {
                Button("Allow…") { permission(for: step).requestOrOpenSettings() }
            }
        case .inputMonitoring:
            // Nothing to click: macOS allows it with Accessibility, from Wiska's next launch,
            // and Wiska offers that restart itself.
            EmptyView()
        case .fnKey:
            HStack {
                Button("Open Keyboard Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
                }
                Toggle("Done", isOn: Binding(get: { settings.fnKeyConfirmed },
                                             set: { settings.fnKeyConfirmed = $0 }))
                    .toggleStyle(.checkbox)
            }
        case .tryIt:
            EmptyView()
        case .screenRecording:
            if !done {
                Button("Allow…") { ScreenRecordingPermission.requestOrOpenSettings() }
            }
        }
    }

    private func permission(for step: OnboardingStep) -> Permission {
        switch step {
        case .accessibility: .accessibility
        default: .microphone
        }
    }
}
