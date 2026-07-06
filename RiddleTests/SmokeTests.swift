import XCTest
@testable import Riddle

final class SmokeTests: XCTestCase {
    func testFontsLoaded() {
        XCTAssertNotNil(UIFont(name: "DancingScript-Regular", size: 96))
        XCTAssertNotNil(UIFont(name: "LXGWWenKai-Regular", size: 96))
    }
    func testSecretsPresent() {
        XCTAssertFalse(Secrets.baseURL.isEmpty)
        XCTAssertTrue(Secrets.baseURL.hasPrefix("https://"))
    }
}
