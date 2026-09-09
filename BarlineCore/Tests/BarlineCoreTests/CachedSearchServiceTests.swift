//
//  CachedSearchServiceTests.swift
//  Barline
//

@testable import BarlineCore
import Foundation
import Testing

@Suite("Off-main cached search")
struct CachedSearchServiceTests {
    @Test("Typing reuses the index and changed documents replace it")
    func cachesAndReplaces() async throws {
        let service = CachedSearchService()
        let original = [document("one", title: "Battery")]
        #expect(try await service.search("bat", documents: original).count == 1)
        #expect(try await service.search("batt", documents: original).count == 1)
        #expect(await service.indexBuildCount == 1)
        let replacement = [document("two", title: "Clock")]
        #expect(try await service.search("battery", documents: replacement).isEmpty)
        #expect(try await service.search("clock", documents: replacement).first?.document.id == .init("two"))
        #expect(await service.indexBuildCount == 2)
    }

    @Test("Cancelled requests cannot replace the cached index or return results")
    func cancellation() async throws {
        let service = CachedSearchService()
        let documents = [document("one", title: "Battery")]
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await service.search("battery", documents: documents)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await service.indexBuildCount == 0)
        #expect(try await service.search("battery", documents: documents).count == 1)
    }

    @Test("Published result sets are bounded")
    func boundsResults() async throws {
        let documents = (0 ..< 250).map { document("item.\($0)", title: "Battery \($0)") }
        let service = CachedSearchService()
        #expect(try await service.search("battery", documents: documents).count == 200)
    }

    @Test("Invalid replacement leaves the prior index reusable")
    func invalidReplacement() async throws {
        let service = CachedSearchService()
        let document = document("one", title: "Battery")
        _ = try await service.search("battery", documents: [document])
        await #expect(throws: SearchIndexError.self) {
            try await service.search("battery", documents: [document, document])
        }
        #expect(try await service.search("battery", documents: [document]).count == 1)
        #expect(await service.indexBuildCount == 1)
    }

    @Test("Search workload leaves the main actor available for input")
    @MainActor
    func mainActorRemainsResponsive() async throws {
        let documents = (0 ..< 1000).map { document("item.\($0)", title: "Battery Utility \($0)") }
        let service = CachedSearchService()
        let clock = ContinuousClock()
        var ticks = 0
        var longestInterval: Duration = .zero
        let heartbeat = Task { @MainActor in
            var previous = clock.now
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(1)) } catch { break }
                let now = clock.now
                longestInterval = max(longestInterval, previous.duration(to: now))
                previous = now
                ticks += 1
            }
        }
        defer { heartbeat.cancel() }
        let start = clock.now
        for query in ["b", "ba", "bat", "batt", "batte", "battery", "util", "utility", "battery utility"] {
            _ = try await service.search(query, documents: documents)
        }
        #expect(ticks > 0)
        #expect(await service.indexBuildCount == 1)
        print("Search responsiveness probe: 1000 documents, 9 queries, \(ticks) main-actor ticks, longest interval \(longestInterval), elapsed \(start.duration(to: clock.now))")
    }

    private func document(_ id: String, title: String) -> SearchDocument {
        SearchDocument(id: .init(id), kind: .command, entity: .command(.init(id)), title: title)
    }
}
