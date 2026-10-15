import Foundation
import Security
import Vision
import ImageIO

public struct Vault {
    private let service: String
    public init(service: String = "local.macauthenticator.vault.v1") { self.service = service }
    private var query: [String:Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "accounts"] }
    public func load() throws -> [Account] {
        var request = query; request[kSecReturnData as String] = true; request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        try check(status)
        guard let data = result as? Data else { throw AuthError.invalid(L10n.text("Could not read the macOS Keychain.")) }
        let accounts = try JSONDecoder().decode([Account].self, from: data)
        for account in accounts { try account.validate() }
        guard Set(accounts.map(\.id)).count == accounts.count else { throw AuthError.invalid(L10n.text("The account vault is damaged.")) }
        return accounts
    }
    public func save(_ accounts: [Account]) throws {
        for account in accounts { try account.validate() }
        let data = try JSONEncoder().encode(accounts)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var request = query; request[kSecValueData as String] = data
            request[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            request[kSecAttrLabel as String] = L10n.text("Mac Authenticator — accounts")
            try check(SecItemAdd(request as CFDictionary, nil))
        } else { try check(status) }
    }
    public func delete() throws { let status = SecItemDelete(query as CFDictionary); if status != errSecItemNotFound { try check(status) } }
    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else { throw AuthError.invalid(L10n.text("Keychain: {0}", String(SecCopyErrorMessageString(status, nil) as String? ?? String(status)))) }
    }
}
public enum QRImport {
    public static func messages(in data: Data) throws -> [String] {
        guard data.count <= 30_000_000 else { throw AuthError.invalid(L10n.text("The image exceeds 30 MB.")) }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 4096, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { throw AuthError.invalid(L10n.text("Could not open the image.")) }
        let request = VNDetectBarcodesRequest(); request.symbologies = [.qr]
        try VNImageRequestHandler(cgImage: image).perform([request])
        let messages = (request.results ?? []).compactMap(\.payloadStringValue).filter { $0.hasPrefix("otpauth://") || $0.hasPrefix("otpauth-migration://") }
        guard !messages.isEmpty else { throw AuthError.invalid(L10n.text("No Authenticator QR code found. Choose a clear, complete image with a margin around the code.")) }
        return messages
    }
    public static func read(url: URL) throws -> [ImportPart] {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 30_000_000 else { throw AuthError.invalid(L10n.text("The file exceeds 30 MB.")) }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        if let text = String(data: data, encoding: .utf8), text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("otpauth") { return try OTPImport.parse(text: text) }
        return try messages(in: data).flatMap { try OTPImport.parse(text: $0) }
    }
}
