import Foundation

public struct ImportPart {
    public var accounts: [Account]
    public var batchID: UInt64?
    public var batchSize: Int
    public var batchIndex: Int
    public init(accounts: [Account], batchID: UInt64? = nil, batchSize: Int = 1, batchIndex: Int = 0) {
        self.accounts = accounts; self.batchID = batchID; self.batchSize = batchSize; self.batchIndex = batchIndex
    }
}
public struct ImportSession {
    private var parts: [ImportPart] = []
    public init() {}
    public var accounts: [Account] {
        var result: [Account] = []
        for account in parts.flatMap(\.accounts) where !result.contains(where: { $0.sameCredential(as: account) }) { result.append(account) }
        return result
    }
    public var missingParts: Int {
        let batches = Dictionary(grouping: parts.filter { $0.batchSize > 1 }, by: { $0.batchID })
        return batches.values.reduce(0) { $0 + $1[0].batchSize - Set($1.map(\.batchIndex)).count }
    }
    public var partCount: Int { parts.count }
    public mutating func add(_ incoming: [ImportPart]) throws {
        var copy = parts
        for part in incoming {
            if part.batchSize > 1 {
                let siblings = copy.filter { $0.batchID == part.batchID && $0.batchSize > 1 }
                guard siblings.allSatisfy({ $0.batchSize == part.batchSize }) else { throw AuthError.invalid(L10n.text("The export parts do not match.")) }
                if let previous = siblings.first(where: { $0.batchIndex == part.batchIndex }) {
                    guard previous.accounts.count == part.accounts.count,
                          zip(previous.accounts, part.accounts).allSatisfy({ $0.sameCredential(as: $1) && $0.name == $1.name && $0.issuer == $1.issuer && $0.counter == $1.counter }) else { throw AuthError.invalid(L10n.text("Two different versions of the same export part were found.")) }
                    continue
                }
            }
            copy.append(part)
        }
        parts = copy
    }
}
public enum OTPImport {
    public static func parse(text: String) throws -> [ImportPart] {
        guard text.utf8.count <= 4_000_000 else { throw AuthError.invalid(L10n.text("The file is too large.")) }
        let lines = text.split(whereSeparator: \.isWhitespace)
        guard !lines.isEmpty else { throw AuthError.invalid(L10n.text("Paste an otpauth link or an export QR code.")) }
        return try lines.map { try parseURI(String($0)) }
    }
    public static func parseURI(_ input: String) throws -> ImportPart {
        guard input.utf8.count <= 1_000_000, let url = URLComponents(string: input) else { throw AuthError.invalid(L10n.text("Invalid link.")) }
        var query: [String:String] = [:]
        for item in url.queryItems ?? [] {
            guard query[item.name] == nil, let value = item.value else { throw AuthError.invalid(L10n.text("Duplicate or empty link parameter.")) }
            query[item.name] = value
        }
        if url.scheme == "otpauth-migration" {
            guard url.host == "offline", var encoded = query["data"] else { throw AuthError.invalid(L10n.text("Invalid Google Authenticator export link.")) }
            encoded = encoded.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
            guard let data = Data(base64Encoded: encoded), !data.isEmpty else { throw AuthError.invalid(L10n.text("The export data is damaged.")) }
            return try migration(data)
        }
        guard url.scheme == "otpauth", let kind = OTPKind(rawValue: url.host ?? ""), let secret = query["secret"] else { throw AuthError.invalid(L10n.text("Only otpauth:// and otpauth-migration:// links are supported.")) }
        let label = String(url.path.dropFirst())
        let (issuerFromLabel, name) = splitLabel(label)
        let algorithm: Algorithm
        if let raw = query["algorithm"] {
            guard let parsed = Algorithm(rawValue: raw.uppercased()) else { throw AuthError.invalid(L10n.text("Unsupported algorithm.")) }; algorithm = parsed
        } else { algorithm = .sha1 }
        let digits = try intParameter(query["digits"], fallback: 6)
        let period = try intParameter(query["period"], fallback: 30)
        var counter: UInt64 = 0
        if let raw = query["counter"] { guard let value = UInt64(raw) else { throw AuthError.invalid(L10n.text("Invalid HOTP counter.")) }; counter = value }
        else if kind == .hotp { throw AuthError.invalid(L10n.text("HOTP requires a counter.")) }
        if let issuer = query["issuer"], !issuerFromLabel.isEmpty, issuer != issuerFromLabel { throw AuthError.invalid(L10n.text("The service name in the link does not match the issuer.")) }
        let account = Account(name: name, issuer: query["issuer"] ?? issuerFromLabel, secret: try Base32.decode(secret), algorithm: algorithm, digits: digits, kind: kind, counter: counter, period: period)
        try account.validate()
        return ImportPart(accounts: [account])
    }
    private static func intParameter(_ input: String?, fallback: Int) throws -> Int {
        guard let input else { return fallback }
        guard let value = Int(input) else { throw AuthError.invalid(L10n.text("Invalid numeric parameter.")) }; return value
    }
    private static func splitLabel(_ label: String) -> (String, String) {
        if let colon = label.firstIndex(of: ":") { return (String(label[..<colon]), String(label[label.index(after: colon)...]).trimmingCharacters(in: .whitespaces)) }
        return ("", label)
    }
    private static func migration(_ data: Data) throws -> ImportPart {
        let fields = try Proto.fields(data)
        let version = try fields.number(2, default: 1)
        guard version == 1 || version == 2 else { throw AuthError.invalid(L10n.text("Unsupported export version: {0}.", String(version))) }
        let size = try fields.number(3, default: 1), index = try fields.number(4, default: 0)
        guard (1...1000).contains(size), index < size else { throw AuthError.invalid(L10n.text("Invalid QR code numbering.")) }
        // Version 2 exports can omit batch_id (proto3 default). Treat the current
        // import session as one anonymous batch; conflicting parts are rejected.
        let id: UInt64? = fields.contains(where: { $0.tag == 5 }) ? try fields.number(5, default: 0) : nil
        let accounts = try fields.filter { $0.tag == 1 }.map { field -> Account in
            guard case .bytes(let bytes) = field.value else { throw AuthError.invalid(L10n.text("Damaged account in the export.")) }
            let values = try Proto.fields(bytes)
            let algorithm: Algorithm
            switch try values.number(4, default: 0) {
            case 1: algorithm = .sha1
            case 2: algorithm = .sha256
            case 3: algorithm = .sha512
            default: throw AuthError.invalid(L10n.text("Unsupported algorithm in the export."))
            }
            let digits: Int
            switch try values.number(5, default: 0) { case 1: digits = 6; case 2: digits = 8; default: throw AuthError.invalid(L10n.text("Unsupported code length.")) }
            let kind: OTPKind
            switch try values.number(6, default: 0) { case 1: kind = .hotp; case 2: kind = .totp; default: throw AuthError.invalid(L10n.text("Unsupported code type.")) }
            let label = try values.string(2), explicitIssuer = try values.string(3)
            let (labelIssuer, name) = splitLabel(label)
            let account = Account(name: name.isEmpty ? "Unnamed" : name, issuer: explicitIssuer.isEmpty ? labelIssuer : explicitIssuer, secret: try values.bytes(1), algorithm: algorithm, digits: digits, kind: kind, counter: try values.number(7, default: 0))
            try account.validate(); return account
        }
        guard !accounts.isEmpty, accounts.count <= 1000 else { throw AuthError.invalid(L10n.text("The export contains no accounts or too many accounts.")) }
        return ImportPart(accounts: accounts, batchID: id, batchSize: Int(size), batchIndex: Int(index))
    }
}
private struct Proto {
    enum Value { case number(UInt64), bytes(Data) }
    var tag: Int
    var value: Value
    static func fields(_ data: Data) throws -> [Proto] {
        let bytes = Array(data); var cursor = 0; var fields: [Proto] = []
        func varint() throws -> UInt64 {
            var result: UInt64 = 0
            for shift in stride(from: 0, through: 63, by: 7) {
                guard cursor < bytes.count else { throw AuthError.invalid(L10n.text("Truncated export data.")) }
                let byte = bytes[cursor]; cursor += 1
                guard shift < 63 || byte <= 1 else { throw AuthError.invalid(L10n.text("Overflow in export data.")) }
                result |= UInt64(byte & 127) << shift
                if byte & 128 == 0 { return result }
            }
            throw AuthError.invalid(L10n.text("Invalid export data."))
        }
        while cursor < bytes.count {
            let key = try varint(), tag = key >> 3, wire = key & 7
            guard tag > 0, tag <= 0x1fffffff else { throw AuthError.invalid(L10n.text("Invalid export field.")) }
            switch wire {
            case 0: fields.append(Proto(tag: Int(tag), value: .number(try varint())))
            case 2:
                let length = try varint()
                guard length <= UInt64(bytes.count - cursor) else { throw AuthError.invalid(L10n.text("Truncated export data.")) }
                fields.append(Proto(tag: Int(tag), value: .bytes(Data(bytes[cursor..<cursor+Int(length)])))); cursor += Int(length)
            case 1, 5:
                let count = wire == 1 ? 8 : 4
                guard count <= bytes.count - cursor else { throw AuthError.invalid(L10n.text("Truncated export data.")) }; cursor += count
            default: throw AuthError.invalid(L10n.text("Unsupported export format."))
            }
        }
        return fields
    }
}
private extension Array where Element == Proto {
    func unique(_ tag: Int) throws -> Proto.Value? {
        let matches = filter { $0.tag == tag }
        guard matches.count <= 1 else { throw AuthError.invalid(L10n.text("Duplicate export field.")) }; return matches.first?.value
    }
    func number(_ tag: Int, default fallback: UInt64) throws -> UInt64 {
        guard let value = try unique(tag) else { return fallback }
        guard case .number(let number) = value else { throw AuthError.invalid(L10n.text("Invalid export field.")) }; return number
    }
    func bytes(_ tag: Int) throws -> Data {
        guard let value = try unique(tag) else { return Data() }
        guard case .bytes(let bytes) = value else { throw AuthError.invalid(L10n.text("Invalid export field.")) }; return bytes
    }
    func string(_ tag: Int) throws -> String {
        guard let value = String(data: try bytes(tag), encoding: .utf8) else { throw AuthError.invalid(L10n.text("Invalid export text.")) }; return value
    }
}
