@testable import BarlineCore
import Testing

struct CapturePublicationPolicyTests {
    @Test func currentGrantedCaptureCanPublish() {
        #expect(CapturePublicationPolicy.permitsPublication(
            capturedGeneration: 1, currentGeneration: 1, permissionIsGranted: true
        ))
    }

    @Test func revokedOrRegrantedCaptureCannotPublish() {
        #expect(!CapturePublicationPolicy.permitsPublication(
            capturedGeneration: 1, currentGeneration: 1, permissionIsGranted: false
        ))
        #expect(!CapturePublicationPolicy.permitsPublication(
            capturedGeneration: 1, currentGeneration: 2, permissionIsGranted: false
        ))
        #expect(!CapturePublicationPolicy.permitsPublication(
            capturedGeneration: 1, currentGeneration: 3, permissionIsGranted: true
        ))
    }
}
