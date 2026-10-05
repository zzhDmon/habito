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
        if !archive.exists {
            app.swipeUp()
            app.swipeUp()
        }
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
        if !disable.exists {
            app.swipeUp()
            app.swipeUp()
        }
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

    /// 同一用例的所有重启沿用相同环境；只隔离场景日期，不冻结计时实际经过的秒数。
    private func makeApplication() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["HABITO_UI_SYSTEM_REFERENCE"] = String(Date.now.timeIntervalSince1970)
        return app
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
        app.buttons["parent.gate.create"].tap()
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
