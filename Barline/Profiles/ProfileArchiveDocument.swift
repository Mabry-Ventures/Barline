//
//  ProfileArchiveDocument.swift
//  Barline
//

import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let barlineProfileArchive = UTType(
        exportedAs: "com.mabryventures.barline.profile-archive",
        conformingTo: .json
    )
}

struct ProfileArchiveDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.barlineProfileArchive, .json]

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
