import XCTest

/// 在真实 iPad 模拟器进程中验证不依赖通知的孩子闭环。
@MainActor
final class HabitoKidFlowUITests: XCTestCase {
    private let seededTaskIdentifier = "kid.today.task.c5412144-2fb8-4e96-9f7a-6a42e0803d11"
    private let seededTemplateIdentifier =
        "parent.templates.item.6743a00b-878f-4bb0-a861-64056ec19fe5"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testStartPauseRelaunchResumeCompleteAndUndo() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
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

    func testParentGateRequiresLongPressAndPersistsCredentialAcrossRelaunch() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["--habito-ui-testing", "--habito-ui-reset"]
        app.launch()

        let entry = app.buttons["parent.gate.entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        XCTAssertFalse(app.secureTextFields["parent.gate.pin"].waitForExistence(timeout: 1))

        entry.press(forDuration: 1.2)
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
        entry.press(forDuration: 1.2)
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
}
