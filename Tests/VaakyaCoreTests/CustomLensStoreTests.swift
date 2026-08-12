import Foundation
import Testing
@testable import VaakyaCore

@Suite struct CustomLensStoreTests {
    private func tempStore() throws -> (CustomLensStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vaakya-custom-lenses-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return (CustomLensStore(directory: url), url)
    }

    @Test func slugifiesTitlesAndAvoidsReservedIDs() {
        #expect(CustomLensStore.makeSlug(from: "Standup Notes") == "standup_notes")
        #expect(CustomLensStore.makeSlug(from: "  1:1s!! ") == "l_1_1s")
        #expect(CustomLensStore.makeSlug(from: "") == "custom_lens")
    }

    @Test func saveLoadAndListCustomLenses() throws {
        let (store, url) = try tempStore()
        defer { try? FileManager.default.removeItem(at: url) }

        let saved = try store.save(title: "Standup notes", body: "Extract blockers and owners.")
        #expect(saved.id == "standup_notes")
        #expect(saved.origin == .custom)
        #expect(saved.requiresLLM)
        #expect(saved.body.contains("Extract blockers"))

        let loaded = try store.load(id: "standup_notes")
        #expect(loaded.title == "Standup notes")
        #expect(try store.allSpecs().map(\.id) == ["standup_notes"])
    }

    @Test func refusesBundledIDsAndEmptyFields() throws {
        let (store, url) = try tempStore()
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: LensCatalogError.reservedLensID("L5_technical_interview")) {
            try store.save(id: "L5_technical_interview", title: "Nope", body: "body")
        }
        #expect(throws: LensCatalogError.emptyTitle) {
            try store.save(title: "   ", body: "body")
        }
        #expect(throws: LensCatalogError.emptyBody) {
            try store.save(title: "Ok", body: "  ")
        }
        #expect(throws: LensCatalogError.invalidLensID("Bad ID")) {
            try store.save(id: "Bad ID", title: "Ok", body: "body")
        }
    }

    @Test func catalogMergesBundledAndCustomLenses() throws {
        let (store, url) = try tempStore()
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try store.save(title: "Retro board", body: "Cluster themes.")

        let specs = try LensCatalog.allSpecs(userDirectory: url)
        let ids = specs.map(\.id)
        #expect(ids.contains("L0_raw_transcript"))
        #expect(ids.contains("retro_board"))
        let custom = try #require(specs.first(where: { $0.id == "retro_board" }))
        #expect(custom.origin == .custom)
        #expect(try LensCatalog.loadSpec(id: "retro_board", userDirectory: url).title == "Retro board")
    }

    @Test func deleteRemovesOnlyCustomFiles() throws {
        let (store, url) = try tempStore()
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try store.save(title: "Temp", body: "body")
        try store.delete(id: "temp")
        #expect(try store.allSpecs().isEmpty)
        #expect(throws: LensCatalogError.reservedLensID("L0_raw_transcript")) {
            try store.delete(id: "L0_raw_transcript")
        }
    }

    @Test func incrementsSlugWhenTheFileAlreadyExists() throws {
        let (store, url) = try tempStore()
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try store.save(title: "Notes", body: "one")
        let second = try store.save(title: "Notes", body: "two")
        #expect(second.id == "notes_2")
    }
}
