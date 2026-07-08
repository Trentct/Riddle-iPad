import XCTest
@testable import Riddle

/// 致谢清单是法务要求，不是可选文案——这里断言每个必须出现的来源都在列表里、且都带非空 license，
/// 防止以后改致谢文案时不小心漏掉某一项却没人发现（对齐 SoundStoreTests/StoreManagerTests 同类"防手滑"用意）。
final class AttributionsTests: XCTestCase {
    func testAllItemsHaveNonEmptyLicenseAndNote() {
        for item in Attributions.all {
            XCTAssertFalse(item.name.isEmpty, "\(item.id) 名称不应为空")
            XCTAssertFalse(item.license.isEmpty, "\(item.id) license 不应为空")
            XCTAssertFalse(item.note.isEmpty, "\(item.id) 说明不应为空")
        }
    }

    func testCoversAlgorithmOrigin() {
        XCTAssertTrue(Attributions.all.contains { $0.name.contains("MaximeRivest/Riddle") },
                      "必须致谢算法与 persona 出处 MaximeRivest/Riddle")
    }

    func testCoversActivelyUsedFonts() {
        XCTAssertTrue(Attributions.all.contains { $0.name.contains("LXGW WenKai") },
                      "归野/沈砚使用的 LXGW WenKai 必须致谢")
        XCTAssertTrue(Attributions.all.contains { $0.name.contains("Dancing Script") },
                      "Ashford 使用的 Dancing Script 必须致谢")
    }

    func testCoversSDTTrajectoryModel() {
        XCTAssertTrue(Attributions.all.contains { $0.name.contains("SDT") },
                      "手泽轨迹字库背后的 SDT 模型必须致谢")
    }

    func testIDsAreUnique() {
        let ids = Attributions.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "致谢条目 id 不应重复")
    }
}
