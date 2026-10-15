import CryptoKit
import CoreImage
import AppKit
import AuthenticatorCore

final class AuthenticatorTests {
    func testRFC4226HOTP() throws {
        let expected = ["755224","287082","359152","969429","338314","254676","287922","162583","399871","520489"]
        for (counter, code) in expected.enumerated() {
            let account = Account(name: "RFC4226", secret: Data("12345678901234567890".utf8), kind: .hotp, counter: UInt64(counter))
            expectEqual(try account.code(), code)
        }
    }
    func testRFC6238AllAlgorithms() throws {
        let times: [TimeInterval] = [59,1111111109,1111111111,1234567890,2000000000,20000000000]
        let vectors: [(Algorithm,String,[String])] = [
            (.sha1,"12345678901234567890",["94287082","07081804","14050471","89005924","69279037","65353130"]),
            (.sha256,"12345678901234567890123456789012",["46119246","68084774","67062674","91819424","90698825","77737706"]),
            (.sha512,"1234567890123456789012345678901234567890123456789012345678901234",["90693936","25091201","99943326","93441116","38618901","47863826"])
        ]
        for (algorithm, secret, codes) in vectors {
            let account = Account(name: "RFC6238", secret: Data(secret.utf8), algorithm: algorithm, digits: 8)
            for (time, expected) in zip(times,codes) { expectEqual(try account.code(at: Date(timeIntervalSince1970: time)), expected) }
        }
    }
    func testBase32AndMalformedInputs() throws {
        expectEqual(try Base32.decode("JBSWY3DPEHPK3PXP"), Data([72,101,108,108,111,33,222,173,190,239]))
        expectEqual(try Base32.decode("mzxw6=== \n"), Data("foo".utf8))
        for input in ["", "A", "MZ", "M=ZXW6", "!!!!", "012345"] { expectThrows(try Base32.decode(input)) }
    }
    func testStandardURI() throws {
        let account = try OTPImport.parseURI("otpauth://totp/ACME:alice%40example.com?secret=JBSWY3DPEHPK3PXP&issuer=ACME&algorithm=SHA256&digits=8&period=60").accounts[0]
        expectEqual(account.issuer, "ACME"); expectEqual(account.name, "alice@example.com")
        expectEqual(account.period,60); expectEqual(account.algorithm,.sha256); expectEqual(account.digits,8)
        let counter = try OTPImport.parseURI("otpauth://hotp/alice?secret=JBSWY3DPEHPK3PXP&counter=42").accounts[0]
        expectEqual(counter.counter,42); expectEqual(counter.kind,.hotp)
        for suffix in ["&period=0","&digits=7","&algorithm=MD5","&digits=x","&secret=AAAA", "&issuer=other"] {
            expectThrows(try OTPImport.parseURI("otpauth://totp/ACME:alice?secret=JBSWY3DPEHPK3PXP" + suffix))
        }
        expectThrows(try OTPImport.parseURI("otpauth://hotp/alice?secret=JBSWY3DPEHPK3PXP"))
    }
    // Independent wire fixture produced by Python's protobuf-compatible encoder in scripts/make-fixtures.py.
    func testMigrationWireFixture() throws {
        let part = try OTPImport.parseURI(fixture("migration.txt"))
        expectEqual(part.batchSize, 1); expectEqual(part.accounts.count, 2)
        expectEqual(part.accounts[0].issuer, "Google"); expectEqual(part.accounts[0].name, "alice@example.com")
        expectEqual(try part.accounts[0].code(at: Date(timeIntervalSince1970:59)), "287082")
        expectEqual(part.accounts[1].kind,.hotp); expectEqual(part.accounts[1].counter,42)
        expectEqual(part.accounts[1].algorithm,.sha256); expectEqual(part.accounts[1].digits,8)
        expectEqual(try part.accounts[1].code(), "63034454")
    }
    func testBatchAssemblyAndDuplicateDetection() throws {
        let first = try OTPImport.parseURI(fixture("batch-1.txt")), second = try OTPImport.parseURI(fixture("batch-2.txt"))
        var session = ImportSession()
        try session.add([second]); expectEqual(session.missingParts,1)
        try session.add([second]); expectEqual(session.missingParts,1); expectEqual(session.partCount,1)
        try session.add([first]); expectEqual(session.missingParts,0); expectEqual(session.accounts.count,2)
        try session.add([try OTPImport.parseURI(fixture("migration.txt"))]); expectEqual(session.accounts.count,2)
        var conflict = first; conflict.accounts[0].name = "different"
        expectThrows(try session.add([conflict])); expectEqual(session.accounts.count,2)
    }
    func testVersion2WithoutBatchID() throws {
        let first = try OTPImport.parseURI(fixture("v2-1.txt")), second = try OTPImport.parseURI(fixture("v2-2.txt"))
        let unnamed = try OTPImport.parseURI(fixture("v2-empty-name.txt")).accounts[0]
        expectEqual(unnamed.name, "Без названия"); expectEqual(unnamed.issuer, "Example")
        expectEqual(first.batchID, nil)
        var session = ImportSession()
        try session.add([second]); expectEqual(session.missingParts, 1)
        try session.add([first]); expectEqual(session.missingParts, 0)
        expectEqual(session.accounts.count, 2)
        expectEqual(try first.accounts[0].code(at: Date(timeIntervalSince1970: 59)), "287082")
        expectEqual(try second.accounts[0].code(), "63034454")
    }
    func testMalformedMigrationIsAtomic() throws {
        let valid = fixture("migration.txt")
        for encoded in ["", "not-base64", "Cg==", "CgX/", "AA==", "/////////////////////w=="] {
            expectThrows(try OTPImport.parseURI("otpauth-migration://offline?data=" + encoded))
        }
        expectThrows(try OTPImport.parse(text: valid + "\nhttps://example.com"))
        expectThrows(try OTPImport.parseURI(fixture("unsupported.txt")))
        expectThrows(try OTPImport.parseURI(fixture("invalid-batch.txt")))
    }
    func testQRImageThroughImportAndCodeGeneration() throws {
        let uri = fixture("migration.txt")
        let generator = CIFilter(name: "CIQRCodeGenerator")!
        generator.setValue(Data(uri.utf8), forKey: "inputMessage"); generator.setValue("M", forKey: "inputCorrectionLevel")
        let qr = generator.outputImage!.transformed(by: CGAffineTransform(scaleX: 8,y: 8))
        let background = CIImage(color: CIColor.white).cropped(to: qr.extent.insetBy(dx: -32, dy: -32))
        let output = qr.composited(over: background)
        let data = CIContext().pngRepresentation(of: output, format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())!
        let decoded = try QRImport.messages(in:data)
        expectEqual(decoded, [uri])
        let account = try OTPImport.parse(text: decoded[0])[0].accounts[0]
        expectEqual(try account.code(at: Date(timeIntervalSince1970:59)),"287082")
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        try data.write(to: tmp); defer { try? FileManager.default.removeItem(at:tmp) }
        expectEqual(try QRImport.read(url:tmp)[0].accounts.count,2)
        // Keep a public synthetic fixture for the GUI smoke test; contains no user data.
        if let location = ProcessInfo.processInfo.environment["QR_FIXTURE_OUTPUT"] { try data.write(to: URL(fileURLWithPath: location)) }
    }
    func testKeychainRoundTripAndUpdate() throws {
        let vault = Vault(service: "local.macauthenticator.test." + UUID().uuidString)
        defer { try? vault.delete() }
        expectEqual(try vault.load(),[])
        var accounts = try OTPImport.parseURI(fixture("migration.txt")).accounts
        try vault.save(accounts); expectEqual(try vault.load(),accounts)
        accounts[1].counter += 1; try vault.save(accounts)
        expectEqual(try vault.load()[1].counter,43)
        try vault.save([]); expectEqual(try vault.load(),[])
    }
    func testTOTPBoundaryAndValidation() throws {
        let account = Account(name: "RFC", secret:Data("12345678901234567890".utf8))
        expectEqual(try account.code(at: Date(timeIntervalSince1970:29)),"755224")
        expectEqual(try account.code(at: Date(timeIntervalSince1970:30)),"287082")
        expectThrows(try account.code(at: Date(timeIntervalSince1970:-1)))
        var invalid = account; invalid.period = 0; expectThrows(try invalid.code())
        invalid = account; invalid.secret = Data(); expectThrows(try invalid.code())
    }
    private func fixture(_ name: String) -> String {
        let path = URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/" + name)
        return try! String(contentsOf:path,encoding:.utf8).trimmingCharacters(in:.whitespacesAndNewlines)
    }
}

private var failures = 0
private var assertions = 0
func expectEqual<T: Equatable>(_ actual: @autoclosure () throws -> T, _ expected: T, file: StaticString = #filePath, line: UInt = #line) {
    assertions += 1
    do { if try actual() != expected { failures += 1; print("FAIL equality at line \(line)") } }
    catch { failures += 1; print("FAIL unexpected error at line \(line): \(error.localizedDescription)") }
}
func expectThrows<T>(_ expression: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
    assertions += 1
    do { _ = try expression(); failures += 1; print("FAIL expected rejection at line \(line)") } catch {}
}
if CommandLine.arguments.dropFirst().first == "--inspect-import" {
    do {
        var session = ImportSession()
        for path in CommandLine.arguments.dropFirst(2) {
            let parts = try QRImport.read(url: URL(fileURLWithPath: path))
            try session.add(parts)
            for part in parts { print("QR: accounts=\(part.accounts.count), part=\(part.batchIndex + 1)/\(part.batchSize)") }
        }
        for account in session.accounts { _ = try account.code() }
        print("TOTAL accounts=\(session.accounts.count), missing_parts=\(session.missingParts); all codes generated")
        exit(0)
    } catch { print("Import check failed: \(error.localizedDescription)"); exit(1) }
}
let suite = AuthenticatorTests()
let checks: [(String, () throws -> Void)] = [
    ("RFC 4226 HOTP", suite.testRFC4226HOTP),
    ("RFC 6238 SHA1/SHA256/SHA512", suite.testRFC6238AllAlgorithms),
    ("Base32 validation", suite.testBase32AndMalformedInputs),
    ("Standard otpauth URIs", suite.testStandardURI),
    ("Google migration wire fixture", suite.testMigrationWireFixture),
    ("Multi-QR batches and duplicates", suite.testBatchAssemblyAndDuplicateDetection),
    ("Version 2 anonymous multi-QR export", suite.testVersion2WithoutBatchID),
    ("Malformed migration rejection", suite.testMalformedMigrationIsAtomic),
    ("QR image to OTP end to end", suite.testQRImageThroughImportAndCodeGeneration),
    ("Keychain persistence and update", suite.testKeychainRoundTripAndUpdate),
    ("TOTP boundaries and validation", suite.testTOTPBoundaryAndValidation)
]
for (name, check) in checks {
    let before = failures
    do { try check() } catch { failures += 1; print("FAIL \(name): \(error.localizedDescription)") }
    print("\(before == failures ? "PASS" : "FAIL") \(name)")
}
print("\(checks.count) groups, \(assertions) assertions, \(failures) failures")
exit(failures == 0 ? 0 : 1)
