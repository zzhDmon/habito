import SwiftUI

/// 日历页已加载状态的日期说明、任务列表和覆盖操作。
struct ParentCalendarDayContent: View {
    let snapshot: ParentCalendarDaySnapshot
    let onPreview: (ParentCalendarDayAction) -> Void

    var body: some View {
        Section("parentCalendar.dayTypeSection") {
            LabeledContent("parentCalendar.naturalType", value: dayTypeName(snapshot.naturalDayType))
            LabeledContent(
                "parentCalendar.currentOverride",
                value: snapshot.overrideDayType.map(dayTypeName) ?? String(localized: "parentCalendar.noOverride")
            )
            if snapshot.isHistorical {
                Label("parentCalendar.historyReadOnly", systemImage: "lock.fill")
                    .foregroundStyle(.secondary)
            }
        }

        Section("parentCalendar.tasksSection") {
            if snapshot.occurrences.isEmpty {
                ContentUnavailableView(
                    "parentCalendar.emptyTitle",
                    systemImage: "calendar.badge.checkmark",
                    description: Text("parentCalendar.emptyDescription")
                )
            } else {
                ForEach(snapshot.occurrences) { item in
                    HStack(spacing: HabitoDesign.Spacing.small) {
                        VStack(alignment: .leading, spacing: HabitoDesign.Spacing.xSmall) {
                            Text(item.title)
                                .font(.headline)
                            Text(item.scheduledAt, style: .time)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(statusName(item.status))
                            .font(.caption)
                        if item.isDetachedOverride {
                            Image(systemName: "pin.fill")
                                .accessibilityLabel("parentCalendar.detached")
                        }
                    }
                }
            }
        }

        Section("parentCalendar.actionsSection") {
            Button("parentCalendar.markSchoolDay", systemImage: "backpack.fill", action: markSchoolDay)
                .accessibilityIdentifier(HabitoAccessibilityID.parentCalendarSchoolDay)
            Button(
                "parentCalendar.markHoliday",
                systemImage: "sun.max.fill",
                role: .destructive,
                action: markHoliday
            )
            .accessibilityIdentifier(HabitoAccessibilityID.parentCalendarHoliday)
            if snapshot.overrideDayType != nil {
                Button(
                    "parentCalendar.removeOverride",
                    systemImage: "arrow.uturn.backward",
                    action: removeOverride
                )
                .accessibilityIdentifier(HabitoAccessibilityID.parentCalendarRemoveOverride)
            }
        }
        .disabled(snapshot.isHistorical)
    }

    private func markSchoolDay() {
        onPreview(.setSchoolDay)
    }

    private func markHoliday() {
        onPreview(.setHoliday)
    }

    private func removeOverride() {
        onPreview(.removeOverride)
    }

    private func dayTypeName(_ type: DayType) -> String {
        switch type {
        case .schoolDay: String(localized: "parentCalendar.schoolDay")
        case .holiday: String(localized: "parentCalendar.holiday")
        }
    }

    private func statusName(_ status: TaskOccurrenceStatus) -> LocalizedStringKey {
        switch status {
        case .pending: "parentToday.statusPending"
        case .inProgress: "parentToday.statusInProgress"
        case .completed: "parentToday.statusCompleted"
        case .skipped: "parentToday.statusSkipped"
        case .cancelled: "parentToday.statusDeleted"
        }
    }
}
