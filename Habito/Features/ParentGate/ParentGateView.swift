import SwiftUI

/// 家长 PIN 的创建、验证、失败反馈与本机重置界面。
struct ParentGateView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: ParentGateViewModel
    @State private var taskTemplatesModel: ParentTaskTemplateListViewModel
    @State private var parentTodayModel: ParentTodayTaskViewModel
    @State private var parentCalendarModel: ParentCalendarDayViewModel
    @State private var parentNotificationModel: ParentNotificationDiagnosticsViewModel
    @State private var path: [ParentRoute] = []
    @State private var pin = ""
    @State private var confirmation = ""
    @State private var isResetConfirmationPresented = false
    private let taskTemplateEditorModelFactory: TaskTemplateEditorViewModelFactory

    init(
        model: ParentGateViewModel,
        taskTemplatesModel: ParentTaskTemplateListViewModel,
        parentTodayModel: ParentTodayTaskViewModel,
        parentCalendarModel: ParentCalendarDayViewModel,
        parentNotificationModel: ParentNotificationDiagnosticsViewModel,
        taskTemplateEditorModelFactory: TaskTemplateEditorViewModelFactory
    ) {
        _model = State(initialValue: model)
        _taskTemplatesModel = State(initialValue: taskTemplatesModel)
        _parentTodayModel = State(initialValue: parentTodayModel)
        _parentCalendarModel = State(initialValue: parentCalendarModel)
        _parentNotificationModel = State(initialValue: parentNotificationModel)
        self.taskTemplateEditorModelFactory = taskTemplateEditorModelFactory
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch model.state {
                case .loading:
                    ProgressView("parentGate.loading")
                case .setup:
                    setupForm
                case .verify:
                    verifyForm
                case .unlocked:
                    ParentTaskTemplateListView(
                        model: taskTemplatesModel,
                        onShowToday: { path.append(.today) },
                        onShowCalendar: { path.append(.calendar) },
                        onShowNotifications: { path.append(.notifications) },
                        onCreate: { path.append(.template(.create)) },
                        onSelect: { path.append(.template(.detail($0))) }
                    )
                case .failed:
                    ContentUnavailableView {
                        Label("parentGate.errorTitle", systemImage: "exclamationmark.triangle.fill")
                    } description: {
                        Text("parentGate.errorDescription")
                    } actions: {
                        Button("parentGate.retry", action: model.prepareForPresentation)
                    }
                }
            }
            .navigationTitle("parentGate.navigationTitle")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("parentGate.close", action: dismiss.callAsFunction)
                }
            }
            .navigationDestination(for: ParentRoute.self) { route in
                switch route {
                case .today:
                    ParentTodayTaskListView(model: parentTodayModel)
                case .calendar:
                    ParentCalendarDayView(model: parentCalendarModel)
                case .notifications:
                    ParentNotificationDiagnosticsView(model: parentNotificationModel)
                case let .template(templateRoute):
                    TaskTemplateEditorView(
                        model: taskTemplateEditorModelFactory.makeModel(for: templateRoute),
                        onSaved: taskTemplatesModel.load
                    )
                }
            }
        }
        .presentationDetents([.large])
        .confirmationDialog(
            "parentGate.resetConfirmationTitle",
            isPresented: $isResetConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("parentGate.resetConfirm", role: .destructive, action: resetPIN)
            Button("parentGate.cancel", role: .cancel) {}
        } message: {
            Text("parentGate.resetConfirmationDescription")
        }
    }

    private var setupForm: some View {
        Form {
            Section {
                SecureField("parentGate.pin", text: $pin)
                    .keyboardType(.numberPad)
                    .textContentType(.newPassword)
                    .onChange(of: pin) { _, value in pin = filteredPIN(value) }
                    .accessibilityIdentifier(HabitoAccessibilityID.parentPINField)
                SecureField("parentGate.confirmPIN", text: $confirmation)
                    .keyboardType(.numberPad)
                    .textContentType(.newPassword)
                    .onChange(of: confirmation) { _, value in confirmation = filteredPIN(value) }
                    .accessibilityIdentifier(HabitoAccessibilityID.parentPINConfirmationField)
            } header: {
                Text("parentGate.setupTitle")
            } footer: {
                Text("parentGate.setupDescription")
            }

            feedbackView

            Button("parentGate.create", action: createPIN)
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity, minHeight: HabitoDesign.Layout.minimumTapSize)
                .accessibilityIdentifier(HabitoAccessibilityID.parentCreateButton)
        }
    }

    private var verifyForm: some View {
        Form {
            Section {
                SecureField("parentGate.pin", text: $pin)
                    .keyboardType(.numberPad)
                    .textContentType(.password)
                    .onChange(of: pin) { _, value in pin = filteredPIN(value) }
                    .accessibilityIdentifier(HabitoAccessibilityID.parentPINField)
            } header: {
                Text("parentGate.verifyTitle")
            } footer: {
                Text("parentGate.verifyDescription")
            }

            feedbackView

            Button("parentGate.unlock", action: verifyPIN)
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity, minHeight: HabitoDesign.Layout.minimumTapSize)
                .accessibilityIdentifier(HabitoAccessibilityID.parentUnlockButton)

            Button("parentGate.reset", role: .destructive) {
                isResetConfirmationPresented = true
            }
            .frame(minHeight: HabitoDesign.Layout.minimumTapSize)
            .accessibilityIdentifier(HabitoAccessibilityID.parentResetButton)
        }
    }

    @ViewBuilder
    private var feedbackView: some View {
        if let feedback = model.feedback {
            Label(feedbackKey(feedback), systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    private func createPIN() {
        model.createPIN(pin, confirmation: confirmation)
        clearInputs()
    }

    private func verifyPIN() {
        model.verifyPIN(pin)
        clearInputs()
    }

    private func resetPIN() {
        model.resetPIN()
        clearInputs()
    }

    private func clearInputs() {
        pin = ""
        confirmation = ""
    }

    private func filteredPIN(_ value: String) -> String {
        // 与领域校验一致，只保留 ASCII 数字，避免全角数字等视觉相似字符造成无法解锁。
        String(
            value.filter {
                $0.isNumber && $0.unicodeScalars.allSatisfy(\.isASCII)
            }.prefix(4)
        )
    }

    private func feedbackKey(_ feedback: ParentGateViewModel.Feedback) -> LocalizedStringKey {
        switch feedback {
        case .invalidFormat: "parentGate.feedbackInvalidFormat"
        case .confirmationMismatch: "parentGate.feedbackMismatch"
        case .incorrectPIN: "parentGate.feedbackIncorrect"
        case .storageFailure: "parentGate.feedbackStorageFailure"
        }
    }
}
