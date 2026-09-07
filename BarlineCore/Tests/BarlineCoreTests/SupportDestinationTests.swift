//
//  SupportDestinationTests.swift
//  Barline
//

@testable import BarlineCore
import Testing

struct SupportDestinationTests {
    @Test func unsetAndPlaceholderDestinationsStayAbsent() {
        for value in [nil, "", "$(BARLINE_SUPPORT_URL)", "https://example.com/support", "https://site.invalid"] {
            #expect(SupportDestination.url(from: value) == nil)
        }
    }

    @Test func rejectsUnsafeOrTrackingDestinations() {
        for value in [
            "http://usebarline.com/support", "javascript:alert(1)", "file:///tmp/site",
            "https://user:pass@usebarline.com/support", "https://usebarline.com:443/support",
            "https://usebarline.com/support?item=private", " https://usebarline.com", "https://localhost",
        ] {
            #expect(SupportDestination.url(from: value) == nil)
        }
    }

    @Test func acceptsCanonicalHTTPSOnlyWhenConfigured() {
        #expect(SupportDestination.url(from: "https://usebarline.com/#support")?.absoluteString
            == "https://usebarline.com/#support")
    }
}
