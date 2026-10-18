import Foundation
import CryptoKit
import SuperPasteCore

/// Why a sync step failed; the description is what the Sync pane shows.
public enum SyncError: LocalizedError, Equatable {
    /// The folder already holds Super Paste data sealed with a key this Mac doesn't have.
    case missingKey
    /// This Mac's key doesn't open the folder's data.
    case keyMismatch
    /// Text given to `importKey` isn't a sync key.
    case invalidKey
    /// The folder can't be created, read or written.
    case folderUnavailable(String)
    /// A file isn't a Super Paste sync file, or it was changed by someone without the key.
    case unreadableFile(String)
    case keychain(String)

    public var errorDescription: String? {
        switch self {
        case .missingKey:
            "This folder is already used by another Mac. Import that Mac's sync key first."
        case .keyMismatch:
            "This Mac's sync key doesn't match the one the folder was set up with."
        case .invalidKey:
            "That isn't a Super Paste sync key."
        case .folderUnavailable(let why):
            "The sync folder isn't available: \(why)"
        case .unreadableFile(let name):
            "A file in the sync folder couldn't be decrypted (\(name)). It may be damaged or changed by someone else."
        case .keychain(let why):
            "The sync key couldn't be saved in the Keychain: \(why)"
        }
    }
}

/// The 256-bit key every Mac that shares a sync folder holds. File contents are sealed with a subkey derived for
/// sealing, and blob file names are keyed hashes under another subkey, so the folder never sees a value computed
/// with the master key itself and a blob's name doesn't reveal which content it holds.
public struct SyncKey: @unchecked Sendable {
    public let data: Data
    let sealing: SymmetricKey
    let naming: SymmetricKey

    /// The text form starts with this; `init(text:)` also accepts the bare Base64.
    public static let textPrefix = "SPK1-"

    public init?(data: Data) {
        guard data.count == 32 else { return nil }
        self.data = data
        let master = SymmetricKey(data: data)
        sealing = HKDF<SHA256>.deriveKey(inputKeyMaterial: master, salt: Data("superpaste.sync".utf8),
                                         info: Data("seal.v1".utf8), outputByteCount: 32)
        naming = HKDF<SHA256>.deriveKey(inputKeyMaterial: master, salt: Data("superpaste.sync".utf8),
                                        info: Data("blob-name.v1".utf8), outputByteCount: 32)
    }

    public static func generate() -> SyncKey {
        SyncKey(data: SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) })!
    }

    /// `SPK1-` + the key in Base64: what the user moves to another Mac.
    public var text: String { Self.textPrefix + data.base64EncodedString() }

    /// Parses `text`; whitespace anywhere (line breaks from mail or notes) and the prefix are optional.
    public init(text: String) throws {
        var t = text.filter { !$0.isWhitespace }
        if t.uppercased().hasPrefix(Self.textPrefix) { t.removeFirst(Self.textPrefix.count) }
        guard let data = Data(base64Encoded: t), let key = SyncKey(data: data) else { throw SyncError.invalidKey }
        self = key
    }

    /// The file name a blob with this SHA-256 digest gets in the folder: HMAC-SHA256 under the naming subkey.
    public func blobName(forDigest digest: String) -> String {
        let mac = HMAC<SHA256>.authenticationCode(for: Data(digest.utf8), using: naming)
        return mac.map { String(format: "%02x", $0) }.joined()
    }

    public func matches(_ other: SyncKey) -> Bool { data == other.data }
}

/// Sealing for every file in the sync folder: `SPS1`, a flags byte, then AES-256-GCM (12-byte random nonce,
/// ciphertext, 16-byte tag). The header and the file's logical name (`context`) are authenticated, so a file can't
/// be renamed, swapped for another or have its flags flipped without failing to open.
public enum SyncCrypto {
    private static let magic = Data("SPS1".utf8)
    private static let compressedFlag: UInt8 = 1

    public static func seal(_ plain: Data, key: SyncKey, context: String, compress: Bool = false) throws -> Data {
        var body = plain
        var flags: UInt8 = 0
        if compress, let packed = try? (plain as NSData).compressed(using: .lzfse) as Data, packed.count < plain.count {
            body = packed
            flags |= compressedFlag
        }
        let header = magic + Data([flags])
        guard let combined = try AES.GCM.seal(body, using: key.sealing, authenticating: aad(header, context)).combined
        else { throw SyncError.unreadableFile(context) }
        return header + combined
    }

    /// Opens a sealed file; throws `unreadableFile` when it isn't one, was sealed under another name or key, or was
    /// changed.
    public static func open(_ sealed: Data, key: SyncKey, context: String) throws -> Data {
        guard sealed.count > magic.count + 1 + 28, sealed.prefix(magic.count) == magic else {
            throw SyncError.unreadableFile(context)
        }
        let header = Data(sealed.prefix(magic.count + 1))
        let flags = header[header.startIndex + magic.count]
        guard flags & ~compressedFlag == 0 else { throw SyncError.unreadableFile(context) }
        do {
            let box = try AES.GCM.SealedBox(combined: sealed.dropFirst(header.count))
            let body = try AES.GCM.open(box, using: key.sealing, authenticating: aad(header, context))
            guard flags & compressedFlag != 0 else { return body }
            return try (body as NSData).decompressed(using: .lzfse) as Data
        } catch {
            throw SyncError.unreadableFile(context)
        }
    }

    private static func aad(_ header: Data, _ context: String) -> Data {
        header + Data("superpaste.sync.v1\0\(context)".utf8)
    }
}

// MARK: - Key storage

/// Where this Mac keeps the sync key. Tests use an in-memory one.
@MainActor
public protocol SyncKeyStoring: AnyObject {
    func load() -> SyncKey?
    func save(_ key: SyncKey) throws
}

/// The key as a generic password in the login Keychain (`Keychain`, account "syncKey"). It never syncs through
/// iCloud Keychain; other Macs get it with Export/Import Key.
@MainActor
public final class KeychainSyncKeyStore: SyncKeyStoring {
    private let account = "syncKey"

    public init() {}

    public func load() -> SyncKey? {
        Keychain.get(account).flatMap { try? SyncKey(text: $0) }
    }

    public func save(_ key: SyncKey) throws {
        Keychain.set(key.text, for: account)
        guard load()?.matches(key) == true else { throw SyncError.keychain("the Keychain refused the item") }
    }
}
