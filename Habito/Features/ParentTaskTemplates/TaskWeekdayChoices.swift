import SwiftUI

/// 快捷星期与逐日按钮操作同一集合，家长仍可为实际课程调整。
struct TaskWeekdayChoices: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var weekdays: Set<Weekday>

    var body: some View {
        LazyVGrid(
            columns: dynamicTypeSize.isAccessibilitySize
                ? [GridItem(.flexible())] : [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        ) {
            ForEach(TaskWeekdayPreset.allCases, id: \.self) { preset in
                Button {
                    select(preset)
                } label: {
                    Label {
                        Text(LocalizedStringKey("taskPreset.days." + preset.rawValue), tableName: "UIR1")
                    } icon: {
                        Image(systemName: weekdays == preset.days ? "checkmark.circle.fill" : "circle")
                    }
                    .frame(minHeight: HabitoDesign.Layout.minimumTapSize)
                }
                .labelStyle(.titleAndIcon)
                .buttonStyle(.bordered)
                .accessibilityAddTraits(weekdays == preset.days ? .isSelected : [])
                .accessibilityIdentifier("parent.templates.days." + preset.rawValue)
            }
        }
        Text("taskPreset.days.hint", tableName: "UIR1")
            .font(.footnote)
    }

    private func select(_ preset: TaskWeekdayPreset) { weekdays = preset.days }
}

#Preview("重复星期") {
    @Previewable @State var days = Weekday.schoolDays
    Form { TaskWeekdayChoices(weekdays: $days) }
}
