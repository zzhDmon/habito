import XCTest

/// 在真实 iPad 模拟器进程中验证不依赖通知的孩子闭环。
@MainActor
final class HabitoKidFlowUITests: XCTestCase {
    private let seededTaskIdentifier = "kid.today.task.c5412144-2fb8-4e96-9f7a-6a42e0803d11"
    private let seededTemplateIdentifier =
        "parent.templates.item.6743a00b-878f-4bb0-a861-64056ec19fe5"
    private let parentTodayTaskIdentifier =
        "parent.today.task.c5412144-2fb8-4e96-9f7a-6a42e0803d11"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunchMaterializationRefreshesInitiallyEmptyToday() throws {
        verifyLaunchMaterialization(extraArguments: [])
    }

    func testDeniedNotificationsDoNotHideNewlyMaterializedToday() throws {
        verifyLaunchMaterialization(extraArguments: ["--habito-ui-notifications-denied"])
    }

    func testSchedulingFailureDoesNotHideNewlyMaterializedToday() throws {
        verifyLaunchMaterialization(extraArguments: ["--habito-ui-notifications-fail"])
    }

    private func verifyLaunchMaterialization(extraArguments: [String]) {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = makeApplication()
        app.launchArguments =
            ["--habito-ui-testing", "--habito-ui-reset", "--habito-ui-template-only"] + extraArguments
        app.launch()
        // 重建会生成新的实例 UUID，按正式可访问性命名空间查找，不伪造固定样例实例。
        let task = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "kid.today.task.")).firstMatch
        XCTAssertTrue(task.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["阅读 15 分钟"].exists)
        task.tap()
        XCTAssertTrue(app.buttons["kid.session.start"].waitForExistence(timeout: 5))
    }

    func testColdLaunchNotificationOpensSeededTask() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = makeApplication()
        app.launchArguments = [
            "--habito-ui-testing",
            "--habito-ui-reset",
            "--habito-ui-notification-request",
            "habito.occurrence.c5412144-2fb8-4e96-9f7a-6a42e0803d11.primary",
        ]
        app.launch()

        XCTAssertTrue(app.buttons["kid.session.start"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["阅读 15 分钟"].exists)
    }

    func testBackgroundNotificationReplacesCurrentNavigationWithSeededTask() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = makeApplication()
        app.launchArguments = [
            "--habito-ui-testing",
            "--habito-ui-reset",
            "--habito-ui-notification-request",
            "habito.occurrence.c5412144-2fb8-4e96-9f7a-6a42e0803d11.primary",
            "--habito-ui-delayed-notification",
        ]
        app.launch()

        XCTAssertTrue(app.buttons[seededTaskIdentifier].waitForExistence(timeout: 5))
        let notificationResponse = app.buttons["testing.notification-response"]
        XCTAssertTrue(notificationResponse.waitForExistence(timeout: 5))
        notificationResponse.tap()
        XCTAssertTrue(app.buttons["kid.session.start"].waitForExistence(timeout: 5))
    }

    func testColdLaunchOldNotificationForCompletedTaskReturnsHomeWithoutReseeding() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = makeApplication()
        app.launchArguments = ["--habito-ui-testing", "--habito-ui-reset"]
        app.launch()
        let task = app.buttons[seededTaskIdentifier]
        XCTAssertTrue(task.waitForExistence(timeout: 5))
        task.tap()
        let complete = app.buttons["kid.session.complete"]
        XCTAssertTrue(complete.waitForExistence(timeout: 5))
        complete.tap()
        XCTAssertTrue(app.buttons["kid.session.undo"].waitForExistence(timeout: 2))

        // 不传 reset：旧通知路由必须读取刚才已保存的完成事实，而不是测试进程内快照。
        relaunchWithOldSeededNotification(app)
        XCTAssertTrue(app.staticTexts["今天的任务都完成了。"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["kid.session.start"].exists)
        XCTAssertFalse(app.buttons["kid.session.complete"].exists)
        XCTAssertFalse(task.exists)
        XCTAssertTrue(app.buttons["parent.gate.entry"].exists)
    }

    func testColdLaunchOldNotificationForDeletedTaskReturnsHomeWithoutReseeding() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = makeApplication()
        app.launchArguments = ["--habito-ui-testing", "--habito-ui-reset"]
        app.launch()
        XCTAssertTrue(app.buttons[seededTaskIdentifier].waitForExistence(timeout: 5))
        unlockParent(in: app)
        let template = app.buttons[seededTemplateIdentifier]
        XCTAssertTrue(template.waitForExistence(timeout: 5))
        template.tap()
        let archive = app.buttons["parent.templates.lifecycle.archive"]
        scrollFullyIntoEditorViewport(archive, in: app)
        XCTAssertTrue(archive.waitForExistence(timeout: 5))
        archive.tap()
        let confirm = app.buttons["parent.templates.lifecycle.confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.staticTexts["还没有任务"].waitForExistence(timeout: 5))

        // 软删除保留模板历史，但移除其待处理实例；重启播种不能使旧 identifier 再次有效。
        relaunchWithOldSeededNotification(app)
        XCTAssertTrue(app.staticTexts["今天没有任务啊"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["kid.session.start"].exists)
        XCTAssertFalse(app.buttons[seededTaskIdentifier].exists)
        XCTAssertTrue(app.buttons["parent.gate.entry"].exists)
    }

    func testStartPauseRelaunchResumeCompleteAndUndo() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = makeApplication()
        app.launchArguments = ["--habito-ui-testing", "--habito-ui-reset"]
        app.launch()

        let task = app.buttons[seededTaskIdentifier]
        XCTAssertTrue(task.waitForExistence(timeout: 5))
        task.tap()

        let start = app.buttons["kid.session.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()

        let pause = app.buttons["kid.session.pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        pause.tap()
        XCTAssertTrue(app.buttons["kid.session.resume"].waitForExistence(timeout: 5))

        // 第二次启动不传 reset，证明暂停会话来自独立磁盘容器，而不是测试进程内状态。
        app.terminate()
        app.launchArguments = ["--habito-ui-testing"]
        app.launch()
        XCTAssertTrue(task.waitForExistence(timeout: 5))
        task.tap()

        let resume = app.buttons["kid.session.resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        resume.tap()
        XCTAssertTrue(pause.waitForExistence(timeout: 5))

        let complete = app.buttons["kid.session.complete"]
        XCTAssertTrue(complete.waitForExistence(timeout: 5))
        complete.tap()

        let undo = app.buttons["kid.session.undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 2))
        undo.tap()
        XCTAssertTrue(start.waitForExistence(timeout: 5))
    }

    func testPendingTaskCanScheduleTenMinuteSnooze() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = makeApplication()
        app.launchArguments = ["--habito-ui-testing", "--habito-ui-reset"]
        app.launch()

        let task = app.buttons[seededTaskIdentifier]
        XCTAssertTrue(task.waitForExistence(timeout: 5))
        task.tap()

        let snooze = app.buttons["kid.session.snooze"]
        XCTAssertTrue(snooze.waitForExistence(timeout: 5))
        snooze.tap()

        let feedback = app.descendants(matching: .any)["kid.session.snooze-feedback"]
        XCTAssertTrue(feedback.waitForExistence(timeout: 5))
        XCTAssertEqual(feedback.label, "好，10 分钟后提醒你。")
    }

    func testSnoozeExplainsDeniedNotificationsWithoutBlockingCompletion() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = makeApplication()
        app.launchArguments = ["--habito-ui-testing", "--habito-ui-reset", "--habito-ui-notifications-denied"]
        app.launch()
        let task = app.buttons[seededTaskIdentifier]
        XCTAssertTrue(task.waitForExistence(timeout: 5))
        task.tap()
        let snooze = app.buttons["kid.session.snooze"]
        XCTAssertTrue(snooze.waitForExistence(timeout: 5))
        snooze.tap()
        let feedback = app.descendants(matching: .any)["kid.session.snooze-feedback"]
        XCTAssertTrue(feedback.waitForExistence(timeout: 5))
        XCTAssertEqual(feedback.label, "提醒还没打开，请找家长打开。")
        app.buttons["kid.session.complete"].tap()
        XCTAssertTrue(app.buttons["kid.session.undo"].waitForExistence(timeout: 5))
    }

    func testParentCanRetryFailedNotificationScheduling() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = makeApplication()
        app.launchArguments = ["--habito-ui-testing", "--habito-ui-reset", "--habito-ui-notifications-fail"]
        app.launch()
        unlockParent(in: app)
        app.buttons["parent.notifications.open"].tap()
        let failure = app.descendants(matching: .any)["parent.notifications.scheduling-error"]
        XCTAssertTrue(failure.waitForExistence(timeout: 5))
        let retry = app.buttons["parent.notifications.scheduling-retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        retry.tap()
        XCTAssertTrue(failure.waitForExistence(timeout: 5))
    }

    func testParentGateOpensWithTapAndPersistsCredentialAcrossRelaunch() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = makeApplication()
        app.launchArguments = ["--habito-ui-testing", "--habito-ui-reset"]
        app.launch()

        let entry = app.buttons["parent.gate.entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        let pin = app.secureTextFields["parent.gate.pin"]
        let confirmation = app.secureTextFields["parent.gate.pin-confirmation"]
        XCTAssertTrue(pin.waitForExistence(timeout: 5))
        pin.tap()
        pin.typeText("1357")
        confirmation.tap()
        confirmation.typeText("1357")
        app.buttons["parent.gate.create"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["parent.gate.unlocked"].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.buttons["parent.templates.create"].exists)
        app.buttons["parent.templates.create"].tap()
        let title = app.textFields["parent.templates.editor.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("数学练习")
        app.buttons["parent.templates.editor.save"].tap()
        XCTAssertTrue(app.staticTexts["数学练习"].waitForExistence(timeout: 5))

        let template = app.buttons[seededTemplateIdentifier]
        XCTAssertTrue(template.waitForExistence(timeout: 5))
        template.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["parent.templates.editor"].waitForExistence(
                timeout: 5
            )
        )
        let archive = app.buttons["parent.templates.lifecycle.archive"]
        scrollFullyIntoEditorViewport(archive, in: app)
        XCTAssertTrue(archive.waitForExistence(timeout: 5))
        archive.tap()
        let lifecycleConfirmation = app.buttons["parent.templates.lifecycle.confirm"].firstMatch
        XCTAssertTrue(lifecycleConfirmation.waitForExistence(timeout: 5))
        app.buttons["parent.templates.lifecycle.cancel"].firstMatch.tap()
        XCTAssertTrue(app.buttons["parent.templates.lifecycle.disable"].exists)

        app.buttons["parent.templates.lifecycle.disable"].tap()
        lifecycleConfirmation.tap()
        XCTAssertTrue(app.buttons["parent.templates.lifecycle.enable"].waitForExistence(timeout: 5))

        app.terminate()
        app.launchArguments = ["--habito-ui-testing"]
        app.launch()
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        XCTAssertTrue(pin.waitForExistence(timeout: 5))

        pin.tap()
        pin.typeText("0000")
        app.buttons["parent.gate.unlock"].tap()
        XCTAssertFalse(app.descendants(matching: .any)["parent.gate.unlocked"].exists)

        pin.tap()
        pin.typeText("1357")
        app.buttons["parent.gate.unlock"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["parent.gate.unlocked"].waitForExistence(timeout: 5)
        )
    }

    func testParentCanSkipRestoreAndCorrectTodayTask() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = makeApplication()
        app.launchArguments = ["--habito-ui-testing", "--habito-ui-reset"]
        app.launch()

        let entry = app.buttons["parent.gate.entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        let pin = app.secureTextFields["parent.gate.pin"]
        let confirmation = app.secureTextFields["parent.gate.pin-confirmation"]
        XCTAssertTrue(pin.waitForExistence(timeout: 5))
        pin.tap()
        pin.typeText("1357")
        confirmation.tap()
        confirmation.typeText("1357")
        app.buttons["parent.gate.create"].tap()

        let today = app.buttons["parent.today.open"]
        XCTAssertTrue(today.waitForExistence(timeout: 5))
        today.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)[parentTodayTaskIdentifier].waitForExistence(timeout: 5)
        )

        let actions = app.buttons["操作"]
        XCTAssertTrue(actions.waitForExistence(timeout: 5))
        actions.tap()
        app.buttons["跳过今天"].tap()
        XCTAssertTrue(app.staticTexts["已跳过"].waitForExistence(timeout: 5))

        actions.tap()
        app.buttons["恢复任务"].tap()
        XCTAssertTrue(app.staticTexts["待完成"].waitForExistence(timeout: 5))

        actions.tap()
        app.buttons["更正为已完成"].tap()
        XCTAssertTrue(app.staticTexts["已完成"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["由家长更正"].exists)
    }

    func testParentNotificationDiagnosticsShowsIndependentStates() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = makeApplication()
        app.launchArguments = ["--habito-ui-testing", "--habito-ui-reset"]
        app.launch()

        unlockParent(in: app)
        let diagnostics = app.buttons["parent.notifications.open"]
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 5))
        diagnostics.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["parent.notifications.screen"].waitForExistence(
                timeout: 5
            )
        )
        XCTAssertTrue(app.staticTexts["通知权限"].exists)
        XCTAssertTrue(app.staticTexts["提醒显示"].exists)
        XCTAssertTrue(app.staticTexts["提醒声音"].exists)
        XCTAssertTrue(app.staticTexts["parent.notifications.primary-count"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["parent.notifications.scheduling-retry"].exists)
    }

    func testParentCanPreviewHolidayAndRestoreTasksByRemovingOverride() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = makeApplication()
        app.launchArguments = ["--habito-ui-testing", "--habito-ui-reset"]
        app.launch()

        let entry = app.buttons["parent.gate.entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        let pin = app.secureTextFields["parent.gate.pin"]
        let confirmation = app.secureTextFields["parent.gate.pin-confirmation"]
        XCTAssertTrue(pin.waitForExistence(timeout: 5))
        pin.tap()
        pin.typeText("1357")
        confirmation.tap()
        confirmation.typeText("1357")
        app.buttons["parent.gate.create"].tap()

        let calendar = app.buttons["parent.calendar.open"]
        XCTAssertTrue(calendar.waitForExistence(timeout: 5))
        calendar.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["parent.calendar.screen"].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts["阅读 15 分钟"].waitForExistence(timeout: 5))

        let holiday = app.buttons["parent.calendar.holiday"]
        if !holiday.exists {
            app.swipeUp()
        }
        XCTAssertTrue(holiday.waitForExistence(timeout: 5))
        holiday.tap()
        let confirm = app.buttons["parent.calendar.confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '移除 1 个任务'")).firstMatch.exists)
        confirm.tap()
        XCTAssertTrue(app.staticTexts["这一天没有任务"].waitForExistence(timeout: 5))

        let removeOverride = app.buttons["parent.calendar.remove-override"]
        if !removeOverride.exists {
            app.swipeUp()
        }
        XCTAssertTrue(removeOverride.waitForExistence(timeout: 5))
        removeOverride.tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.staticTexts["阅读 15 分钟"].waitForExistence(timeout: 5))
    }

    func testParentManagementLoopFromEmptyData() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = makeApplication()
        app.launchArguments = [
            "--habito-ui-testing",
            "--habito-ui-reset",
            "--habito-ui-empty",
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["今天没有任务啊"].waitForExistence(timeout: 5))
        unlockParent(in: app)
        XCTAssertTrue(app.staticTexts["还没有任务"].waitForExistence(timeout: 5))

        app.buttons["parent.templates.create"].firstMatch.tap()
        let title = app.textFields["parent.templates.editor.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("闭环阅读")
        app.buttons["parent.templates.editor.save"].tap()
        XCTAssertTrue(app.staticTexts["闭环阅读"].waitForExistence(timeout: 5))

        let template = app.buttons.matching(
            // 首页及时刷新后也有同名任务；必须限定家长模板，不能点击背景孩子卡片。
            NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "parent.templates.item.", "闭环阅读")
        ).firstMatch
        XCTAssertTrue(template.waitForExistence(timeout: 5))
        template.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("已编辑")
        app.buttons["parent.templates.editor.save"].tap()
        XCTAssertTrue(app.staticTexts["闭环阅读已编辑"].waitForExistence(timeout: 5))

        app.buttons["parent.today.open"].tap()
        XCTAssertTrue(app.staticTexts["闭环阅读已编辑"].waitForExistence(timeout: 5))
        app.buttons["操作"].tap()
        app.buttons["调整今天的时间"].tap()
        let saveTime = app.buttons["parent.today.time.save"]
        XCTAssertTrue(saveTime.waitForExistence(timeout: 5))
        saveTime.tap()

        navigateBack(in: app, from: "今日任务管理")
        app.buttons["parent.calendar.open"].tap()
        let holiday = app.buttons["parent.calendar.holiday"]
        if !holiday.exists { app.swipeUp() }
        XCTAssertTrue(holiday.waitForExistence(timeout: 5))
        holiday.tap()
        let calendarConfirm = app.buttons["parent.calendar.confirm"].firstMatch
        XCTAssertTrue(calendarConfirm.waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS '1 个已开始、已完成、已跳过或单日调整的任务会保留'")
            ).firstMatch.exists
        )
        calendarConfirm.tap()

        let removeOverride = app.buttons["parent.calendar.remove-override"]
        if !removeOverride.exists { app.swipeUp() }
        removeOverride.tap()
        XCTAssertTrue(calendarConfirm.waitForExistence(timeout: 5))
        calendarConfirm.tap()

        navigateBack(in: app, from: "日历与放假")
        let editedTemplate = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "parent.templates.item.", "闭环阅读已编辑")
        ).firstMatch
        editedTemplate.tap()
        let disable = app.buttons["parent.templates.lifecycle.disable"]
        scrollFullyIntoEditorViewport(disable, in: app)
        disable.tap()
        let lifecycleConfirm = app.buttons["parent.templates.lifecycle.confirm"].firstMatch
        XCTAssertTrue(lifecycleConfirm.waitForExistence(timeout: 5))
        lifecycleConfirm.tap()
        XCTAssertTrue(app.buttons["parent.templates.lifecycle.enable"].waitForExistence(timeout: 5))

        app.buttons["parent.templates.lifecycle.archive"].tap()
        XCTAssertTrue(lifecycleConfirm.waitForExistence(timeout: 5))
        lifecycleConfirm.tap()
        XCTAssertTrue(app.staticTexts["还没有任务"].waitForExistence(timeout: 5))
    }

    func testFormalConfiguredTemplateProtectsSubmittedRewardThroughEditApprovalAndRestart() throws {
        verifyFormalConfigurationLoop(zeroReward: false)
    }

    func testFormalZeroRewardTemplateConfirmsEffortThroughApprovalAndRestart() throws {
        verifyFormalConfigurationLoop(zeroReward: true)
    }

    func testRewardInputErrorsRemainVisibleAndCorrectableBeforeFormalSave() throws {
        let app = launchEmptyParentEditor(title: "输入可纠正")
        setRewardText("", identifier: "parent.templates.editor.xp", in: app)
        tapEditorSave(in: app)
        let error = app.descendants(matching: .any)["parent.templates.editor.reward-error"]
        scrollFullyIntoEditorViewport(error, in: app)
        XCTAssertTrue(error.label.contains("0 或正整数"))
        XCTAssertTrue(app.buttons["parent.templates.editor.save"].exists)
        setRewardText("9999999999999999999999", identifier: "parent.templates.editor.xp", in: app, towardTop: true)
        tapEditorSave(in: app)
        scrollFullyIntoEditorViewport(error, in: app)
        XCTAssertTrue(error.label.contains("数值没有过大"))
        setRewardText("0", identifier: "parent.templates.editor.xp", in: app, towardTop: true)
        setRewardText(String(Int.max), identifier: "parent.templates.editor.base-coins", in: app)
        setRewardText("1", identifier: "parent.templates.editor.autonomy-coins", in: app)
        tapEditorSave(in: app)
        scrollFullyIntoEditorViewport(error, in: app)
        XCTAssertTrue(error.label.contains("总额过大"))
        keepScreenshot(app, name: "正式配置奖励错误可纠正")
        setRewardText("7", identifier: "parent.templates.editor.base-coins", in: app, towardTop: true)
        tapEditorSave(in: app)
        XCTAssertTrue(parentTemplate(named: "输入可纠正", in: app).waitForExistence(timeout: 5))
    }

    func testLegacyTemplateConfigurationRemainsZeroAndUnassignedAfterTitleEditAndRestart() throws {
        let app = launchScenario("legacy")
        unlockParent(in: app)
        app.buttons[seededTemplateIdentifier].tap()
        assertPickerValue("待设置", identifier: "parent.templates.editor.category", in: app)
        assertPickerValue("全天", identifier: "parent.templates.editor.time-period", in: app)
        assertPickerValue("孩子自行确认", identifier: "parent.templates.editor.verification", in: app)
        for identifier in ["xp", "base-coins", "autonomy-coins"] {
            let input = app.textFields["parent.templates.editor.\(identifier)"]
            scrollFullyIntoEditorViewport(input, in: app)
            XCTAssertEqual(input.value as? String, "0")
        }
        let title = app.textFields["parent.templates.editor.title"]
        scrollFullyIntoEditorViewport(title, in: app, towardTop: true)
        title.tap()
        title.typeText("旧配置保留")
        tapEditorSave(in: app)
        XCTAssertTrue(app.buttons[seededTemplateIdentifier].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = ["--habito-ui-testing"]
        app.launch()
        unlockExistingParent(in: app)
        app.buttons[seededTemplateIdentifier].tap()
        assertPickerValue("待设置", identifier: "parent.templates.editor.category", in: app)
        let xp = app.textFields["parent.templates.editor.xp"]
        scrollFullyIntoEditorViewport(xp, in: app)
        XCTAssertEqual(xp.value as? String, "0")
        keepScreenshot(app, name: "旧任务配置原样回读")
    }

    /// 全程由空库的正式表单生成任务，再走孩子提交与家长验收，不播种 detached 奖励实例。
    private func verifyFormalConfigurationLoop(zeroReward: Bool) {
        let name = zeroReward ? "正式零奖励" : "正式显式奖励"
        let app = launchEmptyParentEditor(title: name)
        chooseEditorOption("成长任务", identifier: "parent.templates.editor.category", in: app)
        chooseEditorOption("晚上", identifier: "parent.templates.editor.time-period", in: app)
        chooseEditorOption("家长验收", identifier: "parent.templates.editor.verification", in: app)
        setRewardText(zeroReward ? "0" : "11", identifier: "parent.templates.editor.xp", in: app)
        setRewardText(zeroReward ? "0" : "7", identifier: "parent.templates.editor.base-coins", in: app)
        setRewardText(zeroReward ? "0" : "3", identifier: "parent.templates.editor.autonomy-coins", in: app)
        keepScreenshot(app, name: "正式配置显式奖励输入")
        tapEditorSave(in: app)
        let template = parentTemplate(named: name, in: app)
        XCTAssertTrue(template.waitForExistence(timeout: 5))
        template.tap()
        assertPickerValue("成长任务", identifier: "parent.templates.editor.category", in: app)
        assertPickerValue("晚上", identifier: "parent.templates.editor.time-period", in: app)
        assertPickerValue("家长验收", identifier: "parent.templates.editor.verification", in: app)
        let xp = app.textFields["parent.templates.editor.xp"]
        scrollFullyIntoEditorViewport(xp, in: app)
        XCTAssertEqual(xp.value as? String, zeroReward ? "0" : "11")
        tapEditorSave(in: app)
        XCTAssertTrue(template.waitForExistence(timeout: 5))
        app.buttons["parent.gate.close"].tap()
        let tasks = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "kid.today.task."))
        XCTAssertEqual(tasks.count, 1)
        let taskID = tasks.element.identifier
        tasks.element.tap()
        let submit = app.buttons["kid.session.submit"]
        scrollFullyIntoSessionViewport(submit, in: app)
        submit.tap()
        assertWaitingWithoutOldActions(in: app)
        returnToTodayFromTask(in: app)
        unlockExistingParent(in: app)
        if !zeroReward {
            // 等待期间编辑正式模板，不得改写这一轮提交的 11/7/3 奖励快照。
            template.tap()
            chooseEditorOption("孩子自行确认", identifier: "parent.templates.editor.verification", in: app)
            setRewardText("41", identifier: "parent.templates.editor.xp", in: app)
            setRewardText("23", identifier: "parent.templates.editor.base-coins", in: app)
            setRewardText("9", identifier: "parent.templates.editor.autonomy-coins", in: app)
            tapEditorSave(in: app)
            XCTAssertTrue(template.waitForExistence(timeout: 5))
        }
        openParentReview(in: app)
        let coins = app.descendants(matching: .any)["parent.review.snapshot-coins"]
        scrollFullyIntoReviewViewport(coins, in: app)
        // 固定测试场景上午提交、正式默认提醒 19:30，严格提前提交。
        XCTAssertTrue(coins.label.contains(zeroReward ? "0" : "10"))
        let approve = reviewAction("approve", in: app)
        scrollFullyIntoReviewViewport(approve, in: app)
        approve.tap()
        XCTAssertTrue(app.staticTexts["已确认通过"].waitForExistence(timeout: 5))
        if zeroReward {
            XCTAssertFalse(app.staticTexts["parent.review.reward-xp"].exists)
            XCTAssertFalse(app.staticTexts["parent.review.reward-coins"].exists)
        } else {
            XCTAssertEqual(app.staticTexts["parent.review.reward-xp"].label, "+11 XP 已到账")
            XCTAssertEqual(app.staticTexts["parent.review.reward-coins"].label, "+10 金币已到账")
        }
        keepScreenshot(app, name: zeroReward ? "正式零奖励完成肯定" : "正式快照审核真实到账")
        app.terminate()
        // 继续同一空库环境但不 reset，避免 Debug 默认播种再加入一条待完成任务。
        app.launchArguments = ["--habito-ui-testing", "--habito-ui-empty"]
        app.launch()
        XCTAssertTrue(app.staticTexts["今天的任务都完成了。"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons[taskID].exists)
        unlockExistingParent(in: app)
        openParentReview(in: app)
        XCTAssertTrue(app.staticTexts["没有待验收任务"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["已确认通过"].exists)
        XCTAssertFalse(app.staticTexts["parent.review.reward-coins"].exists)
    }

    private func launchEmptyParentEditor(title: String) -> XCUIApplication {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = makeApplication()
        app.launchArguments = ["--habito-ui-testing", "--habito-ui-reset", "--habito-ui-empty"]
        app.launch()
        unlockParent(in: app)
        app.buttons["parent.templates.create"].tap()
        let input = app.textFields["parent.templates.editor.title"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText(title)
        return app
    }

    private func parentTemplate(named name: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "parent.templates.item.", name)
        ).element
    }

    /// 先结束原生编辑再保存，避免键盘移动 iPad 弹层时点击落在旧位置。
    private func tapEditorSave(in app: XCUIApplication) {
        let viewport = app.descendants(matching: .any)["parent.templates.editor"]
        let keyboard = app.keyboards.element
        if keyboard.exists, keyboard.isHittable {
            let visibleFrame = formVisibleFrame(viewport, in: app)
            XCTAssertGreaterThan(visibleFrame.height, 0)
            let centerY = (visibleFrame.midY - viewport.frame.minY) / viewport.frame.height
            let offset = visibleFrame.height * 0.12 / viewport.frame.height
            let start = viewport.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: centerY))
            let end = viewport.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: centerY - offset))
            start.press(forDuration: 0.1, thenDragTo: end)
            let dismissed = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "hittable == false"), object: keyboard)
            XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
        }
        let save = app.buttons["parent.templates.editor.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        // 保存位于表单安全区的固定操作栏，而非导航栏；仍要求完整可见和真实可点击。
        XCTAssertTrue(app.frame.contains(save.frame))
        XCTAssertTrue(save.isHittable)
        XCTAssertGreaterThanOrEqual(save.frame.width, 44)
        XCTAssertGreaterThanOrEqual(save.frame.height, 44)
        save.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func chooseEditorOption(_ option: String, identifier: String, in app: XCUIApplication) {
        let picker = app.buttons[identifier]
        scrollFullyIntoEditorViewport(picker, in: app)
        XCTAssertGreaterThanOrEqual(picker.frame.height, 44)
        picker.tap()
        let choice = app.buttons[option]
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        choice.tap()
        // 导航 Picker 保留选择页供家长核对；使用该页唯一的原生返回按钮回到草稿。
        let selectionTitle: String
        switch identifier {
        case "parent.templates.editor.category": selectionTitle = "任务分类"
        case "parent.templates.editor.time-period": selectionTitle = "时间段"
        default: selectionTitle = "完成确认"
        }
        let selectionBar = app.navigationBars[selectionTitle]
        if selectionBar.exists {
            selectionBar.buttons.element(boundBy: 0).tap()
        }
        assertPickerValue(option, identifier: identifier, in: app)
    }

    private func assertPickerValue(_ value: String, identifier: String, in app: XCUIApplication) {
        let picker = app.buttons[identifier]
        scrollFullyIntoEditorViewport(picker, in: app)
        XCTAssertTrue(picker.label.contains(value) || (picker.value as? String)?.contains(value) == true)
    }

    private func setRewardText(
        _ text: String, identifier: String, in app: XCUIApplication, towardTop: Bool = false
    ) {
        let input = app.textFields[identifier]
        // 错误提示位于奖励区域底部；纠正前方懒加载输入时需要向上寻找，不能继续向底部滚动。
        scrollFullyIntoEditorViewport(input, in: app, towardTop: towardTop)
        XCTAssertGreaterThanOrEqual(input.frame.height, 44)
        let row = app.descendants(matching: .any)[identifier + ".row"]
        XCTAssertTrue(row.exists)
        XCTAssertGreaterThanOrEqual(row.frame.height, 44)
        let oldValue = input.value as? String ?? ""
        let oldText = oldValue == input.placeholderValue ? "" : oldValue
        // 原生边框已暴露完整 44 pt；点击靠下边缘并实际输入，而不是仅验证外框。
        // 使用控件自身的归一化坐标，避免横屏下混用绝对偏移导致落到相邻行。
        let edge = input.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
        edge.tap()
        // 直接切换原生输入框，不为每个字段额外隐藏/重开键盘；需要滚动时 Form 自行收起键盘。
        // UI 焦点仅作切换等待；typeText 和后面的精确回读才证明真实键盘输入，没有使用私有属性。
        let focused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasFocus == true"), object: input)
        let focusResult = XCTWaiter.wait(for: [focused], timeout: 5)
        if focusResult != .completed {
            let diagnostic = XCTAttachment(string: "输入边缘：\(identifier)\n\(app.debugDescription)")
            diagnostic.name = "奖励边缘焦点与键盘诊断"
            diagnostic.lifetime = .keepAlways
            add(diagnostic)
        }
        XCTAssertEqual(focusResult, .completed, "边缘点击应让当前输入框获得焦点")
        input.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: oldText.count) + text)
        let newValue = input.value as? String ?? ""
        // XCTest 将空 TextField 的 placeholder 作为 value；金额仍必须精确回读，空值再由保存错误验证。
        XCTAssertEqual(newValue == input.placeholderValue ? "" : newValue, text)
    }

    /// 原生 Form 懒加载内容；小幅滚动到控件完整可见再操作，不把边缘命中当验收。
    private func scrollFullyIntoEditorViewport(_ element: XCUIElement, in app: XCUIApplication, towardTop: Bool = false)
    {
        let viewport = app.descendants(matching: .any)["parent.templates.editor"]
        scrollFullyIntoFormViewport(element, viewport: viewport, in: app, towardTop: towardTop)
    }

    /// 原生自动滚动可能把大字按钮放到键盘后；只在实际可视区完整露出后才点击。
    private func scrollFullyIntoPINViewport(_ element: XCUIElement, in app: XCUIApplication) {
        let viewport = app.descendants(matching: .any)["parent.gate.form"]
        scrollFullyIntoFormViewport(element, viewport: viewport, in: app)
    }

    private func scrollFullyIntoFormViewport(
        _ element: XCUIElement, viewport: XCUIElement, in app: XCUIApplication, towardTop: Bool = false
    ) {
        XCTAssertTrue(viewport.waitForExistence(timeout: 5))
        for _ in 0..<25 {
            let visibleFrame = formVisibleFrame(viewport, in: app)
            guard visibleFrame.height > 0 else {
                XCTFail("表单应保留可操作区域")
                return
            }
            if element.exists, element.isHittable, visibleFrame.contains(element.frame) { return }
            let distance =
                element.exists ? (element.frame.midY - visibleFrame.midY) / visibleFrame.height : (towardTop ? -1 : 1)
            // 归一化坐标属于完整 Form；把可视区内的位移换算后，拖动终点也不能落进导航栏/键盘。
            let displacement =
                min(max(abs(distance), 0.12), 0.35) * visibleFrame.height / viewport.frame.height
                * (distance < 0 ? 1.0 : -1.0)
            let centerY = (visibleFrame.midY - viewport.frame.minY) / viewport.frame.height
            // 左侧行外留白避开输入光标与右侧系统滚动条，后者可能把拖动当成滚动条操作。
            let start = viewport.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: centerY))
            let end = viewport.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: centerY + displacement))
            start.press(forDuration: 0.1, thenDragTo: end)
        }
        keepScreenshot(app, name: "正式编辑器滚动边界失败")
        let targetFrame = element.exists ? String(describing: element.frame) : "尚未出现"
        let diagnostic = XCTAttachment(
            string: "目标：\(targetFrame)\n表单：\(viewport.frame)\n\(app.debugDescription)"
        )
        diagnostic.name = "原生表单可视区与键盘诊断"
        diagnostic.lifetime = .keepAlways
        add(diagnostic)
        // 只有循环内扣除键盘后的完整可见才可成功，不能在结束时退回更宽松的外框判断。
        XCTFail("编辑控件应完整可见")
    }

    /// 使用当前快照中的公开 frame 扣除遮挡，不能从 debugDescription 解析坐标作断言。
    private func formVisibleFrame(_ viewport: XCUIElement, in app: XCUIApplication) -> CGRect {
        var visibleFrame = viewport.frame
        // 17 的全屏弹层仍暴露背景“今日”导航栏；只能扣当前表单自己的原生导航栏。
        let currentTitles = viewport.identifier == "parent.gate.form" ? ["家长入口"] : ["新建任务", "编辑任务"]
        let navigationBars = app.navigationBars.matching(NSPredicate(format: "identifier IN %@", currentTitles))
        XCTAssertEqual(navigationBars.count, 1, "当前表单应只有一个导航栏")
        for navigationBar in navigationBars.allElementsBoundByIndex {
            let frame = navigationBar.frame
            if frame.intersects(visibleFrame) {
                let oldBottom = visibleFrame.maxY
                visibleFrame.origin.y = max(visibleFrame.minY, frame.maxY)
                visibleFrame.size.height = max(0, oldBottom - visibleFrame.minY)
            }
        }
        // Keyboard 不包含上方的系统输入工具栏；二者都可能覆盖 Form。
        let keyboard = app.keyboards.element
        let assistant = app.otherElements["SystemInputAssistantView"]
        // Form 的 AX frame 包含底部安全区；固定保存栏也必须从输入的真实可视区扣除。
        let saveBar = app.descendants(matching: .any)["parent.templates.editor.save-bar"]
        for obstruction in [keyboard, assistant, saveBar] where obstruction.exists {
            let frame = obstruction.frame
            if frame.intersects(visibleFrame), frame.minY > visibleFrame.minY {
                visibleFrame.size.height = min(visibleFrame.maxY, frame.minY) - visibleFrame.minY
            }
        }
        return visibleFrame
    }

    func testParentApprovalSubmissionWaitsWithoutRewardOrOldActionsAcrossRelaunch() throws {
        let app = launchScenario("parent-approval")
        openSeededTask(in: app)
        app.buttons["kid.session.start"].tap()
        XCTAssertTrue(app.buttons["kid.session.pause"].waitForExistence(timeout: 5))
        let submit = app.buttons["kid.session.submit"]
        XCTAssertTrue(submit.exists)
        XCTAssertEqual(submit.label, "提交给家长")
        submit.tap()
        assertWaitingWithoutOldActions(in: app)
        XCTAssertTrue(app.staticTexts["已提交！"].exists)
        app.buttons["kid.session.dismiss-completion-feedback"].tap()
        XCTAssertFalse(app.staticTexts["已提交！"].exists)
        keepScreenshot(app, name: "审核任务提交等待")

        // 旧通知只能回首页；再次进入从磁盘读等待状态，不能重播局部收据。
        relaunchWithOldSeededNotification(app)
        let task = app.buttons[seededTaskIdentifier]
        XCTAssertTrue(task.waitForExistence(timeout: 5))
        XCTAssertTrue(task.label.contains("等家长确认"))
        task.tap()
        assertWaitingWithoutOldActions(in: app)
        XCTAssertFalse(app.staticTexts["已提交！"].exists)
        XCTAssertFalse(app.buttons["kid.session.dismiss-completion-feedback"].exists)
    }

    func testReturnedSubmissionEncouragesContinuingAndResubmitsWithoutReward() throws {
        let app = launchScenario("returned-submission")
        let task = app.buttons[seededTaskIdentifier]
        XCTAssertTrue(task.waitForExistence(timeout: 5))
        XCTAssertTrue(task.label.contains("再完善一下"))
        task.tap()
        let status = app.descendants(matching: .any)["kid.session.submission-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue(status.label.contains("准备好就再提交"))
        XCTAssertTrue(app.buttons["kid.session.start"].exists)
        XCTAssertTrue(app.buttons["kid.session.submit"].exists)
        keepScreenshot(app, name: "退回继续完善")
        app.buttons["kid.session.start"].tap()
        XCTAssertTrue(app.buttons["kid.session.pause"].waitForExistence(timeout: 5))
        app.buttons["kid.session.submit"].tap()
        assertWaitingWithoutOldActions(in: app)
    }

    func testSelfConfirmShowsActualRewardsOnceAndUndoRemainsReachable() throws {
        let app = launchScenario("reward-self-confirm")
        openSeededTask(in: app)
        app.buttons["kid.session.complete"].tap()
        let undo = app.buttons["kid.session.undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 2))
        XCTAssertTrue(undo.isHittable)
        XCTAssertTrue(app.staticTexts["你做到了！"].exists)
        XCTAssertTrue(app.staticTexts["你自己记得做啦！"].exists)
        let xp = app.descendants(matching: .any)["kid.session.reward-xp"]
        let coins = app.descendants(matching: .any)["kid.session.reward-coins"]
        XCTAssertTrue(xp.exists)
        XCTAssertTrue(coins.exists)
        XCTAssertEqual(xp.label, "+11 XP 已到账")
        XCTAssertEqual(coins.label, "+10 金币已到账")
        keepScreenshot(app, name: "真实奖励到账")
        app.buttons["kid.session.dismiss-completion-feedback"].tap()
        XCTAssertFalse(xp.exists)
        XCTAssertFalse(coins.exists)
        XCTAssertFalse(app.staticTexts["你做到了！"].exists)
        relaunchWithOldSeededNotification(app)
        XCTAssertTrue(app.staticTexts["今天的任务都完成了。"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["你做到了！"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["kid.session.reward-xp"].exists)
    }

    func testZeroRewardStillEncouragesCompletionWithoutInventingCurrency() throws {
        let app = launchScenario("legacy")
        openSeededTask(in: app)
        app.buttons["kid.session.complete"].tap()
        XCTAssertTrue(app.staticTexts["你做到了！"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["kid.session.reward-xp"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["kid.session.reward-coins"].exists)
        XCTAssertTrue(app.buttons["kid.session.dismiss-completion-feedback"].isHittable)
    }

    /// 字号由验收命令的 simctl ui content_size 设置；不使用未验证的私有启动参数。
    func testSubmissionAndWaitingRemainReadableAndReachableWithSystemTextSize() throws {
        let app = launchScenario("parent-approval")
        openSeededTask(in: app)
        let submit = app.buttons["kid.session.submit"]
        scrollFullyIntoSessionViewport(submit, in: app)
        XCTAssertTrue(submit.isHittable)
        XCTAssertGreaterThanOrEqual(submit.frame.height, 44)
        submit.tap()
        let status = app.descendants(matching: .any)["kid.session.submission-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        scrollFullyIntoSessionViewport(status, in: app)
        XCTAssertTrue(status.label.contains("等家长确认"))
        // 读屏合并状态有文字而非仅颜色；真机 VoiceOver 手势验收仍后置。
        XCTAssertTrue(status.label.contains("提交已经保存"))
        keepScreenshot(app, name: "系统字号等待状态")
        let dismiss = app.buttons["kid.session.dismiss-completion-feedback"]
        scrollFullyIntoSessionViewport(dismiss, in: app)
        XCTAssertTrue(dismiss.isHittable)
        XCTAssertGreaterThanOrEqual(dismiss.frame.height, 44)
        keepScreenshot(app, name: "辅助大字等待与反馈")
        dismiss.tap()
        XCTAssertFalse(dismiss.exists)
        XCTAssertFalse(app.staticTexts["已提交！"].exists)
    }

    func testParentReviewRequiresPINAndApprovesOriginalSnapshotOnce() throws {
        let app = submitSeededTaskForReview()
        XCTAssertFalse(app.buttons["parent.review.open"].exists)
        unlockParent(in: app)
        openParentReview(in: app)
        XCTAssertTrue(app.staticTexts["以下是通过后的预期奖励，现在还没有到账。"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["在提醒前主动提交"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["parent.review.reward-xp"].exists)
        let approve = reviewAction("approve", in: app)
        approve.tap()
        XCTAssertTrue(app.staticTexts["已确认通过"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["parent.review.reward-xp"].label, "+11 XP 已到账")
        XCTAssertEqual(app.staticTexts["parent.review.reward-coins"].label, "+10 金币已到账")
        XCTAssertFalse(reviewActions("approve", in: app).element.exists)
        keepScreenshot(app, name: "PIN 后真实验收到账")
        navigateBack(in: app, from: "待验收")
        openParentReview(in: app)
        XCTAssertTrue(app.staticTexts["没有待验收任务"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["已确认通过"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["parent.review.reward-coins"].exists)

        app.terminate()
        app.launchArguments = ["--habito-ui-testing"]
        app.launch()
        XCTAssertTrue(app.staticTexts["今天的任务都完成了。"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["parent.review.open"].exists)
        unlockExistingParent(in: app, verifyWrongPIN: true)
        openParentReview(in: app)
        XCTAssertTrue(app.staticTexts["没有待验收任务"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["已确认通过"].exists)
    }

    func testParentReviewReturnKeepsTaskAndDoesNotGrantReward() throws {
        let app = submitSeededTaskForReview()
        unlockParent(in: app)
        openParentReview(in: app)
        reviewAction("return", in: app).tap()
        XCTAssertTrue(app.staticTexts["已请孩子再完善"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["累计计时已经保留。和孩子一起再看看，准备好后重新提交。"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["parent.review.reward-xp"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["parent.review.reward-coins"].exists)
        XCTAssertFalse(reviewActions("return", in: app).element.exists)
        keepScreenshot(app, name: "家长退回不惩罚")
        // 家长关闭按钮属于管理首页；审核详情先沿原导航返回，不假设根工具栏跨目的页保留。
        navigateBack(in: app, from: "待验收")
        app.buttons["parent.gate.close"].tap()
        let task = app.buttons[seededTaskIdentifier]
        XCTAssertTrue(task.waitForExistence(timeout: 5))
        XCTAssertTrue(task.label.contains("再完善一下"))
        task.tap()
        XCTAssertTrue(app.buttons["kid.session.start"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["kid.session.submit"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["kid.session.reward-xp"].exists)
    }

    func testParentReviewEmptyQueueDoesNotGuessLegacyTaskNeedsApproval() throws {
        let app = launchScenario("legacy")
        unlockParent(in: app)
        openParentReview(in: app)
        XCTAssertTrue(app.staticTexts["没有待验收任务"].waitForExistence(timeout: 5))
        XCTAssertFalse(reviewActions("approve", in: app).element.exists)
        XCTAssertFalse(reviewActions("return", in: app).element.exists)
        keepScreenshot(app, name: "待验收空队列")
    }

    func testParentReviewFailedApprovalKeepsWaitingAndCanRetryAfterRelaunch() throws {
        verifyFailedParentReview(action: "approve")
    }

    func testParentReviewFailedReturnKeepsWaitingAndCanRetryAfterRelaunch() throws {
        verifyFailedParentReview(action: "return")
    }

    /// 系统字号由外部 simctl 原生设置；实际审核/关闭断言，不能仅靠存在判断可达。
    func testParentReviewActionsRemainReachableWithSystemTextSize() throws {
        let app = submitSeededTaskForReview()
        unlockParent(in: app)
        openParentReview(in: app)
        let submitted = app.descendants(matching: .any)["parent.review.snapshot-submitted"]
        scrollFullyIntoReviewViewport(submitted, in: app)
        XCTAssertTrue(submitted.label.contains("孩子提交时间") && submitted.label.contains("2026"))
        let expectedCoins = app.descendants(matching: .any)["parent.review.snapshot-coins"]
        scrollFullyIntoReviewViewport(expectedCoins, in: app)
        XCTAssertTrue(expectedCoins.label.contains("通过后金币") && expectedCoins.label.contains("10"))
        keepScreenshot(app, name: "系统大字审核明细")
        let approve = reviewAction("approve", in: app)
        scrollFullyIntoReviewViewport(approve, in: app)
        XCTAssertEqual(approve.label, "确认通过")
        XCTAssertGreaterThanOrEqual(approve.frame.height, 44)
        let returned = reviewAction("return", in: app)
        scrollFullyIntoReviewViewport(returned, in: app)
        XCTAssertEqual(returned.label, "请孩子再完善")
        XCTAssertGreaterThanOrEqual(returned.frame.height, 44)
        keepScreenshot(app, name: "系统大字审核操作")
        scrollFullyIntoReviewViewport(approve, in: app)
        approve.tap()
        XCTAssertTrue(app.staticTexts["已确认通过"].waitForExistence(timeout: 5))
        let dismiss = app.buttons["parent.review.dismiss-feedback"]
        scrollFullyIntoReviewViewport(dismiss, in: app)
        XCTAssertGreaterThanOrEqual(dismiss.frame.height, 44)
        keepScreenshot(app, name: "系统大字真实审核结果")
        dismiss.tap()
        XCTAssertFalse(dismiss.exists)
        XCTAssertFalse(app.staticTexts["已确认通过"].exists)
    }

    func testTimedReviewReturnResubmissionApprovalAndRelaunchKeepOneReward() throws {
        verifyReviewRoundTrip(zeroReward: false)
    }

    func testZeroRewardReviewRoundTripStillConfirmsEffortWithoutInventingCurrency() throws {
        verifyReviewRoundTrip(zeroReward: true)
    }

    /// 两轮都由实际孩子/家长页面提交；重启不 reset，避免播种替代真实状态恢复。
    private func verifyReviewRoundTrip(zeroReward: Bool) {
        let app = launchScenario(zeroReward ? "zero-reward-parent-approval" : "parent-approval")
        openSeededTask(in: app)
        app.buttons["kid.session.start"].tap()
        let pause = app.buttons["kid.session.pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        pause.tap()
        app.buttons["kid.session.submit"].tap()
        assertWaitingWithoutOldActions(in: app)
        returnToTodayFromTask(in: app)
        unlockParent(in: app)
        openParentReview(in: app)
        let firstRequestID = reviewAction("approve", in: app).identifier
        reviewAction("return", in: app).tap()
        XCTAssertTrue(app.staticTexts["已请孩子再完善"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["parent.review.reward-xp"].exists)
        XCTAssertFalse(app.staticTexts["parent.review.reward-coins"].exists)
        navigateBack(in: app, from: "待验收")
        app.buttons["parent.gate.close"].tap()

        app.terminate()
        app.launchArguments = ["--habito-ui-testing"]
        app.launch()
        let task = app.buttons[seededTaskIdentifier]
        XCTAssertTrue(task.waitForExistence(timeout: 5))
        XCTAssertTrue(task.label.contains("再完善一下"))
        XCTAssertFalse(app.buttons["parent.review.open"].exists)
        task.tap()
        XCTAssertTrue(app.buttons["kid.session.start"].waitForExistence(timeout: 5))
        app.buttons["kid.session.start"].tap()
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        pause.tap()
        app.buttons["kid.session.submit"].tap()
        assertWaitingWithoutOldActions(in: app)
        returnToTodayFromTask(in: app)
        unlockExistingParent(in: app)
        openParentReview(in: app)
        let secondRequest = reviewAction("approve", in: app)
        XCTAssertNotEqual(secondRequest.identifier, firstRequestID, "重提必须审核新 ID，不能重用退回请求")
        // UI 操作可能跨过真实 60 秒提醒；结算需跟随第二次提交快照，不能硬假设仍自主。
        let secondWasAutonomous = app.staticTexts["在提醒前主动提交"].exists
        if !secondWasAutonomous { XCTAssertTrue(app.staticTexts["提交时已到提醒时间"].exists) }
        secondRequest.tap()
        XCTAssertTrue(app.staticTexts["已确认通过"].waitForExistence(timeout: 5))
        if zeroReward {
            XCTAssertFalse(app.staticTexts["parent.review.reward-xp"].exists)
            XCTAssertFalse(app.staticTexts["parent.review.reward-coins"].exists)
        } else {
            XCTAssertEqual(app.staticTexts["parent.review.reward-xp"].label, "+11 XP 已到账")
            XCTAssertEqual(
                app.staticTexts["parent.review.reward-coins"].label,
                secondWasAutonomous ? "+10 金币已到账" : "+7 金币已到账")
        }
        XCTAssertFalse(reviewActions("approve", in: app).element.exists)
        keepScreenshot(app, name: zeroReward ? "零奖励两轮真实审核完成" : "计时退回重提真实审核完成")
        navigateBack(in: app, from: "待验收")
        app.buttons["parent.gate.close"].tap()
        XCTAssertTrue(app.staticTexts["今天的任务都完成了。"].waitForExistence(timeout: 5))

        relaunchWithOldSeededNotification(app)
        XCTAssertTrue(app.staticTexts["今天的任务都完成了。"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["你做到了！"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["kid.session.reward-xp"].exists)
        unlockExistingParent(in: app, verifyWrongPIN: true)
        openParentReview(in: app)
        XCTAssertTrue(app.staticTexts["没有待验收任务"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["已确认通过"].exists)
        XCTAssertFalse(reviewActions("approve", in: app).element.exists)
    }

    private func returnToTodayFromTask(in app: XCUIApplication) {
        let back = app.navigationBars["任务"].buttons["今日"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
    }

    private func verifyFailedParentReview(action: String) {
        let app = submitSeededTaskForReview(extraArguments: ["--habito-ui-review-save-fail"])
        unlockParent(in: app)
        openParentReview(in: app)
        reviewAction(action, in: app).tap()
        let alert = app.alerts["这次验收没有完成"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts["验收没有保存成功，任务仍在等待，没有发放奖励。请稍后重试。"].exists)
        keepScreenshot(app, name: "审核保存失败保留等待-\(action)")
        alert.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(reviewAction(action, in: app).exists)
        XCTAssertFalse(app.descendants(matching: .any)["parent.review.reward-xp"].exists)
        XCTAssertFalse(app.staticTexts["已确认通过"].exists)
        XCTAssertFalse(app.staticTexts["已请孩子再完善"].exists)
        app.terminate()
        // 去掉失败注入但不 reset，真正从同一磁盘等待事实重试。
        app.launchArguments = ["--habito-ui-testing"]
        app.launch()
        unlockExistingParent(in: app)
        openParentReview(in: app)
        reviewAction(action, in: app).tap()
        let expectedTitle = action == "approve" ? "已确认通过" : "已请孩子再完善"
        XCTAssertTrue(app.staticTexts[expectedTitle].waitForExistence(timeout: 5))
        XCTAssertFalse(reviewActions(action, in: app).element.exists)
    }

    private func submitSeededTaskForReview(extraArguments: [String] = []) -> XCUIApplication {
        let app = launchScenario("parent-approval", extraArguments: extraArguments)
        openSeededTask(in: app)
        let submit = app.buttons["kid.session.submit"]
        scrollFullyIntoSessionViewport(submit, in: app)
        submit.tap()
        assertWaitingWithoutOldActions(in: app)
        let back = app.navigationBars["任务"].buttons["今日"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        return app
    }

    private func openParentReview(in app: XCUIApplication) {
        let open = app.buttons["parent.review.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()
        XCTAssertTrue(app.scrollViews["parent.review.screen"].waitForExistence(timeout: 5))
    }

    private func reviewActions(_ action: String, in app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "parent.review.\(action)."))
    }

    private func reviewAction(_ action: String, in app: XCUIApplication) -> XCUIElement {
        let actions = reviewActions(action, in: app)
        XCTAssertTrue(actions.element(boundBy: 0).waitForExistence(timeout: 5))
        XCTAssertEqual(actions.count, 1, "合成队列只有一条，不能宽泛取第一条掩盖重复")
        return actions.element(boundBy: 0)
    }

    private func unlockExistingParent(in app: XCUIApplication, verifyWrongPIN: Bool = false) {
        let entry = app.buttons["parent.gate.entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        let pin = app.secureTextFields["parent.gate.pin"]
        XCTAssertTrue(pin.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["parent.review.open"].exists)
        XCTAssertFalse(app.secureTextFields["parent.gate.pin-confirmation"].exists)
        if verifyWrongPIN {
            pin.tap()
            pin.typeText("0000")
            app.buttons["parent.gate.unlock"].tap()
            XCTAssertFalse(app.buttons["parent.review.open"].exists)
        }
        pin.tap()
        pin.typeText("1357")
        let unlock = app.buttons["parent.gate.unlock"]
        scrollFullyIntoPINViewport(unlock, in: app)
        unlock.tap()
        XCTAssertTrue(app.buttons["parent.review.open"].waitForExistence(timeout: 5))
    }

    /// 大字长字段会被整屏 swipe 越过；按实际窗口中心小幅拖动，仍要求内容完整可见。
    private func scrollFullyIntoReviewViewport(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        let viewport = app.scrollViews["parent.review.screen"]
        XCTAssertTrue(viewport.exists)
        for _ in 0..<10 {
            if element.isHittable, viewport.frame.contains(element.frame) { return }
            let distance = (element.frame.midY - viewport.frame.midY) / viewport.frame.height
            let displacement = min(max(abs(distance), 0.08), 0.25) * (distance < 0 ? 1.0 : -1.0)
            let start = viewport.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let end = viewport.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5 + displacement))
            start.press(forDuration: 0.1, thenDragTo: end)
        }
        let diagnostic = XCTAttachment(
            string:
                "元素：\(element.identifier)\n元素 frame：\(element.frame)\n窗口 frame：\(viewport.frame)\n\(element.debugDescription)"
        )
        diagnostic.name = "审核滚动边界诊断"
        diagnostic.lifetime = .keepAlways
        add(diagnostic)
        keepScreenshot(app, name: "审核滚动失败视图")
        XCTAssertTrue(element.isHittable && viewport.frame.contains(element.frame), "审核动作应能完整滚动到可视区域")
    }

    private func launchScenario(_ scenario: String, extraArguments: [String] = []) -> XCUIApplication {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = makeApplication()
        app.launchArguments =
            [
                "--habito-ui-testing", "--habito-ui-reset", "--habito-ui-task-scenario", scenario,
            ] + extraArguments
        app.launch()
        return app
    }

    private func openSeededTask(in app: XCUIApplication) {
        let task = app.buttons[seededTaskIdentifier]
        XCTAssertTrue(task.waitForExistence(timeout: 5))
        task.tap()
        XCTAssertTrue(app.buttons["kid.session.start"].waitForExistence(timeout: 5))
    }

    private func assertWaitingWithoutOldActions(in app: XCUIApplication) {
        let status = app.descendants(matching: .any)["kid.session.submission-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue(status.label.contains("等家长确认"))
        for identifier in [
            "kid.session.start", "kid.session.pause", "kid.session.resume", "kid.session.complete",
            "kid.session.submit", "kid.session.snooze", "kid.session.undo", "kid.session.reward-xp",
            "kid.session.reward-coins",
        ] {
            XCTAssertFalse(app.descendants(matching: .any)[identifier].exists, identifier)
        }
    }

    private func keepScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// 17 在按钮仅露出边缘时也可能报告 isHittable；按真实滚动窗口核对，不能把无效点击算验收。
    private func scrollFullyIntoSessionViewport(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        let viewport = app.scrollViews["kid.session.screen"]
        XCTAssertTrue(viewport.exists)
        for _ in 0..<4 {
            if element.isHittable, viewport.frame.contains(element.frame) { return }
            if element.frame.minY < viewport.frame.minY {
                viewport.swipeDown()
            } else {
                viewport.swipeUp()
            }
        }
        XCTAssertTrue(element.isHittable && viewport.frame.contains(element.frame), "元素应能完整滚动到执行页可视区域")
    }

    /// 同一用例的所有重启沿用相同环境；只隔离场景日期，不冻结计时实际经过的秒数。
    private func makeApplication() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["HABITO_UI_SYSTEM_REFERENCE"] = String(Date.now.timeIntervalSince1970)
        return app
    }

    private func relaunchWithOldSeededNotification(_ app: XCUIApplication) {
        app.terminate()
        app.launchArguments = [
            "--habito-ui-testing",
            "--habito-ui-notification-request",
            "habito.occurrence.c5412144-2fb8-4e96-9f7a-6a42e0803d11.primary",
        ]
        app.launch()
    }

    private func unlockParent(in app: XCUIApplication) {
        let entry = app.buttons["parent.gate.entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        let pin = app.secureTextFields["parent.gate.pin"]
        let confirmation = app.secureTextFields["parent.gate.pin-confirmation"]
        XCTAssertTrue(pin.waitForExistence(timeout: 5))
        pin.tap()
        pin.typeText("1357")
        confirmation.tap()
        confirmation.typeText("1357")
        let create = app.buttons["parent.gate.create"]
        scrollFullyIntoPINViewport(create, in: app)
        create.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["parent.gate.unlocked"].waitForExistence(timeout: 5)
        )
    }

    private func navigateBack(in app: XCUIApplication, from navigationTitle: String) {
        let back = app.navigationBars[navigationTitle].buttons["家长任务"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
    }
}
