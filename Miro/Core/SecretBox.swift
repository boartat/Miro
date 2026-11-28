//
//  SecretBox.swift
//  Miro
//
//  Password lock for hidden games. Only a salted PBKDF2-SHA256 hash of the password is stored
//  (Library/secretbox.json). This hides games from the list; it does not encrypt game files.
//

import CommonCrypto
import Foundation
import Security

@MainActor
final class SecretBox: ObservableObject {
    static let shared = SecretBox()

    @Published private(set) var hasPassword: Bool
    /// While unlocked the sidebar shows the hidden games
    @Published private(set) var isUnlocked = false
    /// Password sheet the UI should present (create / unlock / change)
    @Published var request: SecretBoxRequest?

    private struct Stored: Codable {
        var salt: Data
        var hash: Data
        var rounds: UInt32
    }

    nonisolated static var file: URL { MiroPaths.libraryFolder.appending(path: "secretbox.json") }
    nonisolated static let minimumLength = 4

    private init() {
        hasPassword = Self.load() != nil
        #if DEBUG
        // screenshots of the secret-box look without a password (debug builds only)
        if ProcessInfo.processInfo.environment["MIRO_DEBUG_SECRET_OPEN"] != nil { isUnlocked = true }
        #endif
    }

    /// First run: choose a password
    func setPassword(_ password: String) throws {
        guard password.count >= Self.minimumLength else {
            throw SecretBoxError.tooShort
        }
        var salt = Data(count: 16)
        let status = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        guard status == errSecSuccess else { throw SecretBoxError.storage }
        let rounds: UInt32 = 120_000
        let stored = Stored(salt: salt, hash: Self.derive(password, salt: salt, rounds: rounds), rounds: rounds)
        MiroPaths.ensure(MiroPaths.libraryFolder)
        let data = try JSONEncoder().encode(stored)
        try data.write(to: Self.file, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.file.path(percentEncoded: false))
        hasPassword = true
        isUnlocked = true
    }

    /// Returns true and unlocks when the password matches
    @discardableResult
    func unlock(_ password: String) -> Bool {
        guard let stored = Self.load() else { return false }
        let candidate = Self.derive(password, salt: stored.salt, rounds: stored.rounds)
        guard Self.constantTimeEqual(candidate, stored.hash) else { return false }
        isUnlocked = true
        return true
    }

    func changePassword(current: String, new: String) throws {
        guard let stored = Self.load(),
              Self.constantTimeEqual(Self.derive(current, salt: stored.salt, rounds: stored.rounds), stored.hash) else {
            throw SecretBoxError.wrongPassword
        }
        try setPassword(new)
    }

    func lock() {
        isUnlocked = false
    }

    // MARK: - Helpers

    private static func load() -> Stored? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(Stored.self, from: data)
    }

    private static func derive(_ password: String, salt: Data, rounds: UInt32) -> Data {
        let passwordBytes = Array(password.utf8).map { Int8(bitPattern: $0) }
        var derived = Data(count: 32)
        _ = derived.withUnsafeMutableBytes { derivedBuffer in
            salt.withUnsafeBytes { saltBuffer in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2), passwordBytes, passwordBytes.count,
                    saltBuffer.bindMemory(to: UInt8.self).baseAddress, salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), rounds,
                    derivedBuffer.bindMemory(to: UInt8.self).baseAddress, 32
                )
            }
        }
        return derived
    }

    private static func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}

enum SecretBoxRequest: Identifiable, Equatable {
    /// First use; optionally hide a game right after the password is chosen
    case create(hideAfter: UUID?)
    case unlock
    case change

    var id: String {
        switch self {
        case .create(let id): return "create-\(id?.uuidString ?? "")"
        case .unlock: return "unlock"
        case .change: return "change"
        }
    }
}

enum SecretBoxError: LocalizedError {
    case tooShort, mismatch, wrongPassword, storage

    var errorDescription: String? {
        switch self {
        case .tooShort: return "비밀번호는 \(SecretBox.minimumLength)자 이상이어야 해요"
        case .mismatch: return "두 비밀번호가 서로 달라요"
        case .wrongPassword: return "비밀번호가 달라요"
        case .storage: return "비밀번호를 저장하지 못했어요"
        }
    }
}
