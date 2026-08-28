import BarlineCore
import XCTest

final class BarlineIntegrationTests: XCTestCase {
    func testProfileCodecRoundTripUsesCurrentSchema() throws {
        let profile = BarlineProfile(name: "Integration")
        let codec = ProfileCodec()
        let data = try codec.encode(profile)
        let decoded = try codec.decode(data)
        XCTAssertEqual(decoded.name, "Integration")
        XCTAssertEqual(decoded.schemaVersion, ProfileSchema.currentVersion)
    }
}
