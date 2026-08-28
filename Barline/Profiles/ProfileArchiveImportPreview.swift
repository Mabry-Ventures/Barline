//
//  ProfileArchiveImportPreview.swift
//  Barline
//

import BarlineCore
import Foundation

struct ProfileArchiveImportPreview: Identifiable, Sendable {
    let id = UUID()
    let profiles: [BarlineProfile]
    let conflictingProfileIDs: Set<UUID>

    var hasConflicts: Bool {
        !conflictingProfileIDs.isEmpty
    }

    var summary: String {
        let profileCount = profiles.count
        let conflictCount = conflictingProfileIDs.count
        if conflictCount == 0 {
            return "\(profileCount) profile\(profileCount == 1 ? "" : "s") ready to import."
        }
        return "\(profileCount) profiles, including \(conflictCount) existing profile\(conflictCount == 1 ? "" : "s")."
    }
}
