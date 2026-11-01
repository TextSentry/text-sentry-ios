import Foundation
import Security
import CryptoKit

/// Credentials are Keychain-only. Never put API keys in App Group defaults.
enum KeychainVault {
    private static let service = "org.textsentry.ios"

    static func read(_ account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    static func write(_ data: Data, for account: String) throws {
        delete(account)
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw JevError.unavailable }
    }

    static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    static var apiKey: String? {
        read("typesafe-api-key").flatMap { String(data: $0, encoding: .utf8) }
    }

    static func setAPIKey(_ value: String) throws {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !key.contains("\n"), !key.contains("\r") else {
            throw JevError.invalidSettings
        }
        try write(Data(key.utf8), for: "typesafe-api-key")
    }
}

/// JSON archives are encrypted before being written to application-private storage.
enum SecureArchive {
    static func url(for filename: String) throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent(filename)
    }

    static func read<T: Decodable>(_ type: T.Type, file: String) -> T? {
        guard let url = try? url(for: file),
              let encrypted = try? Data(contentsOf: url),
              let keyData = KeychainVault.read("archive-" + file),
              let sealed = try? AES.GCM.SealedBox(combined: encrypted),
              let plain = try? AES.GCM.open(sealed, using: SymmetricKey(data: keyData)) else {
            return nil
        }
        return try? JSONDecoder().decode(T.self, from: plain)
    }

    static func write<T: Encodable>(_ value: T, file: String) throws {
        let keyName = "archive-" + file
        let keyData: Data
        if let existing = KeychainVault.read(keyName) {
            keyData = existing
        } else {
            let randomKey = SymmetricKey(size: .bits256)
            keyData = randomKey.withUnsafeBytes { Data($0) }
            try KeychainVault.write(keyData, for: keyName)
        }
        let payload = try JSONEncoder().encode(value)
        guard let encrypted = try AES.GCM.seal(payload, using: SymmetricKey(data: keyData)).combined else {
            throw JevError.unavailable
        }
        try encrypted.write(to: url(for: file), options: .atomic)
    }

    static func erase(file: String) {
        if let fileURL = try? url(for: file) { try? FileManager.default.removeItem(at: fileURL) }
        KeychainVault.delete("archive-" + file)
    }
}
