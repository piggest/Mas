import XCTest
@testable import Mas

/// CGEventTap 駆動の範囲選択における座標追跡ロジックのテスト。
///
/// SelectionState はドラッグ中の start/current グローバル CG 座標を保持し、
/// 選択範囲の rect を計算する純粋ロジック。
final class SelectionStateTests: XCTestCase {

    func test_initialState_hasNoSelectionRect() {
        let state = SelectionState()
        XCTAssertNil(state.selectionRect)
        XCTAssertNil(state.startPoint)
        XCTAssertNil(state.currentPoint)
    }

    func test_begin_setsStartAndCurrentToSamePoint() {
        var state = SelectionState()
        state.begin(at: CGPoint(x: 100, y: 200))
        XCTAssertEqual(state.startPoint, CGPoint(x: 100, y: 200))
        XCTAssertEqual(state.currentPoint, CGPoint(x: 100, y: 200))
        // 0x0 rect になる
        XCTAssertEqual(state.selectionRect, CGRect(x: 100, y: 200, width: 0, height: 0))
    }

    func test_update_movesCurrentPoint() {
        var state = SelectionState()
        state.begin(at: CGPoint(x: 100, y: 200))
        state.update(to: CGPoint(x: 150, y: 250))
        XCTAssertEqual(state.startPoint, CGPoint(x: 100, y: 200))
        XCTAssertEqual(state.currentPoint, CGPoint(x: 150, y: 250))
        XCTAssertEqual(state.selectionRect, CGRect(x: 100, y: 200, width: 50, height: 50))
    }

    func test_selectionRect_normalizes_whenDraggedReverse() {
        var state = SelectionState()
        state.begin(at: CGPoint(x: 200, y: 300))
        state.update(to: CGPoint(x: 100, y: 250))
        // 始点より左上にドラッグしても、rect は左上原点・正の size
        XCTAssertEqual(state.selectionRect, CGRect(x: 100, y: 250, width: 100, height: 50))
    }

    func test_reset_clearsState() {
        var state = SelectionState()
        state.begin(at: CGPoint(x: 100, y: 200))
        state.update(to: CGPoint(x: 150, y: 250))
        state.reset()
        XCTAssertNil(state.selectionRect)
        XCTAssertNil(state.startPoint)
        XCTAssertNil(state.currentPoint)
    }

    func test_isClick_returnsTrue_whenDragDistanceSmall() {
        var state = SelectionState()
        state.begin(at: CGPoint(x: 100, y: 100))
        state.update(to: CGPoint(x: 105, y: 103))
        // 約 5.83px → トラックパッドの微小ドラッグはクリック扱い
        XCTAssertTrue(state.isClickGesture(threshold: 20))
    }

    func test_isClick_returnsFalse_whenDragDistanceLarge() {
        var state = SelectionState()
        state.begin(at: CGPoint(x: 100, y: 100))
        state.update(to: CGPoint(x: 200, y: 200))
        XCTAssertFalse(state.isClickGesture(threshold: 20))
    }

    func test_isClick_returnsTrue_whenNotStarted() {
        let state = SelectionState()
        XCTAssertTrue(state.isClickGesture(threshold: 20), "未開始ならクリック扱い")
    }
}
