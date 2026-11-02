import XCTest
@testable import Mantiza

@MainActor final class EyesTests: XCTestCase {
    func testReadsDemoSettingsScreen() async throws {
        let frame = Frame(image: DemoScreen.settings(), id: 1, capturedAt: Date())
        let reading = try await OCR.read(frame)
        let texts = reading.elements.map(\.text)
        XCTAssertTrue(texts.contains("Settings"), "\(texts)")
        XCTAssertTrue(texts.contains("General"), "\(texts)")
        // Reading order is top to bottom and ids count up from 1.
        XCTAssertEqual(reading.elements.map(\.id), Array(1...reading.elements.count))
        let general = try XCTUnwrap(reading.find("general").first)
        // "General" is drawn in the first row: y = 170...218 of 844 points.
        XCTAssertEqual(general.center.y, (170 + 24) / 844, accuracy: 0.02)
        XCTAssertLessThan(general.center.x, 0.4)
        XCTAssertTrue(reading.table.contains("| General |"))
    }

    func testOrdersLinesThenColumns() {
        let items: [(text: String, box: CGRect, confidence: Double)] = [
            ("right", CGRect(x: 0.6, y: 0.2, width: 0.2, height: 0.03), 1),
            ("below", CGRect(x: 0.1, y: 0.4, width: 0.2, height: 0.03), 1),
            ("left", CGRect(x: 0.1, y: 0.205, width: 0.2, height: 0.03), 1),
        ]
        XCTAssertEqual(OCR.ordered(items).map(\.text), ["left", "right", "below"])
    }

    func testFindPrefersExactMatch() {
        let r = ScreenReading(frameID: 1, elements: [
            ScreenElement(id: 1, text: "General Settings", box: .zero),
            ScreenElement(id: 2, text: "General", box: .zero),
        ])
        XCTAssertEqual(r.find("general").map(\.id), [2, 1])
        XCTAssertTrue(r.find(" ").isEmpty)
    }

    func testDiffSeesSmallChangeButNotSameImage() {
        let a = DemoScreen.settings()
        XCTAssertFalse(ScreenDiff.changed(a, a))
        let b = DemoScreen.settings(size: CGSize(width: 390, height: 844))
        XCTAssertFalse(ScreenDiff.changed(a, b))
        XCTAssertTrue(ScreenDiff.changed(a, DemoScreen.settings(size: CGSize(width: 390, height: 800))))
    }

    func testSettledReturnsNewFrame() async throws {
        let screen = StillScreen()
        screen.show(DemoScreen.settings())
        let action = Date()
        Task { @MainActor in
            try await Task.sleep(for: .milliseconds(100))
            screen.show(DemoScreen.settings())
        }
        let f = try await screen.settled(after: action, quiet: 0.2, most: 2)
        XCTAssertEqual(f.id, 2)
        await screen.stop()
        do { _ = try await screen.frame(after: Date()); XCTFail("expected not sharing") } catch {}
    }
}
