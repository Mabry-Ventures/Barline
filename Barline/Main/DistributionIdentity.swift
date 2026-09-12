//
//  DistributionIdentity.swift
//  Barline
//

import Foundation
import Security

/// Identifies copies of Barline that were distributed to users.
enum DistributionIdentity {
    /// Apple's standard requirement for a Developer ID Application signature:
    /// an Apple-anchored chain whose intermediate is the Developer ID CA and
    /// whose leaf is a Developer ID Application certificate.
    private static let developerIDRequirement = """
    anchor apple generic \
    and certificate 1[field.1.2.840.113635.100.6.2.6] exists \
    and certificate leaf[field.1.2.840.113635.100.6.1.13] exists
    """

    /// `true` only when the running copy carries a valid Developer ID
    /// Application signature, the way Barline releases are signed. Development
    /// builds, gate builds re-signed ad hoc, and locally built Release products
    /// all return `false`, so first-run prompts never interrupt them.
    static let isDeveloperIDSigned: Bool = {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else {
            return false
        }
        var requirement: SecRequirement?
        guard
            SecRequirementCreateWithString(developerIDRequirement as CFString, [], &requirement) == errSecSuccess,
            let requirement
        else {
            return false
        }
        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }()
}
