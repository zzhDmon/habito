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

    func testFormalStatisticsOverviewWaitingApprovalSkipAndRestartWithSystemTextSize() throws {
        let names = ["统计自行确认", "统计家长验收", "统计跳过"]
        let app = launchEmptyParentEditor(title: names[0])
        setRewardText("11", identifier: "parent.templates.editor.xp", in: app)
        setRewardText("7", identifier: "parent.templates.editor.base-coins", in: app)
        setRewardText("3", identifier: "parent.templates.editor.autonomy-coins", in: app)
        tapEditorSave(in: app)
        XCTAssertTrue(parentTemplate(named: names[0], in: app).waitForExistence(timeout: 5))
        for name in names.dropFirst() {
            app.buttons["parent.templates.create"].tap()
            let title = app.textFields["parent.templates.editor.title"]
            XCTAssertTrue(title.waitForExistence(timeout: 5))
            title.tap()
            title.typeText(name)
            if name == names[1] {
                chooseEditorOption("家长验收", identifier: "parent.templates.editor.verification", in: app)
            }
            tapEditorSave(in: app)
            XCTAssertTrue(parentTemplate(named: name, in: app).waitForExistence(timeout: 5))
        }
        let skipTemplate = parentTemplate(named: names[2], in: app).identifier
        let completedTemplate = parentTemplate(named: names[0], in: app).identifier
        app.buttons["parent.gate.close"].tap()
        let selfTask = formalKidTask(named: names[0], in: app)
        scrollFullyIntoTodayViewport(selfTask, in: app)
        selfTask.tap()
        let complete = app.buttons["kid.session.complete"]
        scrollFullyIntoSessionViewport(complete, in: app)
        complete.tap()
        let continueButton = app.buttons["kid.session.dismiss-completion-feedback"]
        scrollFullyIntoSessionViewport(continueButton, in: app)
        continueButton.tap()
        returnToTodayFromTask(in: app)
        let reviewTask = formalKidTask(named: names[1], in: app)
        scrollFullyIntoTodayViewport(reviewTask, in: app)
        let reviewOccurrenceID = reviewTask.identifier.replacingOccurrences(of: "kid.today.task.", with: "")
        reviewTask.tap()
        let submit = app.buttons["kid.session.submit"]
        scrollFullyIntoSessionViewport(submit, in: app)
        submit.tap()
        assertWaitingWithoutOldActions(in: app)
        returnToTodayFromTask(in: app)
        unlockExistingParent(in: app)
        app.buttons["parent.today.open"].tap()
        assertStatisticsCounts(
            prefix: "parent.today.overview", completed: 1, eligible: 3,
            autonomous: 1, known: 1, waiting: 1, in: app, screen: "parent.today.screen")
        let parentList = app.collectionViews["parent.today.screen"]
        let waitingRow = parentList.otherElements["parent.today.task." + reviewOccurrenceID].firstMatch
        scrollFullyIntoStatisticsViewport(parentList.staticTexts["待家长验收"], in: app, screen: "parent.today.screen")
        XCTAssertTrue(waitingRow.label.contains("待家长验收") || waitingRow.staticTexts["待家长验收"].exists)
        XCTAssertFalse(app.buttons["parent.today.actions." + reviewOccurrenceID].exists)
        navigateBack(in: app, from: "今日任务管理")
        // 第三项通过正式单日管理跳过，不删除模板或伪造统计事实。
        let skippedTaskTemplateID = skipTemplate.replacingOccurrences(of: "parent.templates.item.", with: "")
        app.buttons["parent.gate.close"].tap()
        let skippedKidTask = formalKidTask(named: names[2], in: app)
        let skippedID = skippedKidTask.identifier.replacingOccurrences(of: "kid.today.task.", with: "")
        unlockExistingParent(in: app)
        app.buttons["parent.today.open"].tap()
        // 17的原生Menu导出外层AX容器和内层按钮，容器不可点；先显示标题再操作真实叶按钮。
        scrollFullyIntoStatisticsViewport(parentList.staticTexts[names[2]], in: app, screen: "parent.today.screen")
        let menu = parentList.buttons["parent.today.actions." + skippedID]
        XCTAssertTrue(menu.exists)
        let actions = menu.buttons.firstMatch.exists ? menu.buttons.firstMatch : menu
        let menuHierarchy = XCTAttachment(string: app.debugDescription)
        menuHierarchy.name = "统计跳过前原生菜单层级"
        menuHierarchy.lifetime = .keepAlways
        add(menuHierarchy)
        scrollFullyIntoStatisticsViewport(actions, in: app, screen: "parent.today.screen")
        XCTAssertGreaterThanOrEqual(actions.frame.height, 44)
        actions.tap()
        app.buttons["跳过今天"].tap()
        assertStatisticsCounts(
            prefix: "parent.today.overview", completed: 1, eligible: 2,
            autonomous: 1, known: 1, waiting: 1, in: app, screen: "parent.today.screen", towardTop: true)
        navigateBack(in: app, from: "今日任务管理")
        openParentReview(in: app)
        let approve = reviewAction("approve", in: app)
        scrollFullyIntoReviewViewport(approve, in: app)
        approve.tap()
        XCTAssertTrue(app.staticTexts["已确认通过"].waitForExistence(timeout: 5))
        navigateBack(in: app, from: "待验收")
        openStatistics(in: app)
        assertStatisticsCounts(
            prefix: "parent.statistics.total", completed: 2, eligible: 2,
            autonomous: 2, known: 2, waiting: 0, in: app)
        let sources = app.staticTexts["parent.statistics.total.sources"]
        scrollFullyIntoStatisticsViewport(sources, in: app)
        XCTAssertEqual(sources.label, "孩子确认：1；家长验收：1；家长更正：0")
        let daySample = app.staticTexts["parent.statistics.day.2026-09-27.completion.sample"]
        scrollFullyIntoStatisticsViewport(daySample, in: app)
        XCTAssertEqual(daySample.label, "达成 2 / 样本 2")
        let templateID = completedTemplate.replacingOccurrences(of: "parent.templates.item.", with: "")
        let disclosure = app.buttons["parent.statistics.task." + templateID + ".disclosure"].firstMatch
        scrollFullyIntoStatisticsViewport(disclosure, in: app)
        XCTAssertGreaterThanOrEqual(disclosure.frame.height, 44)
        disclosure.tap()
        let taskSample = app.staticTexts["parent.statistics.task." + templateID + ".completion.sample"]
        scrollFullyIntoStatisticsViewport(taskSample, in: app)
        XCTAssertEqual(taskSample.label, "达成 1 / 样本 1")
        // 检查一项后收起其日明细，再找下一项；避免MAX下滚过无关的整周明细。
        scrollFullyIntoStatisticsViewport(disclosure, in: app, towardTop: true)
        disclosure.tap()
        let skippedDisclosure = app.buttons[
            "parent.statistics.task." + skippedTaskTemplateID + ".disclosure"
        ].firstMatch
        scrollFullyIntoStatisticsViewport(skippedDisclosure, in: app)
        skippedDisclosure.tap()
        let skippedSample = app.staticTexts["parent.statistics.task." + skippedTaskTemplateID + ".completion.sample"]
        scrollFullyIntoStatisticsViewport(skippedSample, in: app)
        XCTAssertEqual(skippedSample.label, "达成 0 / 样本 0")
        for days in [14, 30, 7] { selectStatisticsPeriod(days, in: app) }
        keepScreenshot(app, name: "正式统计完成审核跳过窗口与任务趋势")
        app.terminate()
        app.launchArguments = ["--habito-ui-testing", "--habito-ui-empty"]
        app.launch()
        unlockExistingParent(in: app)
        openStatistics(in: app)
        assertStatisticsCounts(
            prefix: "parent.statistics.total", completed: 2, eligible: 2,
            autonomous: 2, known: 2, waiting: 0, in: app)
        XCTAssertFalse(app.staticTexts["parent.statistics.error"].exists)
        keepScreenshot(app, name: "统计真实磁盘重启读回")
    }

    func testStatisticsEmptyReadFailureRetriesWithoutPreloadingBeforePINWithSystemTextSize() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = makeApplication()
        app.launchArguments = [
            "--habito-ui-testing", "--habito-ui-reset", "--habito-ui-empty", "--habito-ui-statistics-read-fail-once",
        ]
        app.launch()
        XCTAssertFalse(app.buttons["parent.statistics.open"].exists)
        XCTAssertFalse(app.staticTexts["parent.statistics.total.completion.value"].exists)
        unlockParent(in: app)
        openStatistics(in: app)
        let retry = app.buttons["parent.statistics.retry"]
        scrollFullyIntoStatisticsViewport(retry, in: app)
        XCTAssertTrue(app.staticTexts["统计暂时无法读取"].exists)
        XCTAssertFalse(app.staticTexts["parent.statistics.total.completion.value"].exists)
        XCTAssertGreaterThanOrEqual(retry.frame.width, 44)
        XCTAssertGreaterThanOrEqual(retry.frame.height, 44)
        keepScreenshot(app, name: "统计读取错误不显示旧比例")
        retry.tap()
        assertStatisticsCounts(
            prefix: "parent.statistics.total", completed: 0, eligible: 0,
            autonomous: 0, known: 0, waiting: 0, in: app)
        XCTAssertEqual(app.staticTexts["parent.statistics.total.completion.value"].label, "暂无数据")
        for days in [14, 30, 7] { selectStatisticsPeriod(days, in: app) }
        let refresh = app.buttons["parent.statistics.refresh"]
        scrollFullyIntoStatisticsViewport(refresh, in: app, towardTop: true)
        XCTAssertTrue(refresh.isHittable)
        XCTAssertGreaterThanOrEqual(refresh.frame.height, 44)
        refresh.tap()
        XCTAssertFalse(app.buttons["parent.statistics.retry"].exists)
        keepScreenshot(app, name: "统计空样本同进程重试及MAX窗口")
    }

    func testStatisticsOrdinaryCompletionIsNotAutonomousWithSystemTextSize() throws {
        let app = launchScenario("reward-after-reminder")
        openSeededTask(in: app)
        let complete = app.buttons["kid.session.complete"]
        scrollFullyIntoSessionViewport(complete, in: app)
        complete.tap()
        let continueButton = app.buttons["kid.session.dismiss-completion-feedback"]
        scrollFullyIntoSessionViewport(continueButton, in: app)
        continueButton.tap()
        returnToTodayFromTask(in: app)
        unlockParent(in: app)
        openStatistics(in: app)
        assertStatisticsCounts(
            prefix: "parent.statistics.total", completed: 1, eligible: 1,
            autonomous: 0, known: 1, waiting: 0, in: app)
        XCTAssertEqual(app.staticTexts["parent.statistics.total.completion.value"].label, "100%")
        XCTAssertEqual(app.staticTexts["parent.statistics.total.autonomy.value"].label, "0%")
        navigateBack(in: app, from: "成长统计")
        app.buttons["parent.today.open"].tap()
        let row = app.collectionViews["parent.today.screen"].otherElements[parentTodayTaskIdentifier].firstMatch
        scrollFullyIntoStatisticsViewport(app.staticTexts["非自主完成（提醒时刻或之后提交）"], in: app, screen: "parent.today.screen")
        XCTAssertTrue(row.label.contains("非自主完成") || row.staticTexts["非自主完成（提醒时刻或之后提交）"].exists)
        keepScreenshot(app, name: "普通完成来源与自主性明确分离")
    }

    private func formalKidTask(named name: String, in app: XCUIApplication) -> XCUIElement {
        let rows = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "kid.today.task.", name))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(rows.count, 1)
        return rows.element
    }

    private func openStatistics(in app: XCUIApplication) {
        let open = app.buttons["parent.statistics.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        XCTAssertTrue(open.isHittable)
        XCTAssertGreaterThanOrEqual(open.frame.height, 44)
        open.tap()
        XCTAssertTrue(app.collectionViews["parent.statistics.screen"].waitForExistence(timeout: 5))
    }

    private func selectStatisticsPeriod(_ days: Int, in app: XCUIApplication) {
        let button = app.buttons["parent.statistics.period.\(days)"]
        scrollFullyIntoStatisticsViewport(button, in: app, towardTop: true)
        XCTAssertGreaterThanOrEqual(button.frame.width, 44)
        XCTAssertGreaterThanOrEqual(button.frame.height, 44)
        button.tap()
        let window = app.staticTexts["parent.statistics.window"]
        scrollFullyIntoStatisticsViewport(window, in: app)
        let start = days == 7 ? "2026-09-21" : (days == 14 ? "2026-09-14" : "2026-08-29")
        XCTAssertEqual(window.label, "所属日期：\(start) 至 2026-09-27")
    }

    private func assertStatisticsCounts(
        prefix: String, completed: Int, eligible: Int, autonomous: Int,
        known: Int, waiting: Int, in app: XCUIApplication, screen: String = "parent.statistics.screen",
        towardTop: Bool = false
    ) {
        for (suffix, expected) in [
            ("completion.sample", "达成 \(completed) / 样本 \(eligible)"),
            ("autonomy.sample", "达成 \(autonomous) / 样本 \(known)"), ("waiting", "待验收：\(waiting)"),
        ] {
            let value = app.staticTexts[prefix + "." + suffix]
            scrollFullyIntoStatisticsViewport(value, in: app, screen: screen, towardTop: towardTop)
            XCTAssertEqual(value.label, expected)
        }
    }

    /// 只依赖原生frame/AX；趋势列表按需物化，找不到时先滚动，不把AX数量当业务总量。
    private func scrollFullyIntoStatisticsViewport(
        _ element: XCUIElement, in app: XCUIApplication,
        screen: String = "parent.statistics.screen", towardTop: Bool = false
    ) {
        // List在两系实际AX均为CollectionView；窄查询避免取背景及无关元素的异常legacy属性。
        let viewport = app.collectionViews[screen]
        XCTAssertTrue(viewport.waitForExistence(timeout: 5))
        var previousFrame: CGRect?
        var stationaryAttempts = 0
        for _ in 0..<80 {
            let viewportFrame = viewport.frame
            var visible = viewportFrame.intersection(app.frame)
            let title = screen == "parent.today.screen" ? "今日任务管理" : "成长统计"
            let bar = app.navigationBars[title]
            if bar.exists, bar.frame.intersects(visible) {
                let bottom = visible.maxY
                visible.origin.y = max(visible.minY, bar.frame.maxY)
                visible.size.height = max(0, bottom - visible.minY)
            }
            let targetFrame = element.exists ? element.frame : nil
            if let targetFrame, visible.contains(targetFrame), element.isHittable { return }
            if let targetFrame {
                stationaryAttempts = targetFrame == previousFrame ? stationaryAttempts + 1 : 0
                previousFrame = targetFrame
                // 到达边界且目标连续不移动时留证失败，不用反复属性读取触发XCT日志洪泛。
                if stationaryAttempts >= 3 { break }
            }
            // 没有有效可视区不生成无穷/NaN坐标；失败时保留原生层级，不跳过业务断言。
            guard visible.height > 0, viewportFrame.height > 0 else { break }
            let distance = targetFrame.map { ($0.midY - visible.midY) / visible.height } ?? (towardTop ? -1 : 1)
            let displacement =
                min(max(abs(distance), 0.12), 0.38) * visible.height / viewportFrame.height
                * (distance < 0 ? 1.0 : -1.0)
            let centerY = (visible.midY - viewportFrame.minY) / viewportFrame.height
            // 沿列表边缘滚动，避免从行内Menu/展开按钮开始长按而打开操作菜单。
            let start = viewport.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: centerY))
            let end = viewport.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: centerY + displacement))
            start.press(forDuration: 0.1, thenDragTo: end)
        }
        let target = element.exists ? element.identifier : "目标尚未物化"
        let diagnostic = XCTAttachment(string: "目标：\(target)\n\(app.debugDescription)")
        diagnostic.name = "统计原生滚动边界"
        diagnostic.lifetime = .keepAlways
        add(diagnostic)
        keepScreenshot(app, name: "统计完整可见失败")
        XCTFail("统计元素应完整滚动到实际可视区")
    }

    func testApprovalReceiptSurvivesRealProcessExitFailureAndAcknowledgementWithoutNewRewards() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = makeApplication()
        for scenario in ["parent-approval", "zero-reward-parent-approval"] {
            for phase in [
                "seed", "pending", "failed-acknowledgement", "pending", "acknowledge", "acknowledged", "acknowledged",
            ] {
                app.terminate()
                app.launchArguments = [
                    "--habito-ui-testing", "--habito-ui-task-scenario", scenario,
                    "--habito-ui-receipt-probe", phase,
                ]
                if phase == "seed" { app.launchArguments.append("--habito-ui-reset") }
                app.launch()
                // 正常首页出现意味着本进程启动探针已核对真实收据/审计/账本；不以日志或内存值冒充重启。
                XCTAssertTrue(app.staticTexts["完成 1 / 1"].waitForExistence(timeout: 10))
                assertTodayRewards(
                    xp: scenario == "parent-approval" ? 11 : 0,
                    coins: scenario == "parent-approval" ? 10 : 0, in: app)
                keepScreenshot(app, name: "跨进程收据-\(scenario)-\(phase)")
            }
        }
    }

    func testChildReceiptFailedContinuePreservesFeedbackAndCanRetryAcrossRelaunchWithSystemTextSize() throws {
        let app = submitSeededTaskForReview(extraArguments: ["--habito-ui-receipt-save-fail"])
        unlockParent(in: app)
        openParentReview(in: app)
        let approve = reviewAction("approve", in: app)
        scrollFullyIntoReviewViewport(approve, in: app)
        let autonomous = app.staticTexts["在提醒前主动提交"].exists
        approve.tap()
        XCTAssertTrue(app.staticTexts["已确认通过"].waitForExistence(timeout: 5))
        navigateBack(in: app, from: "待验收")
        app.buttons["parent.gate.close"].tap()
        assertChildReceipt(zero: false, autonomous: autonomous, in: app)
        continueChildReceipt(in: app)
        let failure = app.staticTexts["kid.today.receipt.error"]
        scrollFullyIntoTodayViewport(failure, in: app, towardTop: true)
        XCTAssertEqual(failure.label, "还没记住这次查看。收获不会少，再点一次继续。")
        XCTAssertTrue(app.staticTexts["kid.today.receipt.approved"].exists)
        assertTodayRewards(xp: 11, coins: autonomous ? 10 : 7, in: app)
        keepScreenshot(app, name: "收据确认失败保留真实到账")
        relaunchTodayKeepingData(app)
        assertChildReceipt(zero: false, autonomous: autonomous, in: app)
        continueChildReceipt(in: app)
        relaunchTodayKeepingData(app)
        XCTAssertFalse(app.staticTexts["kid.today.receipt.approved"].exists)
        assertTodayRewards(xp: 11, coins: autonomous ? 10 : 7, in: app)
    }

    func testCrossDayApprovedReceiptUsesOriginalSubmissionTimingAndAcknowledgesOnceWithSystemTextSize() throws {
        let app = submitSeededTaskForReview()
        unlockParent(in: app)
        openParentReview(in: app)
        let approve = reviewAction("approve", in: app)
        scrollFullyIntoReviewViewport(approve, in: app)
        let autonomous = app.staticTexts["在提醒前主动提交"].exists
        approve.tap()
        XCTAssertTrue(app.staticTexts["已确认通过"].waitForExistence(timeout: 5))
        app.terminate()
        let reference = try XCTUnwrap(Double(app.launchEnvironment["HABITO_UI_SYSTEM_REFERENCE"] ?? ""))
        app.launchEnvironment["HABITO_UI_SYSTEM_REFERENCE"] = String(reference - 2 * 86400)
        app.launchArguments = ["--habito-ui-testing"]
        app.launch()
        assertChildReceipt(zero: false, autonomous: autonomous, in: app)
        keepScreenshot(app, name: "两日后仍读取原审核收据")
        relaunchTodayKeepingData(app)
        assertChildReceipt(zero: false, autonomous: autonomous, in: app)
        continueChildReceipt(in: app)
        relaunchTodayKeepingData(app)
        XCTAssertFalse(app.staticTexts["kid.today.receipt.approved"].exists)
        assertTodayRewards(xp: 11, coins: autonomous ? 10 : 7, in: app)
    }

    /// 沿真实首页滚动逐一核对读屏金额；MAX 不以截图、裁剪边缘或过期 AX 代替点击验收。
    private func assertChildReceipt(zero: Bool, autonomous: Bool, in app: XCUIApplication) {
        let title = app.staticTexts["kid.today.receipt.approved"]
        scrollFullyIntoTodayViewport(title, in: app, towardTop: true)
        XCTAssertEqual(title.label, "家长确认啦！")
        let task = app.staticTexts["kid.today.receipt.task-title"]
        scrollFullyIntoTodayViewport(task, in: app)
        XCTAssertFalse(task.label.isEmpty)
        let celebration = app.staticTexts["kid.session.celebration-title"]
        scrollFullyIntoTodayViewport(celebration, in: app)
        XCTAssertEqual(celebration.label, "你做到了！")
        if autonomous {
            let badge = app.descendants(matching: .any)["kid.session.autonomy-celebration"]
            scrollFullyIntoTodayViewport(badge, in: app)
            XCTAssertEqual(badge.label, "你自己记得做啦！")
        } else {
            XCTAssertFalse(app.descendants(matching: .any)["kid.session.autonomy-celebration"].exists)
        }
        if zero {
            let effort = app.staticTexts["kid.session.completion-effort"]
            scrollFullyIntoTodayViewport(effort, in: app)
            XCTAssertEqual(effort.label, "这份努力已经记下啦。")
            XCTAssertFalse(app.descendants(matching: .any)["kid.session.reward-xp"].exists)
            XCTAssertFalse(app.descendants(matching: .any)["kid.session.reward-coins"].exists)
        } else {
            let xp = app.descendants(matching: .any)["kid.session.reward-xp"]
            let coins = app.descendants(matching: .any)["kid.session.reward-coins"]
            scrollFullyIntoTodayViewport(xp, in: app)
            XCTAssertEqual(xp.label, "+11 XP 已到账")
            scrollFullyIntoTodayViewport(coins, in: app)
            XCTAssertEqual(coins.label, autonomous ? "+10 金币已到账" : "+7 金币已到账")
        }
    }

    private func continueChildReceipt(in app: XCUIApplication) {
        let button = app.buttons["kid.session.dismiss-completion-feedback"]
        scrollFullyIntoTodayViewport(button, in: app)
        XCTAssertGreaterThanOrEqual(button.frame.width, 44)
        XCTAssertGreaterThanOrEqual(button.frame.height, 44)
        button.tap()
    }

    func testMultipleFormalApprovedReceiptsContinueIndividuallyWithoutDoubleRewardsWithSystemTextSize() throws {
        let titles = ["逐条成长收据", "逐条努力收据"]
        let app = launchEmptyParentEditor(title: titles[0])
        chooseEditorOption("家长验收", identifier: "parent.templates.editor.verification", in: app)
        setRewardText("11", identifier: "parent.templates.editor.xp", in: app)
        setRewardText("7", identifier: "parent.templates.editor.base-coins", in: app)
        setRewardText("3", identifier: "parent.templates.editor.autonomy-coins", in: app)
        tapEditorSave(in: app)
        app.buttons["parent.templates.create"].tap()
        let title = app.textFields["parent.templates.editor.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText(titles[1])
        chooseEditorOption("家长验收", identifier: "parent.templates.editor.verification", in: app)
        setRewardText("0", identifier: "parent.templates.editor.xp", in: app)
        setRewardText("0", identifier: "parent.templates.editor.base-coins", in: app)
        setRewardText("0", identifier: "parent.templates.editor.autonomy-coins", in: app)
        tapEditorSave(in: app)
        app.buttons["parent.gate.close"].tap()
        for name in titles {
            let task = todayTask(named: name, in: app)
            scrollFullyIntoTodayViewport(task, in: app)
            task.tap()
            let submit = app.buttons["kid.session.submit"]
            scrollFullyIntoSessionViewport(submit, in: app)
            submit.tap()
            assertWaitingWithoutOldActions(in: app)
            returnToTodayFromTask(in: app)
        }
        XCTAssertFalse(app.staticTexts["kid.today.receipt.approved"].exists)
        unlockExistingParent(in: app)
        openParentReview(in: app)
        var approvedRequestIDs: Set<String> = []
        // 大字懒加载仅公开已物化节点；核对两个不同稳定请求和最终空队列，不把AX数量当业务总数。
        for _ in 0..<2 {
            let actions = reviewActions("approve", in: app)
            let requestID = actions.element(boundBy: 0).identifier
            let approve = app.buttons[requestID]
            scrollFullyIntoReviewViewport(approve, in: app)
            XCTAssertTrue(approvedRequestIDs.insert(requestID).inserted, "每次必须审核不同的真实提交")
            approve.tap()
            let dismiss = app.buttons["parent.review.dismiss-feedback"]
            scrollFullyIntoReviewViewport(dismiss, in: app, towardTop: true)
            dismiss.tap()
            XCTAssertFalse(app.buttons[requestID].exists)
        }
        XCTAssertEqual(approvedRequestIDs.count, 2)
        XCTAssertTrue(app.staticTexts["没有待验收任务"].waitForExistence(timeout: 5))
        navigateBack(in: app, from: "待验收")
        app.buttons["parent.gate.close"].tap()
        var readTitles: Set<String> = []
        for _ in 0..<2 {
            let name = app.staticTexts["kid.today.receipt.task-title"]
            scrollFullyIntoTodayViewport(name, in: app, towardTop: true)
            XCTAssertTrue(readTitles.insert(name.label).inserted, "每次继续应是不同的真实收据")
            assertChildReceipt(zero: name.label == titles[1], autonomous: true, in: app)
            continueChildReceipt(in: app)
        }
        XCTAssertEqual(readTitles, Set(titles))
        relaunchTodayKeepingData(app)
        XCTAssertFalse(app.staticTexts["kid.today.receipt.approved"].exists)
        assertTodayRewards(xp: 11, coins: 10, in: app)
        keepScreenshot(app, name: "两条正式收据确认后重启不补奖")
    }

    func testFormalTimePeriodGroupsKeepRecommendationUniqueAndTasksReachableWithSystemTextSize() throws {
        let app = launchEmptyParentEditor(title: "分组推荐锚点")
        tapEditorSave(in: app)
        app.buttons["parent.gate.close"].tap()
        let anchor = todayTask(named: "分组推荐锚点", in: app)
        scrollFullyIntoTodayViewport(anchor, in: app)
        anchor.tap()
        app.buttons["kid.session.start"].tap()
        let pause = app.buttons["kid.session.pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        pause.tap()
        returnToTodayFromTask(in: app)
        unlockExistingParent(in: app)
        // 先用真实暂停会话固定推荐，避免相同提醒时刻的随机 UUID 决定哪一组少一项。
        let periods = [("早晨", "morning"), ("放学后", "afterSchool"), ("晚上", "evening"), ("全天", "allDay")]
        for (title, _) in periods {
            let create = app.buttons["parent.templates.create"]
            XCTAssertTrue(create.waitForExistence(timeout: 5))
            create.tap()
            let input = app.textFields["parent.templates.editor.title"]
            XCTAssertTrue(input.waitForExistence(timeout: 5))
            input.tap()
            input.typeText("分组\(title)")
            chooseEditorOption(title, identifier: "parent.templates.editor.time-period", in: app)
            if title == "放学后" {
                chooseEditorOption("家长验收", identifier: "parent.templates.editor.verification", in: app)
            }
            tapEditorSave(in: app)
            XCTAssertTrue(parentTemplate(named: "分组\(title)", in: app).waitForExistence(timeout: 5))
        }
        app.buttons["parent.gate.close"].tap()
        scrollFullyIntoTodayViewport(anchor, in: app, towardTop: true)
        XCTAssertEqual(
            app.buttons.matching(
                NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "kid.today.task.", "分组推荐锚点")
            ).count, 1)
        let anchorID = anchor.identifier
        var taskIDs: [String] = []
        for (title, suffix) in periods {
            let header = app.staticTexts["kid.today.group.\(suffix)"]
            scrollFullyIntoTodayViewport(header, in: app)
            XCTAssertEqual(header.label, title)
            let task = todayTask(named: "分组\(title)", in: app)
            scrollFullyIntoTodayViewport(task, in: app)
            XCTAssertGreaterThanOrEqual(task.frame.width, 44)
            XCTAssertGreaterThanOrEqual(task.frame.height, 44)
            taskIDs.append(task.identifier)
        }
        XCTAssertEqual(Set(taskIDs).count, 4)
        XCTAssertFalse(taskIDs.contains(anchorID))
        keepScreenshot(app, name: "正式四时段分组与独立推荐")

        let morning = todayTask(named: "分组早晨", in: app)
        scrollFullyIntoTodayViewport(morning, in: app, towardTop: true)
        morning.tap()
        let complete = app.buttons["kid.session.complete"]
        scrollFullyIntoSessionViewport(complete, in: app)
        complete.tap()
        XCTAssertTrue(app.staticTexts["你做到了！"].waitForExistence(timeout: 5))
        returnToTodayFromTask(in: app)
        let afterSchool = todayTask(named: "分组放学后", in: app)
        scrollFullyIntoTodayViewport(afterSchool, in: app)
        afterSchool.tap()
        let submit = app.buttons["kid.session.submit"]
        scrollFullyIntoSessionViewport(submit, in: app)
        submit.tap()
        assertWaitingWithoutOldActions(in: app)
        returnToTodayFromTask(in: app)
        relaunchTodayKeepingData(app)
        assertTodayRewards(xp: 0, coins: 0, in: app)
        XCTAssertTrue(app.staticTexts["完成 1 / 5"].waitForExistence(timeout: 5))
        for (index, (title, suffix)) in periods.enumerated() {
            let header = app.staticTexts["kid.today.group.\(suffix)"]
            scrollFullyIntoTodayViewport(header, in: app)
            XCTAssertEqual(header.label, title)
            let task = todayTask(named: "分组\(title)", in: app)
            scrollFullyIntoTodayViewport(task, in: app)
            XCTAssertEqual(task.identifier, taskIDs[index])
            if title == "早晨" { XCTAssertTrue(task.label.contains("已完成")) }
            if title == "放学后" { XCTAssertTrue(task.label.contains("等家长确认")) }
        }
        scrollFullyIntoTodayViewport(anchor, in: app, towardTop: true)
        XCTAssertEqual(anchor.identifier, anchorID)
    }

    private func todayTask(named title: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "kid.today.task.", title)
        ).element
    }

    func testCrossDayPausedTaskRemainsRecommendedOutsideTodayPeriodGroupsWithSystemTextSize() throws {
        try verifyCarryOverRecovery(days: 1)
    }

    func testTwoDayPausedTaskKeepsIdentityAndTodayDenominatorWithSystemTextSize() throws {
        try verifyCarryOverRecovery(days: 2)
    }

    /// 映射业务时钟跨过指定天数，恢复原实例；不修改系统时间或等待真实午夜。
    private func verifyCarryOverRecovery(days: Int) throws {
        let app = launchScenario("legacy")
        openSeededTask(in: app)
        app.buttons["kid.session.start"].tap()
        let pause = app.buttons["kid.session.pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        pause.tap()
        returnToTodayFromTask(in: app)
        let reference = try XCTUnwrap(Double(app.launchEnvironment["HABITO_UI_SYSTEM_REFERENCE"] ?? ""))
        app.terminate()
        app.launchArguments = ["--habito-ui-testing"]
        app.launchEnvironment["HABITO_UI_SYSTEM_REFERENCE"] = String(reference - Double(days) * 86400)
        app.launch()
        let carryOver = app.buttons[seededTaskIdentifier]
        scrollFullyIntoTodayViewport(carryOver, in: app)
        XCTAssertTrue(carryOver.label.contains("之前的任务还在做"))
        XCTAssertEqual(app.buttons.matching(identifier: seededTaskIdentifier).count, 1)
        let allDay = app.staticTexts["kid.today.group.allDay"]
        scrollFullyIntoTodayViewport(allDay, in: app)
        XCTAssertEqual(allDay.label, "全天")
        let today = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ AND identifier != %@", "kid.today.task.", seededTaskIdentifier)
        ).element
        scrollFullyIntoTodayViewport(today, in: app)
        XCTAssertFalse(today.label.contains("之前的任务还在做"))
        let todayID = today.identifier
        keepScreenshot(app, name: "跨日推荐与今日全天分组分开")
        scrollFullyIntoTodayViewport(carryOver, in: app, towardTop: true)
        carryOver.tap()
        XCTAssertTrue(app.buttons["kid.session.resume"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["之前的任务还在做"].exists)
        returnToTodayFromTask(in: app)
        relaunchTodayKeepingData(app)
        scrollFullyIntoTodayViewport(app.buttons[seededTaskIdentifier], in: app)
        XCTAssertTrue(app.buttons[seededTaskIdentifier].label.contains("之前的任务还在做"))
        scrollFullyIntoTodayViewport(app.buttons[todayID], in: app)
        assertTodayRewards(xp: 0, coins: 0, in: app)
    }

    func testTodayRewardsPersistAfterCompletionAndRelaunchWithSystemTextSize() throws {
        let app = launchScenario("reward-after-reminder")
        assertTodayRewards(xp: 0, coins: 0, in: app)
        openSeededTask(in: app)
        let complete = app.buttons["kid.session.complete"]
        scrollFullyIntoSessionViewport(complete, in: app)
        complete.tap()
        XCTAssertTrue(app.staticTexts["你做到了！"].waitForExistence(timeout: 5))
        returnToTodayFromTask(in: app)
        assertTodayRewards(xp: 11, coins: 7, in: app)
        let completed = app.staticTexts["今天的任务都完成了。"]
        scrollFullyIntoTodayViewport(completed, in: app)
        assertDailyCompletion(count: 1, in: app)
        keepScreenshot(app, name: "全部完成仍可查看真实资产")
        // 关闭家长入口触发现有首页刷新；只读结果不变，不能把刷新当再次发奖。
        let parentEntry = app.buttons["parent.gate.entry"]
        parentEntry.tap()
        let parentClose = app.buttons["parent.gate.close"]
        XCTAssertTrue(parentClose.waitForExistence(timeout: 5))
        parentClose.tap()
        assertDailyCompletion(count: 1, in: app)
        assertTodayRewards(xp: 11, coins: 7, in: app)
        relaunchWithOldSeededNotification(app)
        assertTodayRewards(xp: 11, coins: 7, in: app)
        assertDailyCompletion(count: 1, in: app)
        XCTAssertFalse(app.descendants(matching: .any)["kid.session.completion-feedback"].exists)
    }

    func testZeroRewardDailyCompletionRemainsReadableWithoutInventingRewardsWithSystemTextSize() throws {
        let app = launchScenario("zero-reward-self-confirm")
        openSeededTask(in: app)
        let complete = app.buttons["kid.session.complete"]
        scrollFullyIntoSessionViewport(complete, in: app)
        complete.tap()
        XCTAssertTrue(app.staticTexts["这份努力已经记下啦。"].waitForExistence(timeout: 5))
        returnToTodayFromTask(in: app)
        assertTodayRewards(xp: 0, coins: 0, in: app)
        assertDailyCompletion(count: 1, in: app)
        keepScreenshot(app, name: "零奖励当天完成印章与真实零资产")
        relaunchTodayKeepingData(app)
        assertDailyCompletion(count: 1, in: app)
        assertTodayRewards(xp: 0, coins: 0, in: app)
        XCTAssertFalse(app.staticTexts["kid.session.reward-xp"].exists)
        XCTAssertFalse(app.staticTexts["kid.session.reward-coins"].exists)
    }

    /// 只读完成结果必须实际读得见，不以AX存在或截断露出代替完整可见性。
    private func assertDailyCompletion(count: Int, in app: XCUIApplication) {
        let stamp = app.staticTexts["kid.today.completion.stamp"]
        let total = app.staticTexts["kid.today.completion.count"]
        let rest = app.staticTexts["kid.today.completion.rest"]
        for element in [stamp, total, rest] {
            scrollFullyIntoTodayViewport(element, in: app)
        }
        XCTAssertEqual(stamp.label, "今日通关")
        XCTAssertEqual(total.label, "完成了 \(count) 项今日任务")
        XCTAssertEqual(rest.label, "今天的努力，已经记下啦。接下来，安心休息吧！")
    }

    func testTodayRewardsReflectImmediateUndoWithoutCreatingAnotherReward() throws {
        let app = launchScenario("reward-after-reminder")
        openSeededTask(in: app)
        // MAX下完成按钮可能在首屏以下；XCTest自动滚动不可靠，先证明完整可见再点击。
        let complete = app.buttons["kid.session.complete"]
        scrollFullyIntoSessionViewport(complete, in: app)
        complete.tap()
        let undo = app.buttons["kid.session.undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 2))
        // 固定安全区不属于ScrollView；无需滚动，直接检查完整窗口与44pt后在原五秒内点击。
        let undoFrame = undo.frame
        XCTAssertTrue(undo.isHittable)
        XCTAssertTrue(app.frame.contains(undoFrame))
        XCTAssertGreaterThanOrEqual(undoFrame.width, 44)
        XCTAssertGreaterThanOrEqual(undoFrame.height, 44)
        undo.tap()
        XCTAssertTrue(app.buttons["kid.session.complete"].waitForExistence(timeout: 5))
        returnToTodayFromTask(in: app)
        assertTodayRewards(xp: 0, coins: 0, in: app)
        XCTAssertFalse(app.staticTexts["kid.today.completion.stamp"].exists)
        relaunchTodayKeepingData(app)
        assertTodayRewards(xp: 0, coins: 0, in: app)
        scrollFullyIntoTodayViewport(app.buttons[seededTaskIdentifier], in: app)
    }

    func testEmptyTodayKeepsZeroAssetsVisibleWithSystemTextSize() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = makeApplication()
        app.launchArguments = ["--habito-ui-testing", "--habito-ui-reset", "--habito-ui-empty"]
        app.launch()
        assertTodayRewards(xp: 0, coins: 0, in: app)
        scrollFullyIntoTodayViewport(app.staticTexts["今天没有任务啊"], in: app)
        XCTAssertFalse(app.staticTexts["kid.today.completion.stamp"].exists)
        keepScreenshot(app, name: "空态真实零资产")
        relaunchTodayKeepingData(app)
        assertTodayRewards(xp: 0, coins: 0, in: app)
    }

    func testTodayRewardFailureKeepsTasksAndRetryReachableWithSystemTextSize() throws {
        let app = launchScenario("corrupt-reward-ledger")
        let error = app.descendants(matching: .any)["kid.today.rewards.error"]
        let retry = app.buttons["kid.today.rewards.retry"]
        for _ in 0..<2 {
            scrollFullyIntoTodayViewport(error, in: app)
            XCTAssertEqual(error.label, "收获暂时没读到")
            XCTAssertFalse(app.descendants(matching: .any)["kid.today.xp"].exists)
            XCTAssertFalse(app.descendants(matching: .any)["kid.today.coins"].exists)
            scrollFullyIntoTodayViewport(retry, in: app)
            XCTAssertTrue(retry.isEnabled && retry.isHittable)
            XCTAssertGreaterThanOrEqual(retry.frame.width, 44)
            XCTAssertGreaterThanOrEqual(retry.frame.height, 44)
            retry.tap()
        }
        keepScreenshot(app, name: "资产错误不伪造零余额")
        openSeededTask(in: app)
        XCTAssertTrue(app.buttons["kid.session.start"].isHittable)
        returnToTodayFromTask(in: app)
        relaunchTodayKeepingData(app)
        scrollFullyIntoTodayViewport(error, in: app)
        XCTAssertFalse(app.descendants(matching: .any)["kid.today.xp"].exists)
    }

    /// 精确金额和完整可见性同时验证；存在或边缘命中都不能当成读得见。
    private func assertTodayRewards(xp: Int, coins: Int, in app: XCUIApplication) {
        let xpValue = app.descendants(matching: .any)["kid.today.xp"]
        let coinValue = app.descendants(matching: .any)["kid.today.coins"]
        scrollFullyIntoTodayViewport(xpValue, in: app)
        XCTAssertEqual(xpValue.label, "成长 XP：\(xp)")
        scrollFullyIntoTodayViewport(coinValue, in: app)
        XCTAssertEqual(coinValue.label, "金币：\(coins)")
        XCTAssertFalse(app.descendants(matching: .any)["kid.today.rewards.error"].exists)
    }

    private func scrollFullyIntoTodayViewport(_ element: XCUIElement, in app: XCUIApplication, towardTop: Bool = false)
    {
        let viewport = app.scrollViews.element(boundBy: 0)
        XCTAssertTrue(viewport.waitForExistence(timeout: 5))
        let navigationBar = app.navigationBars["今日"]
        XCTAssertTrue(navigationBar.waitForExistence(timeout: 5))
        for _ in 0..<25 {
            var visibleFrame = viewport.frame.intersection(app.frame)
            // 今日根页不是家长表单；只扣自己的导航栏，不能套用编辑器的标题/键盘规则。
            let barFrame = navigationBar.frame
            if barFrame.intersects(visibleFrame) {
                let bottom = visibleFrame.maxY
                visibleFrame.origin.y = max(visibleFrame.minY, barFrame.maxY)
                visibleFrame.size.height = max(0, bottom - visibleFrame.minY)
            }
            guard visibleFrame.height > 0 else {
                XCTFail("今日页应保留可操作区域")
                return
            }
            if element.exists, element.isHittable, visibleFrame.contains(element.frame) { return }
            let distance =
                element.exists ? (element.frame.midY - visibleFrame.midY) / visibleFrame.height : (towardTop ? -1 : 1)
            // 大字推荐卡会被整屏 swipe 来回越过；按公开 frame 对齐，保持完整可见与可操作标准。
            let displacement =
                min(max(abs(distance), 0.08), 0.30) * visibleFrame.height / viewport.frame.height
                * (distance < 0 ? 1.0 : -1.0)
            let centerY = (visibleFrame.midY - viewport.frame.minY) / viewport.frame.height
            let start = viewport.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: centerY))
            let end = viewport.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: centerY + displacement))
            start.press(forDuration: 0.1, thenDragTo: end)
        }
        keepScreenshot(app, name: "今日页完整可见性失败")
        let diagnostic = XCTAttachment(string: app.debugDescription)
        diagnostic.name = "今日页原生控件诊断"
        diagnostic.lifetime = .keepAlways
        add(diagnostic)
        XCTFail("今日控件应完整露出且可操作")
    }

    private func relaunchTodayKeepingData(_ app: XCUIApplication) {
        let isEmptyFixture = app.launchArguments.contains("--habito-ui-empty")
        app.terminate()
        // 正式空库场景只保留数据、不启用默认样例播种；其他旧场景的启动语义不变。
        app.launchArguments = isEmptyFixture ? ["--habito-ui-testing", "--habito-ui-empty"] : ["--habito-ui-testing"]
        app.launch()
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

    func testFormalThreeTimesRemainDistinctAndPastDeadlineStillRewardsAutonomyWithSystemTextSize() throws {
        verifyFormalChildTimes(approval: false)
    }

    func testFormalPastDeadlineWaitingKeepsTimesWithoutPressureOrRewardsWithSystemTextSize() throws {
        verifyFormalChildTimes(approval: true)
    }

    /// 两种正式验收方式共用三时间回读；待审核只肯定提交，不把截止提示或收入带入等待态。
    private func verifyFormalChildTimes(approval: Bool) {
        let name = approval ? "截止后等待确认" : "三个独立时间"
        let app = launchEmptyParentEditor(title: name)
        XCTAssertEqual(editorReminderValue(in: app), "19点:30分钟")
        changeTimeToggle("planned", enabled: true, in: app)
        setOptionalTime("planned", hour: "08", minute: "15", in: app)
        changeTimeToggle("deadline", enabled: true, in: app)
        setOptionalTime("deadline", hour: "09", minute: "20", in: app)
        if approval {
            chooseEditorOption("家长验收", identifier: "parent.templates.editor.verification", in: app)
        }
        setRewardText("11", identifier: "parent.templates.editor.xp", in: app)
        setRewardText("7", identifier: "parent.templates.editor.base-coins", in: app)
        setRewardText("3", identifier: "parent.templates.editor.autonomy-coins", in: app)
        tapEditorSave(in: app)
        XCTAssertTrue(parentTemplate(named: name, in: app).waitForExistence(timeout: 5))
        app.buttons["parent.gate.close"].tap()
        let card = todayTask(named: name, in: app)
        scrollFullyIntoTodayViewport(card, in: app)
        XCTAssertGreaterThanOrEqual(card.frame.height, 44)
        XCTAssertGreaterThanOrEqual(card.frame.width, 44)
        for text in ["提醒时间 19:30", "计划时间 08:15", "截止时间 09:20", "过了截止时间，仍可完成"] {
            XCTAssertTrue(card.label.contains(text), "推荐卡应完整读出：\(text)")
        }
        let id = String(card.identifier.dropFirst("kid.today.task.".count))
        // 先重启回读未完成任务，再实际完成；不能以旧页面缓存证明保存成功。
        relaunchTodayKeepingData(app)
        let restored = todayTask(named: name, in: app)
        scrollFullyIntoTodayViewport(restored, in: app)
        XCTAssertEqual(restored.identifier, "kid.today.task." + id)
        XCTAssertTrue(restored.label.contains("截止时间 09:20"))
        restored.tap()
        XCTAssertFalse(app.staticTexts["计划时间"].exists, "计时区不能把提醒时刻重复标作计划时间")
        assertSessionTime("reminder", id: id, text: "提醒时间 19:30", in: app)
        assertSessionTime("planned", id: id, text: "计划时间 08:15", in: app)
        assertSessionTime("deadline", id: id, text: "截止时间 09:20", in: app)
        assertSessionTime("hint", id: id, text: "过了截止时间，仍可完成", in: app)
        keepScreenshot(app, name: "三个独立时间截止已过仍可完成")
        let complete = app.buttons[approval ? "kid.session.submit" : "kid.session.complete"]
        scrollFullyIntoSessionViewport(complete, in: app)
        XCTAssertGreaterThanOrEqual(complete.frame.height, 44)
        complete.tap()
        if approval {
            assertWaitingWithoutOldActions(in: app)
            XCTAssertFalse(app.descendants(matching: .any)["kid.timing.hint." + id].exists)
            assertSessionTime("deadline", id: id, text: "截止时间 09:20", in: app)
            returnToTodayFromTask(in: app)
            assertTodayRewards(xp: 0, coins: 0, in: app)
            relaunchTodayKeepingData(app)
            let waiting = todayTask(named: name, in: app)
            scrollFullyIntoTodayViewport(waiting, in: app)
            XCTAssertEqual(waiting.identifier, "kid.today.task." + id)
            XCTAssertTrue(waiting.label.contains("等家长确认") && waiting.label.contains("截止时间 09:20"))
            XCTAssertFalse(waiting.label.contains("过了截止时间"))
            keepScreenshot(app, name: "等待任务三时间完整纵向展示")
            waiting.tap()
            assertWaitingWithoutOldActions(in: app)
            XCTAssertFalse(app.descendants(matching: .any)["kid.timing.hint." + id].exists)
            returnToTodayFromTask(in: app)
            assertTodayRewards(xp: 0, coins: 0, in: app)
            return
        }
        XCTAssertTrue(app.staticTexts["你做到了！"].waitForExistence(timeout: 5))
        let coins = app.staticTexts["kid.session.reward-coins"]
        scrollFullyIntoSessionViewport(coins, in: app)
        XCTAssertEqual(coins.label, "+10 金币已到账")
        XCTAssertTrue(app.descendants(matching: .any)["kid.session.autonomy-celebration"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["kid.timing.hint." + id].exists)
        returnToTodayFromTask(in: app)
        assertTodayRewards(xp: 11, coins: 10, in: app)
        relaunchTodayKeepingData(app)
        assertTodayRewards(xp: 11, coins: 10, in: app)
        scrollFullyIntoTodayViewport(app.staticTexts["今天的任务都完成了。"], in: app)
        XCTAssertFalse(app.descendants(matching: .any)["kid.session.completion-feedback"].exists)
    }

    private func assertSessionTime(_ field: String, id: String, text: String, in app: XCUIApplication) {
        let element = app.descendants(matching: .any)["kid.timing.\(field)." + id]
        scrollFullyIntoSessionViewport(element, in: app)
        XCTAssertEqual(element.label, text)
    }

    func testFormalOptionalTimesSetEditClearAndRelaunchWithSystemTextSize() throws {
        let name = "正式可空时间"
        let app = launchEmptyParentEditor(title: name)
        let originalReminder = editorReminderValue(in: app)
        assertTimeToggle("planned", enabled: false, in: app)
        assertTimeToggle("deadline", enabled: false, in: app)
        changeTimeToggle("planned", enabled: true, in: app)
        setOptionalTime("planned", hour: "08", minute: "15", in: app)
        changeTimeToggle("deadline", enabled: true, in: app)
        setOptionalTime("deadline", hour: "21", minute: "45", in: app)
        tapEditorSave(in: app)
        let template = parentTemplate(named: name, in: app)
        XCTAssertTrue(template.waitForExistence(timeout: 5))
        template.tap()
        assertOptionalTime("planned", hour: "08", minute: "15", in: app)
        assertOptionalTime("deadline", hour: "21", minute: "45", in: app)
        setOptionalTime("planned", hour: "09", minute: "20", in: app, towardTop: true)
        assertOptionalTime("deadline", hour: "21", minute: "45", in: app)
        tapEditorSave(in: app)
        XCTAssertTrue(template.waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = ["--habito-ui-testing", "--habito-ui-empty"]
        app.launch()
        unlockExistingParent(in: app)
        parentTemplate(named: name, in: app).tap()
        XCTAssertEqual(editorReminderValue(in: app), originalReminder, "独立计划/截止不能改提醒")
        assertOptionalTime("planned", hour: "09", minute: "20", in: app)
        assertOptionalTime("deadline", hour: "21", minute: "45", in: app)
        keepScreenshot(app, name: "正式可空时间重启回读")
        changeTimeToggle("planned", enabled: false, in: app, towardTop: true)
        tapEditorSave(in: app)
        XCTAssertTrue(template.waitForExistence(timeout: 5))
        template.tap()
        assertTimeToggle("planned", enabled: false, in: app)
        assertOptionalTime("deadline", hour: "21", minute: "45", in: app)
        changeTimeToggle("deadline", enabled: false, in: app)
        tapEditorSave(in: app)
        XCTAssertTrue(template.waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        unlockExistingParent(in: app)
        parentTemplate(named: name, in: app).tap()
        XCTAssertEqual(editorReminderValue(in: app), originalReminder, "清空可选时间仍保留原提醒")
        assertTimeToggle("planned", enabled: false, in: app)
        assertTimeToggle("deadline", enabled: false, in: app)
        tapEditorSave(in: app)
        app.buttons["parent.gate.close"].tap()
        XCTAssertEqual(
            app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "kid.today.task.")).count, 1)
    }

    func testLegacyOptionalTimesRemainUnsetAfterTitleEditAndRelaunchWithSystemTextSize() throws {
        let app = launchScenario("legacy")
        let card = app.buttons[seededTaskIdentifier]
        scrollFullyIntoTodayViewport(card, in: app)
        XCTAssertTrue(card.label.contains("提醒时间 19:30"))
        XCTAssertFalse(card.label.contains("计划时间") || card.label.contains("截止时间"))
        card.tap()
        XCTAssertFalse(app.staticTexts["计划时间"].exists, "旧 nil 不能在计时区伪造计划标签")
        XCTAssertFalse(
            app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "kid.timing.planned.")
            ).element.exists)
        XCTAssertFalse(
            app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "kid.timing.deadline.")
            ).element.exists)
        returnToTodayFromTask(in: app)
        unlockParent(in: app)
        app.buttons[seededTemplateIdentifier].tap()
        assertTimeToggle("planned", enabled: false, in: app)
        assertTimeToggle("deadline", enabled: false, in: app)
        let title = app.textFields["parent.templates.editor.title"]
        scrollFullyIntoEditorViewport(title, in: app, towardTop: true)
        title.tap()
        title.typeText("仍未设置时间")
        tapEditorSave(in: app)
        XCTAssertTrue(app.buttons[seededTemplateIdentifier].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = ["--habito-ui-testing"]
        app.launch()
        unlockExistingParent(in: app)
        app.buttons[seededTemplateIdentifier].tap()
        assertTimeToggle("planned", enabled: false, in: app)
        assertTimeToggle("deadline", enabled: false, in: app)
        keepScreenshot(app, name: "旧任务没有自动补时间")
    }

    private func assertTimeToggle(_ field: String, enabled: Bool, in app: XCUIApplication) {
        let toggle = app.buttons["parent.templates.editor.\(field)-enabled"]
        scrollFullyIntoEditorViewport(toggle, in: app)
        XCTAssertGreaterThanOrEqual(toggle.frame.height, 44)
        XCTAssertGreaterThanOrEqual(toggle.frame.width, 44)
        XCTAssertEqual(toggle.label, field == "planned" ? "设置计划时间" : "设置截止时间")
        XCTAssertEqual(toggle.value as? String, enabled ? "已选择" : "未选择")
        if !enabled {
            XCTAssertFalse(app.datePickers["parent.templates.editor.\(field)-time"].exists)
        }
    }

    private func changeTimeToggle(
        _ field: String, enabled: Bool, in app: XCUIApplication, towardTop: Bool = false
    ) {
        let toggle = app.buttons["parent.templates.editor.\(field)-enabled"]
        scrollFullyIntoEditorViewport(toggle, in: app, towardTop: towardTop)
        XCTAssertGreaterThanOrEqual(toggle.frame.height, 44)
        XCTAssertGreaterThanOrEqual(toggle.frame.width, 44)
        XCTAssertEqual(toggle.value as? String, enabled ? "未选择" : "已选择", "应实际改变状态，而不是把现有状态当操作成功")
        // 原生 Button 的完整区域可点击；启用事实由明确的读屏值和真实时间控件回读证明。
        toggle.tap()
        let changed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", enabled ? "已选择" : "未选择"), object: toggle)
        let result = XCTWaiter.wait(for: [changed], timeout: 5)
        if result != .completed {
            let diagnostic = XCTAttachment(string: app.debugDescription)
            diagnostic.name = "时间开关原生层级与实际状态"
            diagnostic.lifetime = .keepAlways
            add(diagnostic)
            keepScreenshot(app, name: "时间开关点击失败")
        }
        XCTAssertEqual(result, .completed)
    }

    private func setOptionalTime(
        _ field: String, hour: String, minute: String, in app: XCUIApplication, towardTop: Bool = false
    ) {
        let picker = app.datePickers["parent.templates.editor.\(field)-time"]
        scrollFullyIntoEditorViewport(picker, in: app, towardTop: towardTop)
        let wheels = picker.pickerWheels
        XCTAssertEqual(wheels.count, 2, "中文 24 小时原生控件应仅有时/分两列")
        wheels.element(boundBy: 0).adjust(toPickerWheelValue: hour)
        wheels.element(boundBy: 1).adjust(toPickerWheelValue: minute)
        assertOptionalTime(field, hour: hour, minute: minute, in: app)
    }

    private func assertOptionalTime(_ field: String, hour: String, minute: String, in app: XCUIApplication) {
        let picker = app.datePickers["parent.templates.editor.\(field)-time"]
        scrollFullyIntoEditorViewport(picker, in: app)
        XCTAssertGreaterThanOrEqual(picker.frame.height, 44)
        XCTAssertGreaterThanOrEqual(picker.frame.width, 44)
        XCTAssertEqual(picker.pickerWheels.count, 2)
        XCTAssertEqual(picker.label, field == "planned" ? "计划时间" : "截止时间")
        // 原生中文 AX 回读带单位，选择 API 却接收不带单位的两位数字；精确核对而非模糊包含。
        XCTAssertEqual(picker.pickerWheels.element(boundBy: 0).value as? String, hour + "点")
        XCTAssertEqual(picker.pickerWheels.element(boundBy: 1).value as? String, minute + "分钟")
    }

    private func editorReminderValue(in app: XCUIApplication) -> String {
        let reminder = app.datePickers["parent.templates.editor.reminder-time"]
        scrollFullyIntoEditorViewport(reminder, in: app, towardTop: true)
        XCTAssertGreaterThanOrEqual(reminder.frame.height, 44)
        XCTAssertGreaterThanOrEqual(reminder.frame.width, 44)
        XCTAssertEqual(reminder.pickerWheels.count, 2)
        XCTAssertEqual(reminder.label, "提醒时间")
        let hour = reminder.pickerWheels.element(boundBy: 0).value as? String
        let minute = reminder.pickerWheels.element(boundBy: 1).value as? String
        XCTAssertEqual(hour, "19点")
        XCTAssertEqual(minute, "30分钟")
        return (hour ?? "") + ":" + (minute ?? "")
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
        assertChildReceipt(zero: zeroReward, autonomous: true, in: app)
        XCTAssertEqual(app.staticTexts["kid.today.receipt.task-title"].label, name)
        keepScreenshot(app, name: zeroReward ? "正式零奖励儿童收据" : "正式自主儿童收据")
        relaunchTodayKeepingData(app)
        assertChildReceipt(zero: zeroReward, autonomous: true, in: app)
        continueChildReceipt(in: app)
        relaunchTodayKeepingData(app)
        XCTAssertFalse(app.staticTexts["kid.today.receipt.approved"].exists)
        assertTodayRewards(xp: zeroReward ? 0 : 11, coins: zeroReward ? 0 : 10, in: app)
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

    func testCompletionCelebrationRewardsAndContinueRemainReachableWithSystemTextSize() throws {
        verifyCompletionCelebration(scenario: "reward-self-confirm", autonomous: true, zeroReward: false)
    }

    func testReminderTimeCompletionGetsOrdinaryReceiptWithoutAutonomyBadge() throws {
        verifyCompletionCelebration(scenario: "reward-after-reminder", autonomous: false, zeroReward: false)
    }

    func testZeroRewardAutonomyStillCelebratesEffortWithSystemTextSize() throws {
        verifyCompletionCelebration(scenario: "zero-reward-self-confirm", autonomous: true, zeroReward: true)
    }

    /// 字号使用真实系统 content_size；展示分层和金额都由真实完成事务产生。
    private func verifyCompletionCelebration(scenario: String, autonomous: Bool, zeroReward: Bool) {
        let app = launchScenario(scenario)
        openSeededTask(in: app)
        let complete = app.buttons["kid.session.complete"]
        scrollFullyIntoSessionViewport(complete, in: app)
        complete.tap()
        let title = app.staticTexts["kid.session.celebration-title"]
        scrollFullyIntoSessionViewport(title, in: app)
        XCTAssertEqual(title.label, "你做到了！")
        let autonomy = app.descendants(matching: .any)["kid.session.autonomy-celebration"]
        XCTAssertEqual(autonomy.exists, autonomous)
        if autonomous {
            scrollFullyIntoSessionViewport(autonomy, in: app)
            XCTAssertTrue(autonomy.label.contains("你自己记得做啦！"))
        }
        let xp = app.descendants(matching: .any)["kid.session.reward-xp"]
        let coins = app.descendants(matching: .any)["kid.session.reward-coins"]
        if zeroReward {
            XCTAssertFalse(xp.exists)
            XCTAssertFalse(coins.exists)
            let effort = app.staticTexts["kid.session.completion-effort"]
            scrollFullyIntoSessionViewport(effort, in: app)
            XCTAssertEqual(effort.label, "这份努力已经记下啦。")
        } else {
            scrollFullyIntoSessionViewport(xp, in: app)
            XCTAssertEqual(xp.label, "+11 XP 已到账")
            scrollFullyIntoSessionViewport(coins, in: app)
            XCTAssertEqual(coins.label, autonomous ? "+10 金币已到账" : "+7 金币已到账")
        }
        let dismiss = app.buttons["kid.session.dismiss-completion-feedback"]
        scrollFullyIntoSessionViewport(dismiss, in: app)
        XCTAssertTrue(dismiss.isEnabled && dismiss.isHittable)
        XCTAssertGreaterThanOrEqual(dismiss.frame.width, 44)
        XCTAssertGreaterThanOrEqual(dismiss.frame.height, 44)
        keepScreenshot(app, name: "真实分层完成可继续-" + scenario)
        dismiss.tap()
        XCTAssertFalse(title.exists)
        XCTAssertFalse(dismiss.exists)
        XCTAssertFalse(xp.exists)
        XCTAssertFalse(coins.exists)
        // 再次进入不能从已完成历史重播局部收据。
        relaunchWithOldSeededNotification(app)
        XCTAssertTrue(app.staticTexts["今天的任务都完成了。"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["kid.session.completion-feedback"].exists)
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
        returnToTodayFromTask(in: app)
        XCTAssertFalse(app.staticTexts["kid.today.completion.stamp"].exists)
        assertTodayRewards(xp: 0, coins: 0, in: app)
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
        assertTodayRewards(xp: 0, coins: 0, in: app)
        openSeededTask(in: app)
        let start = app.buttons["kid.session.start"]
        scrollFullyIntoSessionViewport(start, in: app)
        start.tap()
        let pause = app.buttons["kid.session.pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        scrollFullyIntoSessionViewport(pause, in: app)
        pause.tap()
        let submit = app.buttons["kid.session.submit"]
        scrollFullyIntoSessionViewport(submit, in: app)
        submit.tap()
        assertWaitingWithoutOldActions(in: app)
        returnToTodayFromTask(in: app)
        assertTodayRewards(xp: 0, coins: 0, in: app)
        unlockParent(in: app)
        openParentReview(in: app)
        let firstRequestID = reviewAction("approve", in: app).identifier
        let returnAction = reviewAction("return", in: app)
        scrollFullyIntoReviewViewport(returnAction, in: app)
        returnAction.tap()
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
        scrollFullyIntoTodayViewport(task, in: app)
        task.tap()
        XCTAssertTrue(app.buttons["kid.session.start"].waitForExistence(timeout: 5))
        scrollFullyIntoSessionViewport(start, in: app)
        start.tap()
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        scrollFullyIntoSessionViewport(pause, in: app)
        pause.tap()
        scrollFullyIntoSessionViewport(submit, in: app)
        submit.tap()
        assertWaitingWithoutOldActions(in: app)
        returnToTodayFromTask(in: app)
        assertTodayRewards(xp: 0, coins: 0, in: app)
        unlockExistingParent(in: app)
        openParentReview(in: app)
        let secondRequest = reviewAction("approve", in: app)
        XCTAssertNotEqual(secondRequest.identifier, firstRequestID, "重提必须审核新 ID，不能重用退回请求")
        scrollFullyIntoReviewViewport(secondRequest, in: app)
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
        assertTodayRewards(xp: zeroReward ? 0 : 11, coins: zeroReward ? 0 : (secondWasAutonomous ? 10 : 7), in: app)
        assertChildReceipt(zero: zeroReward, autonomous: secondWasAutonomous, in: app)
        continueChildReceipt(in: app)
        assertTodayRewards(xp: zeroReward ? 0 : 11, coins: zeroReward ? 0 : (secondWasAutonomous ? 10 : 7), in: app)
        XCTAssertTrue(app.staticTexts["今天的任务都完成了。"].waitForExistence(timeout: 5))

        relaunchWithOldSeededNotification(app)
        assertTodayRewards(xp: zeroReward ? 0 : 11, coins: zeroReward ? 0 : (secondWasAutonomous ? 10 : 7), in: app)
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
    private func scrollFullyIntoReviewViewport(
        _ element: XCUIElement, in app: XCUIApplication, towardTop: Bool = false
    ) {
        let viewport = app.scrollViews["parent.review.screen"]
        XCTAssertTrue(viewport.exists)
        for _ in 0..<25 {
            let displacement: Double
            if element.exists {
                if element.isHittable, viewport.frame.contains(element.frame) { return }
                let distance = (element.frame.midY - viewport.frame.midY) / viewport.frame.height
                displacement = min(max(abs(distance), 0.08), 0.25) * (distance < 0 ? 1.0 : -1.0)
            } else {
                // 批准后仍停留在列表底部；顶部反馈尚未懒加载，先滚动寻找，再核对完整点击区域。
                displacement = towardTop ? 0.25 : -0.25
            }
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
        scrollFullyIntoTodayViewport(task, in: app)
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
