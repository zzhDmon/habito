import SwiftUI

/// 家长 PIN 的创建、验证、失败反馈与本机重置界面。
struct ParentGateView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: ParentGateViewModel
    @State private var taskTemplatesModel: ParentTaskTemplateListViewModel
    @State private var parentTodayModel: ParentTodayTaskViewModel
    @State private var statisticsModel: GrowthStatisticsViewModel
    @State private var familyProfileModel: FamilyProfileEditorViewModel
    @State private var parentReviewModel: ParentReviewViewModel
    @State private var parentCalendarModel: ParentCalendarDayViewModel
    @State private var parentNotificationModel: ParentNotificationDiagnosticsViewModel
    @State private var path: [ParentRoute] = []
    @State private var pin = ""
    @State private var confirmation = ""
    @State private var isResetConfirmationPresented = false
    /// 页面拥有的主 actor 焦点；安全输入框移除前结束编辑，不把焦点带入已解锁界面。
    @FocusState private var focusedPINField: String?
    private let taskTemplateEditorModelFactory: TaskTemplateEditorViewModelFactory

    init(
        model: ParentGateViewModel,
        taskTemplatesModel: ParentTaskTemplateListViewModel,
        parentTodayModel: ParentTodayTaskViewModel,
        statisticsModel: GrowthStatisticsViewModel,
        familyProfileModel: FamilyProfileEditorViewModel,
        parentReviewModel: ParentReviewViewModel,
        parentCalendarModel: ParentCalendarDayViewModel,
        parentNotificationModel: ParentNotificationDiagnosticsViewModel,
        taskTemplateEditorModelFactory: TaskTemplateEditorViewModelFactory
    ) {
        _model = State(initialValue: model)
        _taskTemplatesModel = State(initialValue: taskTemplatesModel)
        _parentTodayModel = State(initialValue: parentTodayModel)
        _statisticsModel = State(initialValue: statisticsModel)
        _familyProfileModel = State(initialValue: familyProfileModel)
        _parentReviewModel = State(initialValue: parentReviewModel)
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
                        onShowReview: { path.append(.review) },
                        onShowStatistics: { path.append(.statistics) },
                        onShowFamilyProfile: { path.append(.familyProfile) },
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
            // 根页面只有一个标题来源，不能用门控标题再次覆盖已解锁管理页的标题。
            .navigationTitle(rootNavigationTitle)
            // 行内标题避免大字号门控→管理页切换时的折叠布局竞争；字段仍跟随系统字号。
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("parentGate.close", action: dismiss.callAsFunction)
                        .accessibilityIdentifier(HabitoAccessibilityID.parentClose)
                }
            }
            .navigationDestination(for: ParentRoute.self) { route in
                switch route {
                case .familyProfile:
                    // 本次PIN未通过时不创建资料页面，也不会触发名字load。
                    if model.state == .unlocked {
                        FamilyProfileEditorView(model: familyProfileModel, onClose: dismiss.callAsFunction)
                    } else {
                        ContentUnavailableView("parentGate.verifyTitle", systemImage: "lock.fill")
                    }
                case .review:
                    // 审核路由只注册在家长栈；即使保留旧 path，也不能跨越本次 PIN 验证。
                    if model.state == .unlocked {
                        ParentReviewView(model: parentReviewModel)
                    } else {
                        ContentUnavailableView("parentGate.verifyTitle", systemImage: "lock.fill")
                    }
                case .today:
                    if model.state == .unlocked {
                        ParentTodayTaskListView(model: parentTodayModel, onShowStatistics: { path.append(.statistics) })
                    } else {
                        ContentUnavailableView("parentGate.verifyTitle", systemImage: "lock.fill")
                    }
                case .statistics:
                    if model.state == .unlocked {
                        GrowthStatisticsView(model: statisticsModel)
                    } else {
                        ContentUnavailableView("parentGate.verifyTitle", systemImage: "lock.fill")
                    }
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
        .tint(HabitoDesign.Manga.successInk)
        .toolbarBackground(HabitoDesign.Manga.paper, for: .navigationBar)
        .presentationDetents([.large])
        .onDisappear(perform: clearParentPrivateState)
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

    /// 任何关闭方式（包括下拉与通知路由）都撤下历史和名字，不能只清按钮关闭路径。
    private func clearParentPrivateState() {
        statisticsModel.reset()
        familyProfileModel.reset()
        parentTodayModel.overviewModel?.reset()
    }

    private var setupForm: some View {
        Form {
            Section {
                SecureField("parentGate.pin", text: $pin)
                    .focused($focusedPINField, equals: HabitoAccessibilityID.parentPINField)
                    .keyboardType(.numberPad)
                    .textContentType(.newPassword)
                    .onChange(of: pin) { _, value in pin = filteredPIN(value) }
                    .accessibilityIdentifier(HabitoAccessibilityID.parentPINField)
                SecureField("parentGate.confirmPIN", text: $confirmation)
                    .focused($focusedPINField, equals: HabitoAccessibilityID.parentPINConfirmationField)
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
                .buttonStyle(MangaButtonStyle())
                .frame(maxWidth: .infinity, minHeight: HabitoDesign.Layout.minimumTapSize)
                .accessibilityIdentifier(HabitoAccessibilityID.parentCreateButton)
        }
        // 大字号下按钮可能位于键盘之后；原生滚动应结束编辑，避免只能点到露出的边缘。
        .scrollDismissesKeyboard(.immediately)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(HabitoAccessibilityID.parentPINForm)
    }

    private var verifyForm: some View {
        Form {
            Section {
                SecureField("parentGate.pin", text: $pin)
                    .focused($focusedPINField, equals: HabitoAccessibilityID.parentPINField)
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
                .buttonStyle(MangaButtonStyle())
                .frame(maxWidth: .infinity, minHeight: HabitoDesign.Layout.minimumTapSize)
                .accessibilityIdentifier(HabitoAccessibilityID.parentUnlockButton)

            Button("parentGate.reset", role: .destructive) {
                isResetConfirmationPresented = true
            }
            .frame(minHeight: HabitoDesign.Layout.minimumTapSize)
            .accessibilityIdentifier(HabitoAccessibilityID.parentResetButton)
        }
        .scrollDismissesKeyboard(.immediately)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(HabitoAccessibilityID.parentPINForm)
    }

    @ViewBuilder
    private var feedbackView: some View {
        if let feedback = model.feedback {
            Label(feedbackKey(feedback), systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    private func createPIN() {
        // 先复制本次输入并结束编辑，再切换门禁状态；校验仍由原用例负责。
        let enteredPIN = pin
        let repeatedPIN = confirmation
        clearInputs()
        model.createPIN(enteredPIN, confirmation: repeatedPIN)
    }

    private var rootNavigationTitle: LocalizedStringKey {
        model.state == .unlocked ? "parentTemplates.navigationTitle" : "parentGate.navigationTitle"
    }

    private func verifyPIN() {
        let enteredPIN = pin
        clearInputs()
        model.verifyPIN(enteredPIN)
    }

    private func resetPIN() {
        model.resetPIN()
        clearInputs()
    }

    private func clearInputs() {
        focusedPINField = nil
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
