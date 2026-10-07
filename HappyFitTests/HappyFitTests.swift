import XCTest
@testable import HappyFit

/// Test di base per verificare che il target di test sia configurato.
final class HappyFitTests: XCTestCase {
    func testAppName() {
        XCTAssertEqual(AppBranding.appName, "HappyFit")
    }
}
