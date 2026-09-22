import SwiftUI

/// M0-004 使用的最小本地通知验证页面。
struct NotificationProbeView: View {
    @Bindable var model: NotificationProbeViewModel

    var body: some View {
        Form {
            Section(.notificationProbeStatusSection) {
                LabeledContent {
                    Text(model.authorizationState.title)
                } label: {
                    Text(.notificationProbeAuthorizationLabel)
                }

                LabeledContent {
                    if let scheduledDate = model.scheduledDate {
                        Text(scheduledDate, format: .dateTime.hour().minute().second())
                    } else {
                        Text(.notificationProbeScheduledTimeEmpty)
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    Text(.notificationProbeScheduledTimeLabel)
                }

                if model.isWorking {
                    ProgressView(.notificationProbeWorking)
                }

                Text(model.statusMessage)
                    .foregroundStyle(.secondary)
            }

            Section(.notificationProbeScenarioSection) {
                Picker(.notificationProbeScenarioLabel, selection: $model.selectedScenario) {
                    ForEach(NotificationProbeScenario.allCases) { scenario in
                        Text(scenario.title)
                            .tag(scenario)
                    }
                }

                Text(model.selectedScenario.instruction)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button(
                    .notificationProbeScheduleButton,
                    systemImage: "bell.badge",
                    action: scheduleProbe
                )
                .buttonStyle(.borderedProminent)
                .disabled(model.isWorking)

                Button(
                    .notificationProbeCancelButton,
                    systemImage: "bell.slash",
                    role: .destructive,
                    action: model.cancelProbe
                )
                .disabled(model.scheduledDate == nil || model.isWorking)
            } footer: {
                Text(.notificationProbeFooter)
            }
        }
        .navigationTitle(.notificationProbeTitle)
        .task {
            await model.refresh()
        }
    }

    private func scheduleProbe() {
        Task {
            await model.scheduleProbe()
        }
    }
}

#Preview("通知探针") {
    NavigationStack {
        NotificationProbeView(
            model: NotificationProbeViewModel(
                notificationService: LocalNotificationService()
            )
        )
    }
}
