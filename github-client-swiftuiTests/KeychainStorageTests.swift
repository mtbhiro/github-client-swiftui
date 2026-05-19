import Foundation
import Testing
@testable import github_client_swiftui

struct KeychainStorageTests {

    private func makeSUT() -> KeychainStorage {
        KeychainStorage(service: "test.\(UUID().uuidString)", account: "access_token")
    }

    @Test func save_thenLoad_returnsSavedString() throws {
        let storage = makeSUT()
        try storage.save("token-abc")
        #expect(storage.load() == "token-abc")
    }

    @Test func save_overwrite_returnsLatestValue() throws {
        let storage = makeSUT()
        try storage.save("token-first")
        try storage.save("token-second")
        #expect(storage.load() == "token-second")
    }

    @Test func delete_removesValue() throws {
        let storage = makeSUT()
        try storage.save("token-x")
        try storage.delete()
        #expect(storage.load() == nil)
    }

    @Test func delete_whenAbsent_doesNotThrow() throws {
        let storage = makeSUT()
        try storage.delete()
        #expect(storage.load() == nil)
    }

    @Test func load_withNoSavedValue_returnsNil() {
        let storage = makeSUT()
        #expect(storage.load() == nil)
    }

    @Test func differentService_doesNotShareValue() throws {
        let serviceA = "test.\(UUID().uuidString)"
        let serviceB = "test.\(UUID().uuidString)"
        let storageA = KeychainStorage(service: serviceA, account: "token")
        let storageB = KeychainStorage(service: serviceB, account: "token")

        try storageA.save("for-A")
        #expect(storageB.load() == nil)
    }
}
