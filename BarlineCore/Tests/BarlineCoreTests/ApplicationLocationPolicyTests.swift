//
//  ApplicationLocationPolicyTests.swift
//  Barline
//

@testable import BarlineCore
import Testing

@Suite("Application location")
struct ApplicationLocationPolicyTests {
    private let home = "/Users/person"

    private func location(_ path: String) -> ApplicationLocationPolicy.Location {
        ApplicationLocationPolicy.location(bundlePath: path, homeDirectory: home)
    }

    @Test("Applications folders need no offer")
    func applicationsFolders() {
        #expect(location("/Applications/Barline.app") == .applicationsFolder)
        #expect(location("/Applications/Utilities/Barline.app") == .applicationsFolder)
        #expect(location("/Users/person/Applications/Barline.app") == .applicationsFolder)
        #expect(location("/Applications/Barline.app/") == .applicationsFolder)
        #expect(location("//Applications///Barline.app") == .applicationsFolder)
    }

    @Test("Folder checks ignore case, as macOS volumes do by default")
    func caseInsensitiveFolders() {
        #expect(location("/applications/Barline.app") == .applicationsFolder)
        #expect(location("/APPLICATIONS/Utilities/Barline.app") == .applicationsFolder)
        #expect(location("/Users/Person/applications/Barline.app") == .applicationsFolder)
        #expect(location("/volumes/Barline/Barline.app") == .mountedVolume)
        #expect(location("/applicationsbackup/Barline.app") == .elsewhere)
    }

    @Test("A home directory with a trailing slash still matches ~/Applications")
    func homeDirectoryTrailingSlash() {
        #expect(
            ApplicationLocationPolicy.location(
                bundlePath: "/Users/person/Applications/Barline.app",
                homeDirectory: "/Users/person/"
            ) == .applicationsFolder
        )
    }

    @Test("Downloads and other folders can be moved automatically")
    func ordinaryFolders() {
        #expect(location("/Users/person/Downloads/Barline.app") == .elsewhere)
        #expect(location("/Users/person/Desktop/Barline.app") == .elsewhere)
        #expect(
            location("/private/tmp/barline-ci/DerivedData/Build/Products/Debug/Barline.app") == .elsewhere
        )
    }

    @Test("Folder names that only start with Applications are not Applications folders")
    func prefixTraps() {
        #expect(location("/ApplicationsBackup/Barline.app") == .elsewhere)
        #expect(location("/Users/person/Applications Old/Barline.app") == .elsewhere)
        #expect(location("/Users/other/Applications/Barline.app") == .elsewhere)
    }

    @Test("Traversal cannot disguise another folder as Applications")
    func traversal() {
        #expect(location("/Applications/../Users/person/Downloads/Barline.app") == .elsewhere)
        #expect(location("/Users/person/Downloads/../../../Applications/Barline.app") == .applicationsFolder)
        #expect(location("/Applications/./Barline.app") == .applicationsFolder)
    }

    @Test("App Translocation paths are detected by path component")
    func translocation() {
        #expect(
            location("/private/var/folders/ab/cd/T/AppTranslocation/0A1B2C3D/d/Barline.app") == .translocated
        )
        #expect(location("/Users/person/AppTranslocationNotes/Barline.app") == .elsewhere)
    }

    @Test("Mounted volumes, including the release disk image, need a manual move")
    func mountedVolumes() {
        #expect(location("/Volumes/Barline/Barline.app") == .mountedVolume)
        #expect(location("/VolumesArchive/Barline.app") == .elsewhere)
    }

    @Test("Offers follow the location")
    func offers() {
        let cases: [(ApplicationLocationPolicy.Location, ApplicationLocationPolicy.Offer)] = [
            (.applicationsFolder, .none),
            (.elsewhere, .moveAutomatically),
            (.translocated, .moveManually),
            (.mountedVolume, .moveManually),
        ]
        for (location, expected) in cases {
            #expect(ApplicationLocationPolicy.offer(for: location, isEligible: true, userDeclined: false) == expected)
        }
    }

    @Test("Development builds and a declined offer are never interrupted")
    func suppressedOffers() {
        for location in [
            ApplicationLocationPolicy.Location.elsewhere, .translocated, .mountedVolume, .applicationsFolder,
        ] {
            #expect(ApplicationLocationPolicy.offer(for: location, isEligible: false, userDeclined: false) == .none)
            #expect(ApplicationLocationPolicy.offer(for: location, isEligible: true, userDeclined: true) == .none)
        }
    }
}
