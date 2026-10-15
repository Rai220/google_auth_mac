import Foundation
import CryptoKit

public enum AuthError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}
public enum Algorithm: String, Codable, CaseIterable { case sha1 = "SHA1", sha256 = "SHA256", sha512 = "SHA512" }
public enum OTPKind: String, Codable, CaseIterable { case totp, hotp }
public struct Account: Identifiable, Codable, Equatable {
    public var id: UUID
    public var name: String
    public var issuer: String
    public var secret: Data
    public var algorithm: Algorithm
    public var digits: Int
    public var kind: OTPKind
    public var counter: UInt64
    public var period: Int
    public init(id: UUID = UUID(), name: String, issuer: String = "", secret: Data, algorithm: Algorithm = .sha1, digits: Int = 6, kind: OTPKind = .totp, counter: UInt64 = 0, period: Int = 30) {
        self.id = id; self.name = name; self.issuer = issuer; self.secret = secret
        self.algorithm = algorithm; self.digits = digits; self.kind = kind; self.counter = counter; self.period = period
    }
    public func validate() throws {
        guard !secret.isEmpty, secret.count <= 4096, !name.isEmpty, name.count <= 2048, issuer.count <= 2048,
              [6,8].contains(digits), (1...86400).contains(period) else { throw AuthError.invalid(L10n.text("Invalid account parameters.")) }
    }
    public func sameCredential(as other: Account) -> Bool {
        secret == other.secret && algorithm == other.algorithm && digits == other.digits && kind == other.kind && period == other.period
    }
    public func code(at date: Date = Date()) throws -> String {
        try validate()
        let time = date.timeIntervalSince1970
        guard time.isFinite, time >= 0, time / Double(period) < Double(UInt64.max) else { throw AuthError.invalid(L10n.text("Invalid time.")) }
        var value = (kind == .hotp ? counter : UInt64(time / Double(period))).bigEndian
        let message = withUnsafeBytes(of: &value) { Data($0) }
        let key = SymmetricKey(data: secret)
        let hash: [UInt8]
        switch algorithm {
        case .sha1: hash = Array(HMAC<Insecure.SHA1>.authenticationCode(for: message, using: key))
        case .sha256: hash = Array(HMAC<SHA256>.authenticationCode(for: message, using: key))
        case .sha512: hash = Array(HMAC<SHA512>.authenticationCode(for: message, using: key))
        }
        let offset = Int(hash.last! & 15)
        let truncated = (UInt32(hash[offset] & 127) << 24) | (UInt32(hash[offset+1]) << 16) | (UInt32(hash[offset+2]) << 8) | UInt32(hash[offset+3])
        return String(format: "%0*u", digits, truncated % (digits == 8 ? 100_000_000 : 1_000_000))
    }
}
public enum Base32 {
    public static func decode(_ string: String) throws -> Data {
        let input = string.uppercased().filter { !$0.isWhitespace }
        let unpadded = input.prefix { $0 != "=" }
        guard input.dropFirst(unpadded.count).allSatisfy({ $0 == "=" }), [0,2,4,5,7].contains(unpadded.count % 8) else { throw AuthError.invalid(L10n.text("Invalid Base32 key.")) }
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".utf8)
        var buffer: UInt32 = 0; var bits = 0; var result = Data()
        for byte in unpadded.utf8 {
            guard let index = alphabet.firstIndex(of: byte) else { throw AuthError.invalid(L10n.text("The key must contain only A–Z and 2–7.")) }
            buffer = (buffer << 5) | UInt32(index); bits += 5
            if bits >= 8 { bits -= 8; result.append(UInt8((buffer >> bits) & 255)) }
        }
        guard !result.isEmpty, bits == 0 || buffer & ((1 << bits) - 1) == 0 else { throw AuthError.invalid(L10n.text("Invalid Base32 key.")) }
        return result
    }
}
